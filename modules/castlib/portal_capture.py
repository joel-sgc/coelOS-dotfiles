"""Screen capture through the xdg-desktop-portal ScreenCast API.

The portal (xdg-desktop-portal-hyprland here, with our Quickshell picker)
asks the user what to share, then hands back a PipeWire node and a file
descriptor to the PipeWire connection. GStreamer's `pipewiresrc fd=N path=NODE`
consumes exactly that. The D-Bus session must stay open while streaming: when
it closes, the portal ends the screencast.

    cap = await open_screencast(loop, log)
    ... run gst-launch with cap.fd and cap.node (pass_fds=(cap.fd,)) ...
    await cap.close()
"""

import asyncio
import os
import secrets

PORTAL = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
SCREENCAST = "org.freedesktop.portal.ScreenCast"
REQUEST = "org.freedesktop.portal.Request"
SESSION = "org.freedesktop.portal.Session"

SOURCE_MONITOR = 1
SOURCE_WINDOW = 2
CURSOR_EMBEDDED = 2


class CaptureError(Exception):
    pass


class Capture:
    def __init__(self, bus, session, fd, node):
        self.bus = bus
        self.session = session
        self.fd = fd
        self.node = node

    async def close(self):
        from dbus_fast import Message
        try:
            os.close(self.fd)
        except OSError:
            pass
        try:
            await self.bus.call(Message(destination=PORTAL, path=self.session, interface=SESSION, member="Close"))
        except Exception:
            pass
        self.bus.disconnect()


def request_path(bus, token):
    """Where the portal will publish the Response for a call made with this handle_token."""
    sender = bus.unique_name.lstrip(":").replace(".", "_")
    return "/org/freedesktop/portal/desktop/request/%s/%s" % (sender, token)


async def open_screencast(loop, log, timeout=180, source_types=SOURCE_MONITOR | SOURCE_WINDOW, bus=None):
    """Run CreateSession / SelectSources / Start / OpenPipeWireRemote. `bus` is
    injectable for tests; normally a fresh session-bus connection."""
    from dbus_fast import BusType, Message, MessageType, Variant
    from dbus_fast.aio import MessageBus

    if bus is None:
        bus = await MessageBus(bus_type=BusType.SESSION, negotiate_unix_fd=True).connect()
    waiters = {}

    def on_message(msg):
        if msg.message_type == MessageType.SIGNAL and msg.interface == REQUEST and msg.member == "Response":
            fut = waiters.get(msg.path)
            if fut and not fut.done():
                fut.set_result(msg.body)

    bus.add_message_handler(on_message)
    await bus.call(Message(destination="org.freedesktop.DBus", path="/org/freedesktop/DBus",
                           interface="org.freedesktop.DBus", member="AddMatch", signature="s",
                           body=["type='signal',interface='%s',member='Response'" % REQUEST]))

    async def portal_call(member, signature, body, token):
        """Call a portal method that answers through a Request/Response, return its results."""
        path = request_path(bus, token)
        fut = loop.create_future()
        waiters[path] = fut                       # register before calling: the Response can be instant
        reply = await bus.call(Message(destination=PORTAL, path=PORTAL_PATH, interface=SCREENCAST,
                                       member=member, signature=signature, body=body))
        if reply.message_type == MessageType.ERROR:
            raise CaptureError("%s: %s" % (member, reply.body[0] if reply.body else reply.error_name))
        try:
            code, results = await asyncio.wait_for(fut, timeout)
        except asyncio.TimeoutError:
            raise CaptureError("%s: no answer from the portal" % member)
        finally:
            waiters.pop(path, None)
        if code == 1:
            raise CaptureError("screen sharing was cancelled")
        if code != 0:
            raise CaptureError("%s failed (portal response %d)" % (member, code))
        return results

    def token():
        return "miracast_" + secrets.token_hex(4)

    try:
        t = token()
        res = await portal_call("CreateSession", "a{sv}", [{
            "handle_token": Variant("s", t), "session_handle_token": Variant("s", token())}], t)
        session = res["session_handle"].value
        log("portal session %s" % session)

        t = token()
        await portal_call("SelectSources", "oa{sv}", [session, {
            "handle_token": Variant("s", t), "types": Variant("u", source_types),
            "multiple": Variant("b", False), "cursor_mode": Variant("u", CURSOR_EMBEDDED)}], t)

        t = token()
        log("waiting for you to pick what to share")
        res = await portal_call("Start", "osa{sv}", [session, "", {"handle_token": Variant("s", t)}], t)
        streams = res["streams"].value
        if not streams:
            raise CaptureError("the portal returned no streams")
        node = streams[0][0]

        reply = await bus.call(Message(destination=PORTAL, path=PORTAL_PATH, interface=SCREENCAST,
                                       member="OpenPipeWireRemote", signature="oa{sv}", body=[session, {}]))
        if reply.message_type == MessageType.ERROR or not reply.unix_fds:
            raise CaptureError("OpenPipeWireRemote failed: %s" % (reply.body[0] if reply.body else "no fd"))
        fd = reply.unix_fds[reply.body[0]]
        os.set_inheritable(fd, True)
        log("screencast ready: pipewire node %s" % node)
        return Capture(bus, session, fd, node)
    except BaseException:
        bus.disconnect()
        raise
