#!/usr/bin/env python3
"""A fake xdg-desktop-portal ScreenCast service on the *session* bus, for testing
engine/portal_capture.py without a compositor or a human.

  python3 mock_portal.py [--cancel]     --cancel makes Start answer "user cancelled"
"""
import argparse
import asyncio
import os
import sys

from dbus_fast import BusType, Variant
from dbus_fast.aio import MessageBus
from dbus_fast.service import ServiceInterface, method, signal

PATH = "/org/freedesktop/portal/desktop"
SESSION_PATH = "/org/freedesktop/portal/desktop/session/mock/s1"


class Request(ServiceInterface):
    def __init__(self):
        super().__init__("org.freedesktop.portal.Request")

    @signal()
    def Response(self, code: "u", results: "a{sv}") -> "ua{sv}":
        return [code, results]


class Session(ServiceInterface):
    closed = False

    def __init__(self):
        super().__init__("org.freedesktop.portal.Session")

    @method()
    def Close(self):
        Session.closed = True
        print("session closed", flush=True)


class ScreenCast(ServiceInterface):
    def __init__(self, bus, cancel):
        super().__init__("org.freedesktop.portal.ScreenCast")
        self.bus = bus
        self.cancel = cancel

    def _request(self, options, code, results, delay=0.1):
        sender = self.bus.unique_name  # (the mock answers as itself; the client derives the path from *its* name)
        token = options["handle_token"].value
        client = self._current_sender.lstrip(":").replace(".", "_")
        path = "/org/freedesktop/portal/desktop/request/%s/%s" % (client, token)
        req = Request()
        self.bus.export(path, req)
        asyncio.get_event_loop().call_later(delay, req.Response, code, results)
        return path

    @method()
    def CreateSession(self, options: "a{sv}", ) -> "o":
        return self._request(options, 0, {"session_handle": Variant("s", SESSION_PATH)})

    @method()
    def SelectSources(self, session: "o", options: "a{sv}") -> "o":
        print("SelectSources types=%s cursor=%s" % (options["types"].value, options["cursor_mode"].value), flush=True)
        return self._request(options, 0, {})

    @method()
    def Start(self, session: "o", parent: "s", options: "a{sv}") -> "o":
        if self.cancel:
            return self._request(options, 1, {}, delay=0.3)
        return self._request(options, 0, {"streams": Variant("a(ua{sv})", [[4242, {}]])}, delay=0.3)

    @method()
    def OpenPipeWireRemote(self, session: "o", options: "a{sv}") -> "h":
        r, w = os.pipe()
        return r


async def main():
    p = argparse.ArgumentParser()
    p.add_argument("--cancel", action="store_true")
    args = p.parse_args()
    bus = await MessageBus(bus_type=BusType.SESSION, negotiate_unix_fd=True).connect()
    sc = ScreenCast(bus, args.cancel)
    bus.export(PATH, sc)
    bus.export(SESSION_PATH, Session())
    # learn who is calling: dbus-fast hands the message to a handler, so record the sender
    def on_msg(msg):
        if msg.member in ("CreateSession", "SelectSources", "Start", "OpenPipeWireRemote"):
            sc._current_sender = msg.sender
    bus.add_message_handler(on_msg)
    await bus.request_name("org.freedesktop.portal.Desktop")
    print("mock portal ready", flush=True)
    await asyncio.get_event_loop().create_future()


if __name__ == "__main__":
    asyncio.run(main())
