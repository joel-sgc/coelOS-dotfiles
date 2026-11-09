"""Find Google Cast devices on the LAN (mDNS service _googlecast._tcp) with avahi.

`avahi-browse -rpt` prints one parsable line per resolved service:

    =;wlp1s0;IPv4;Chromecast-abc;_googlecast._tcp;local;abc.local;192.168.0.50;8009;"id=..." "fn=Living Room" "md=Chromecast" ...

TXT keys of interest: id (device uuid), fn (friendly name), md (model), ca (capability bits), ve, st.
"""

import asyncio
import re
import shutil

SERVICE = "_googlecast._tcp"


def parse_txt(raw):
    """'"id=abc" "fn=Living Room"' -> {'id': 'abc', 'fn': 'Living Room'} (avahi escapes bytes as \\DDD)."""
    out = {}
    for item in re.findall(r'"((?:[^"\\]|\\.)*)"', raw or ""):
        item = re.sub(r"\\(\d{3})", lambda m: chr(int(m.group(1))), item)
        k, _, v = item.partition("=")
        out[k] = v
    return out


def parse_browse(text):
    """Parse `avahi-browse -rpt _googlecast._tcp` output into a de-duplicated list of devices."""
    devices = {}
    for line in text.splitlines():
        f = line.split(";")
        if len(f) < 9 or f[0] != "=" or f[4] != SERVICE:
            continue
        proto, host, addr, port = f[2], f[6], f[7], f[8]
        txt = parse_txt(";".join(f[9:]))
        key = txt.get("id") or f[3]
        dev = devices.setdefault(key, {
            "id": txt.get("id", ""), "name": txt.get("fn") or f[3], "model": txt.get("md", ""),
            "host": host, "port": int(port or 8009), "addresses": [], "txt": txt})
        if addr and addr not in dev["addresses"]:
            # prefer IPv4: the devices are reachable on it and URLs we hand them are simpler
            (dev["addresses"].insert(0, addr) if proto == "IPv4" else dev["addresses"].append(addr))
    return sorted(devices.values(), key=lambda d: d["name"].lower())


async def browse(timeout=4.0, avahi_browse=None):
    """Browse live for `timeout` seconds (avahi-browse -t only dumps its cache, which is empty on a fresh network
    -- the same lesson as coel-cast-scan), then read the resolved list."""
    exe = avahi_browse or shutil.which("avahi-browse") or "avahi-browse"
    try:
        live = await asyncio.create_subprocess_exec(exe, "-rp", SERVICE, stdout=asyncio.subprocess.PIPE,
                                                    stderr=asyncio.subprocess.DEVNULL)
    except FileNotFoundError:
        raise RuntimeError("avahi-browse not found (enable services.avahi)")
    out = b""
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while True:                                  # keep what arrived: cancelling a single read() would drop it
        remaining = deadline - loop.time()
        if remaining <= 0:
            break
        try:
            chunk = await asyncio.wait_for(live.stdout.read(4096), remaining)
        except asyncio.TimeoutError:
            break
        if not chunk:
            break
        out += chunk
    if live.returncode is None:
        live.terminate()
        try:
            await asyncio.wait_for(live.wait(), 2)
        except asyncio.TimeoutError:
            live.kill()
    final = await asyncio.create_subprocess_exec(exe, "-rpt", SERVICE, stdout=asyncio.subprocess.PIPE,
                                                 stderr=asyncio.subprocess.DEVNULL)
    cached = (await final.communicate())[0]
    return parse_browse((out + b"\n" + cached).decode(errors="replace"))


def find(devices, query):
    """Pick a device by (part of) its name, model, id, host or address. Raises ValueError unless exactly one matches."""
    q = query.lower()
    exact = [d for d in devices if q in (d["name"].lower(), d["id"].lower(), d["host"].lower()) or q in d["addresses"]]
    if len(exact) == 1:
        return exact[0]
    part = [d for d in devices if q in d["name"].lower() or q in d["model"].lower()]
    if len(part) == 1:
        return part[0]
    if not part and not exact:
        raise ValueError("no Cast device matches %r" % query)
    raise ValueError("%r matches %d devices: %s" % (query, len(part or exact), ", ".join(d["name"] for d in (part or exact))))
