"""Wi-Fi Display (Miracast) source protocol: RTSP framing and capability negotiation.

Pure logic, no sockets and no GStreamer, so it can be unit tested. The source
role in WFD is odd: the *sink* opens the TCP connection to us (port 7236), but
once connected *we* send the first requests (M1, M3, M4, M5) and the sink sends
the rest (M2, M6, M7, keep-alives).

  M1  src -> sink  OPTIONS            (we ask what it supports)
  M2  sink -> src  OPTIONS            (it asks what we support)
  M3  src -> sink  GET_PARAMETER      (read its video/audio capabilities)
  M4  src -> sink  SET_PARAMETER      (pick format, ports, presentation URL)
  M5  src -> sink  SET_PARAMETER      (wfd_trigger_method: SETUP)
  M6  sink -> src  SETUP              (it names its RTP port; we reply with ours)
  M7  sink -> src  PLAY               (stream now)
  M16 sink -> src  GET_PARAMETER      (keep-alive)
  M8  either       TEARDOWN
"""

import re
CRLF = "\r\n"

# CEA-861 resolution table used by wfd_video_formats (bit index -> (w, h, fps, interlaced)).
CEA_MODES = {
    0: (640, 480, 60, False),
    1: (720, 480, 60, False),
    2: (720, 480, 60, True),
    3: (720, 576, 50, False),
    4: (720, 576, 50, True),
    5: (1280, 720, 30, False),
    6: (1280, 720, 60, False),
    7: (1920, 1080, 30, False),
    8: (1920, 1080, 60, False),
    9: (1920, 1080, 60, True),
    10: (1280, 720, 25, False),
    11: (1280, 720, 50, False),
    12: (1920, 1080, 25, False),
    13: (1920, 1080, 50, False),
    14: (1920, 1080, 50, True),
    15: (1280, 720, 24, False),
    16: (1920, 1080, 24, False),
}

# H.264 profile bits (CBP = constrained baseline, CHP = constrained high) and level bits.
PROFILE_CBP = 0x01
PROFILE_CHP = 0x02
LEVELS = {0x01: "3.1", 0x02: "3.2", 0x04: "4", 0x08: "4.1", 0x10: "4.2"}

# H.264 level limits: max macroblocks per second. A mode only fits a level if its
# macroblock rate is within it (1080p30 needs level 4.0; level 3.1 is 720p30 at most).
LEVEL_MAX_MBPS = {0x01: 108000, 0x02: 216000, 0x04: 245760, 0x08: 245760, 0x10: 522240}


def macroblock_rate(cea_bit):
    w, h, fps, _ = CEA_MODES[cea_bit]
    return -(-w // 16) * -(-h // 16) * fps


def fits_level(cea_bit, level_bit):
    return macroblock_rate(cea_bit) <= LEVEL_MAX_MBPS[level_bit]


# VESA and "handheld" (HH) resolution tables of the Wi-Fi Display spec. Displays advertise them next to the CEA bitmap;
# we can read them (they are listed in `coel-miracast info`) but only *produce* CEA modes.
VESA_MODES = {
    0: (800, 600, 30, False), 1: (800, 600, 60, False), 2: (1024, 768, 30, False), 3: (1024, 768, 60, False),
    4: (1152, 864, 30, False), 5: (1152, 864, 60, False), 6: (1280, 768, 30, False), 7: (1280, 768, 60, False),
    8: (1280, 800, 30, False), 9: (1280, 800, 60, False), 10: (1360, 768, 30, False), 11: (1360, 768, 60, False),
    12: (1366, 768, 30, False), 13: (1366, 768, 60, False), 14: (1280, 1024, 30, False), 15: (1280, 1024, 60, False),
    16: (1400, 1050, 30, False), 17: (1400, 1050, 60, False), 18: (1440, 900, 30, False), 19: (1440, 900, 60, False),
    20: (1600, 900, 30, False), 21: (1600, 900, 60, False), 22: (1600, 1200, 30, False), 23: (1600, 1200, 60, False),
    24: (1680, 1024, 30, False), 25: (1680, 1024, 60, False), 26: (1680, 1050, 30, False), 27: (1680, 1050, 60, False),
    28: (1920, 1200, 30, False),
}
HH_MODES = {
    0: (800, 480, 30, False), 1: (800, 480, 60, False), 2: (854, 480, 30, False), 3: (854, 480, 60, False),
    4: (864, 480, 30, False), 5: (864, 480, 60, False), 6: (640, 360, 30, False), 7: (640, 360, 60, False),
    8: (960, 540, 30, False), 9: (960, 540, 60, False), 10: (848, 480, 30, False), 11: (848, 480, 60, False),
}


def mode_name(width, height, fps, interlaced=False):
    """'1080p30', '720p60', '1080i50'; other sizes spelled out: '720x480p60', '1600x1200p30'."""
    std = {(1280, 720): "720", (1920, 1080): "1080"}
    suffix = "i" if interlaced else "p"
    if (width, height) in std:
        return "%s%s%d" % (std[(width, height)], suffix, fps)
    return "%dx%d%s%d" % (width, height, suffix, fps)


def parse_mode_name(text):
    """Inverse of mode_name; also accepts '1920x1080@30' and 'WxH@F'. Returns (w, h, fps, interlaced)."""
    t = text.strip().lower().replace(" ", "")
    m = re.fullmatch(r"(720|1080)([pi])(\d+)", t)
    if m:
        w, h = (1280, 720) if m.group(1) == "720" else (1920, 1080)
        return w, h, int(m.group(3)), m.group(2) == "i"
    m = re.fullmatch(r"(\d+)x(\d+)([pi@])(\d+)", t)
    if m:
        return int(m.group(1)), int(m.group(2)), int(m.group(4)), m.group(3) == "i"
    raise ValueError("not a mode name: %r (examples: 1080p30, 720p60, 720x480p60)" % text)


def cea_bit_for(text):
    """CEA bitmap bit for a mode name such as '720p30'. Raises ValueError if it is not a CEA mode."""
    mode = parse_mode_name(text)
    for bit, m in CEA_MODES.items():
        if m == mode:
            return bit
    raise ValueError("%s is not a mode we can produce (CEA modes: %s)" % (
        text, ", ".join(mode_name(*m) for m in CEA_MODES.values())))


def parse_preference(value):
    """Preference list for the video mode, best first. Names ('1080p30,720p60') or legacy CEA bit numbers ('7,5');
    a string with commas or a list. Returns CEA bits."""
    items = value if isinstance(value, (list, tuple)) else str(value).split(",")
    bits = []
    for item in items:
        if isinstance(item, int):
            bits.append(item)
            continue
        item = item.strip()
        if not item:
            continue
        bits.append(int(item) if item.isdigit() else cea_bit_for(item))
    return bits


# What we ask for, best first: 1080p30, 720p30, 720p60, 1080p60, 480p60, 640x480p60.
DEFAULT_PREFERENCE = [7, 5, 6, 8, 1, 0]


def describe_modes(entries):
    """Every resolution/rate the display offers in its video formats (all three tables), as a list of dicts."""
    out, seen = [], set()
    for e in entries:
        for table, modes, key in (("cea", CEA_MODES, "cea"), ("vesa", VESA_MODES, "vesa"), ("hh", HH_MODES, "hh")):
            for bit, (w, h, fps, interlaced) in modes.items():
                if (e.get(key, 0) >> bit) & 1 and (table, bit) not in seen:
                    seen.add((table, bit))
                    out.append({"name": mode_name(w, h, fps, interlaced), "width": w, "height": h, "fps": fps,
                                "interlaced": interlaced, "table": table, "bit": bit,
                                "usable": table == "cea"})
    return out


def rank_modes(entries, preference=None, strict=False):
    """The display's modes in the order we would pick them: first those in `preference` (best first), then the other
    modes we can produce, then the ones we can only read (VESA / handheld). Each gets `rank` (1 = chosen) or None."""
    pref = parse_preference(DEFAULT_PREFERENCE if preference is None else preference)
    modes = describe_modes(entries)
    levels = 0
    for e in entries:
        levels |= e.get("level", 0)

    def usable(m):
        if m["table"] != "cea":
            return False
        return not strict or any(levels & b and fits_level(m["bit"], b) for b in LEVELS)

    cea = [m for m in modes if m["table"] == "cea"]
    ordered = [m for b in pref for m in cea if m["bit"] == b]
    rest = [m for m in cea if m not in ordered]
    rest.sort(key=lambda m: (m["interlaced"], -m["width"] * m["height"], -m["fps"]))
    ranked, n = [], 0
    for m in ordered + rest:
        m = dict(m, in_preference=m in ordered)
        if usable(m):
            n += 1
            m["rank"] = n
        else:
            m["rank"] = None
        ranked.append(m)
    return ranked + [dict(m, in_preference=False, rank=None) for m in modes if m["table"] != "cea"]


def describe_sink(caps, preference=None, strict=False):
    """Everything the display told us in M3, decoded, with our ranking of its video modes."""
    entries = parse_video_formats(caps.get("wfd_video_formats", "none"))
    profiles = sorted({"constrained-baseline" if e["profile"] & PROFILE_CBP else "constrained-high"
                       for e in entries if e["profile"] & (PROFILE_CBP | PROFILE_CHP)})
    levels = sorted({LEVELS[b] for e in entries for b in LEVELS if e["level"] & b})
    return {
        "video_modes": rank_modes(entries, preference, strict),
        "h264_profiles": profiles,
        "h264_levels": levels,
        "audio_codecs": parse_audio_codecs(caps.get("wfd_audio_codecs")),
        "content_protection": caps.get("wfd_content_protection", "none"),
        "rtp_ports": caps.get("wfd_client_rtp_ports", ""),
    }


class RtspError(Exception):
    pass


class Message:
    """One RTSP request or response."""

    def __init__(self, start, headers, body=""):
        self.start = start            # "OPTIONS * RTSP/1.0"  or  "RTSP/1.0 200 OK"
        self.headers = headers        # dict, keys lower-cased
        self.body = body

    @property
    def is_response(self):
        return self.start.startswith("RTSP/")

    @property
    def method(self):
        return None if self.is_response else self.start.split(" ", 1)[0]

    @property
    def uri(self):
        parts = self.start.split(" ")
        return None if self.is_response or len(parts) < 2 else parts[1]

    @property
    def status(self):
        if not self.is_response:
            return None
        parts = self.start.split(" ", 2)
        return int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else None

    @property
    def cseq(self):
        try:
            return int(self.headers.get("cseq", ""))
        except ValueError:
            return None


def parse_message(raw):
    """Parse one complete message (str). Raises RtspError if malformed."""
    head, _, body = raw.partition(CRLF + CRLF)
    lines = head.split(CRLF)
    if not lines or not lines[0].strip():
        raise RtspError("empty message")
    headers = {}
    for line in lines[1:]:
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        headers[k.strip().lower()] = v.strip()
    return Message(lines[0].strip(), headers, body)


def message_length(buf):
    """If buf (bytes) holds a complete message return its byte length, else None."""
    end = buf.find(b"\r\n\r\n")
    if end < 0:
        return None
    head = buf[:end].decode("latin-1")
    length = 0
    for line in head.split("\r\n")[1:]:
        if line.lower().startswith("content-length:"):
            try:
                length = int(line.split(":", 1)[1].strip())
            except ValueError:
                raise RtspError("bad Content-Length")
    total = end + 4 + length
    return total if len(buf) >= total else None


def build_request(method, uri, cseq, headers=None, body=""):
    lines = ["%s %s RTSP/1.0" % (method, uri), "CSeq: %d" % cseq]
    for k, v in (headers or {}).items():
        lines.append("%s: %s" % (k, v))
    if body:
        lines.append("Content-Length: %d" % len(body.encode()))
    return (CRLF.join(lines) + CRLF + CRLF + body).encode()


def build_response(cseq, status=200, reason="OK", headers=None, body=""):
    lines = ["RTSP/1.0 %d %s" % (status, reason), "CSeq: %d" % cseq]
    for k, v in (headers or {}).items():
        lines.append("%s: %s" % (k, v))
    if body:
        lines.append("Content-Length: %d" % len(body.encode()))
    return (CRLF.join(lines) + CRLF + CRLF + body).encode()


def parse_params(body):
    """'text/parameters' body -> dict of name -> value string."""
    out = {}
    for line in body.replace("\r", "").split("\n"):
        line = line.strip()
        if not line or ":" not in line:
            continue
        k, v = line.split(":", 1)
        out[k.strip()] = v.strip()
    return out


# ---------------------------------------------------------------------------
# video format negotiation
# ---------------------------------------------------------------------------

def parse_video_formats(value):
    """Parse a sink's wfd_video_formats into a list of codec entries.

    value like: '38 00 02 02 0001FFFF 1CFFFFFF 00000FFF 00 0000 0000 00 none none'
    (native, preferred-display-mode, then one or more H.264 codec entries which
    the sink may separate with ', '). Returns [] when the sink says 'none'.
    """
    value = value.strip()
    if value.lower() == "none" or not value:
        return []
    parts = value.split(",")
    entries = []
    for idx, part in enumerate(parts):
        f = part.split()
        if idx == 0:
            f = f[2:]          # drop native + preferred-display-mode
        if len(f) < 10:
            continue
        try:
            entries.append({
                "profile": int(f[0], 16),
                "level": int(f[1], 16),
                "cea": int(f[2], 16),
                "vesa": int(f[3], 16),
                "hh": int(f[4], 16),
            })
        except ValueError:
            continue
    return entries


def choose_video(sink_entries, preference=None, max_level=0x08, strict=True):
    """Pick (profile_bit, level_bit, cea_bit) the sink supports, best preference first.

    Returns None if nothing in our preference list is supported.
    """
    preference = DEFAULT_PREFERENCE if preference is None else preference
    for e in sink_entries:
        for bit in preference:
            if not (e["cea"] >> bit) & 1:
                continue
            profile = PROFILE_CBP if e["profile"] & PROFILE_CBP else (PROFILE_CHP if e["profile"] & PROFILE_CHP else None)
            if profile is None:
                continue
            # highest level the sink supports (no more than we need: 4.1) that the
            # mode actually fits. Sinks routinely advertise a mode their own level
            # cannot carry (the Fire TV offers 1080p30 at level 3.1), and the
            # encoder refuses to produce that, so skip it.
            # strict=False trusts the advertised mode and ignores the level (we then
            # encode at the level the mode really needs; the sink's hardware decoder
            # only looks at the stream's own SPS).
            supported = [b for b in LEVELS if e["level"] & b and b <= max_level and (not strict or fits_level(bit, b))]
            level = max(supported) if supported else None
            if level is None:
                continue
            return profile, level, bit
    return None


def level_for_mode(mode, at_least):
    """Smallest level bit >= at_least that can carry the mode (for the encoder's caps)."""
    mbps = -(-mode["width"] // 16) * -(-mode["height"] // 16) * mode["fps"]
    for b in sorted(LEVEL_MAX_MBPS):
        if b >= at_least and mbps <= LEVEL_MAX_MBPS[b]:
            return b
    return max(LEVEL_MAX_MBPS)


# WFD audio codec mode bits we can produce: AAC-LC 48 kHz stereo (bit 0); LPCM 16-bit stereo 48 kHz (bit 1; the
# 44.1 kHz mode, bit 0, is not produced).
AUDIO_MODES = {"AAC": 0x1, "LPCM": 0x2}


def parse_audio_codecs(value):
    """'LPCM 00000002 00, AAC 00000001 00' -> [{'codec': 'LPCM', 'modes': 2, 'latency': 0}, ...]"""
    out = []
    for part in (value or "").split(","):
        f = part.split()
        if len(f) >= 2 and f[0].upper() in ("LPCM", "AAC", "AC3"):
            try:
                out.append({"codec": f[0].upper(), "modes": int(f[1], 16),
                            "latency": int(f[2], 16) if len(f) > 2 else 0})
            except ValueError:
                continue
    return out


def choose_audio_codec(value, preference=("AAC",)):
    """Pick the first codec in `preference` that the sink offers in a mode we can produce.
    Returns (codec, M4 value), or (None, 'none')."""
    offered = {e["codec"]: e for e in parse_audio_codecs(value)}
    for codec in preference:
        codec = codec.upper()
        e = offered.get(codec)
        if e and e["modes"] & AUDIO_MODES.get(codec, 0):
            bit = AUDIO_MODES[codec]
            return codec, "%s %08X 00" % (codec, bit)
    return None, "none"


def choose_audio(value, preference=("AAC",)):
    """M4 wfd_audio_codecs value (AAC-LC 48k stereo by default), or 'none'."""
    return choose_audio_codec(value, preference)[1]


def format_video_selection(profile, level, cea_bit):
    """The wfd_video_formats value for M4: exactly one mode selected."""
    return "00 00 %02X %02X %08X 00000000 00000000 00 0000 0000 00 none none" % (profile, level, 1 << cea_bit)


def mode_of(cea_bit):
    w, h, fps, interlaced = CEA_MODES[cea_bit]
    return {"width": w, "height": h, "fps": fps, "interlaced": interlaced}


# ---------------------------------------------------------------------------
# parameter blocks
# ---------------------------------------------------------------------------

M3_QUERY = CRLF.join([
    "wfd_content_protection",
    "wfd_video_formats",
    "wfd_audio_codecs",
    "wfd_client_rtp_ports",
]) + CRLF


def build_m4_body(local_ip, rtp_ports_value, video_value, audio_value="none", content_protection=None):
    """M4: the selection. rtp_ports_value is the sink's own (echoed back). content_protection:
    pass "none" when the sink advertised HDCP, to say explicitly that we send unprotected video."""
    lines = []
    if content_protection:
        lines.append("wfd_content_protection: %s" % content_protection)
    lines += [
        "wfd_video_formats: %s" % video_value,
        "wfd_audio_codecs: %s" % audio_value,
        "wfd_presentation_URL: rtsp://%s/wfd1.0/streamid=0 none" % local_ip,
        "wfd_client_rtp_ports: %s" % rtp_ports_value,
    ]
    return CRLF.join(lines) + CRLF


def parse_client_rtp_port(value):
    """'RTP/AVP/UDP;unicast 19000 0 mode=play' -> 19000"""
    parts = value.split()
    for p in parts[1:]:
        if p.isdigit():
            return int(p)
    raise RtspError("no RTP port in %r" % value)


def parse_transport_client_port(transport):
    """'RTP/AVP/UDP;unicast;client_port=19000' (or '19000-19001') -> 19000"""
    for chunk in transport.split(";"):
        chunk = chunk.strip()
        if chunk.startswith("client_port="):
            return int(chunk.split("=", 1)[1].split("-")[0])
    raise RtspError("no client_port in %r" % transport)


PUBLIC_M2 = "org.wfa.wfd1.0, GET_PARAMETER, SET_PARAMETER"


# ---------------------------------------------------------------------------
# AAC ADTS
# ---------------------------------------------------------------------------

def adts_to_mpeg2(buf):
    """Rewrite ADTS headers from the MPEG-4 form (ID bit 0, `FF F1`) to the MPEG-2 form (ID bit 1, `FF F9`)
    that AOSP's Wi-Fi Display source sends (0xff, 0xf9). Takes a byte buffer that may end mid-frame and returns
    (converted_complete_frames, remainder)."""
    out = bytearray()
    i, n = 0, len(buf)
    while i + 7 <= n:
        if buf[i] != 0xFF or (buf[i + 1] & 0xF0) != 0xF0:       # resync: not at a frame start
            i += 1
            continue
        length = ((buf[i + 3] & 0x03) << 11) | (buf[i + 4] << 3) | (buf[i + 5] >> 5)
        if length < 7:
            i += 1
            continue
        if i + length > n:
            break                                              # incomplete frame, wait for more
        frame = bytearray(buf[i:i + length])
        frame[1] |= 0x08                                       # ID = 1 (MPEG-2)
        out += frame
        i += length
    return bytes(out), bytes(buf[i:])


def split_adts(data):
    """Split a buffer of complete ADTS frames (as returned by adts_to_mpeg2) into single frames."""
    frames, i = [], 0
    while i + 7 <= len(data):
        length = ((data[i + 3] & 0x03) << 11) | (data[i + 4] << 3) | (data[i + 5] >> 5)
        if length < 7 or i + length > len(data):
            break
        frames.append(data[i:i + length])
        i += length
    return frames
