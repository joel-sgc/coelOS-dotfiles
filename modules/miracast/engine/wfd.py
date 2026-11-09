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


# What we ask for, best first (mode bit, label).
DEFAULT_PREFERENCE = [7, 5, 6, 8, 1, 0]


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


def choose_audio(value):
    """M4 wfd_audio_codecs value: AAC-LC 48k stereo if the sink offers it, else 'none'."""
    if value and "AAC" in value:
        for part in value.split(","):
            f = part.split()
            if len(f) >= 2 and f[0] == "AAC" and int(f[1], 16) & 1:
                return "AAC 00000001 00"
    return "none"


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
