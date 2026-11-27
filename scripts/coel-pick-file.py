"""coel-pick-file [TITLE]: open the desktop portal's file chooser, print the chosen
paths one per line (nothing, exit 1, if cancelled). Used by the desktop's phone
card to send files over KDE Connect.

A real D-Bus client is needed because the portal answers with a Response signal
on a request object, and cancels requests whose caller has gone away, so a
one-shot `gdbus call` can't do it. The request path is predictable from our
unique name and handle_token, so we subscribe before calling OpenFile.
"""
import asyncio
import random
import sys
import urllib.parse

from dbus_next import Message, MessageType, Variant
from dbus_next.aio import MessageBus


async def main():
    bus = await MessageBus().connect()
    token = "coel%d" % random.randint(0, 1 << 30)
    sender = bus.unique_name[1:].replace(".", "_")
    path = f"/org/freedesktop/portal/desktop/request/{sender}/{token}"
    done = asyncio.get_running_loop().create_future()

    def on_message(msg):
        ours = msg.message_type == MessageType.SIGNAL and msg.member == "Response" and msg.path == path
        if ours and not done.done():
            done.set_result(msg.body)

    bus.add_message_handler(on_message)
    await bus.call(Message(
        destination="org.freedesktop.DBus", path="/org/freedesktop/DBus",
        interface="org.freedesktop.DBus", member="AddMatch", signature="s",
        body=[f"type='signal',interface='org.freedesktop.portal.Request',member='Response',path='{path}'"]))
    title = sys.argv[1] if len(sys.argv) > 1 else "Pick a file"
    options = {"handle_token": Variant("s", token), "multiple": Variant("b", True)}
    reply = await bus.call(Message(
        destination="org.freedesktop.portal.Desktop", path="/org/freedesktop/portal/desktop",
        interface="org.freedesktop.portal.FileChooser", member="OpenFile",
        signature="ssa{sv}", body=["", title, options]))
    if reply.message_type == MessageType.ERROR:
        print("coel-pick-file: " + str(reply.body), file=sys.stderr)
        return 2
    code, results = await done
    if code != 0:
        return 1
    uris = results["uris"].value if "uris" in results else []
    for uri in uris:
        print(urllib.parse.unquote(urllib.parse.urlparse(uri).path))
    return 0 if uris else 1


sys.exit(asyncio.run(main()))
