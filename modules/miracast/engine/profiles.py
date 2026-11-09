"""Per-display quirk profiles.

What a display advertises (video formats, audio codecs) is negotiated from its capabilities. What it
*needs beyond that* (a longer audio start delay, a different bitrate, an audio codec preference, ...) cannot be
discovered, so it is declared here, as data:

    {"name": "roku", "match": {"manufacturer": "Roku"}, "settings": {"vbv_ms": 30}}

`match` conditions are ANDed; string values are case-insensitive regular expressions searched in the field. Known
fields: name, manufacturer, model, device_type (from the Wi-Fi Direct peer record), content_protection, audio_codecs
(from the display's wfd_ parameters). `settings` override engine options by their argparse `dest` name
(e.g. vbv_ms, bitrate, preset, audio_start_delay_ms, audio_preference, preference, color) unless the same option was
given explicitly on the command line. User profiles are tried before the built-in ones; the first match wins.
"""

import json
import re

# Built-in profiles. Empty `settings` documents a display that needs nothing special beyond the engine defaults,
# which already encode what we learned about it (see README: Roku reads the first PMT once, wants M16 keep-alives...).
BUILTIN = [
    {"name": "roku", "match": {"manufacturer": "Roku"}, "settings": {}},
    {"name": "fire-tv", "match": {"name": "Fire ?TV|AFT"}, "settings": {}},
]


def load(path):
    """Load a JSON list (or {name: profile} map) of profiles. Missing file -> []."""
    if not path:
        return []
    with open(path) as f:
        data = json.load(f)
    if isinstance(data, dict):
        data = [dict(v, name=k) for k, v in data.items()]
    for p in data:
        if "name" not in p:
            raise ValueError("profile without a name: %r" % (p,))
    return data


def _field(info, key):
    v = info.get(key)
    if isinstance(v, (list, tuple, set)):
        return " ".join(str(x) for x in v)
    return "" if v is None else str(v)


def matches(profile, info):
    for key, pattern in (profile.get("match") or {}).items():
        if not re.search(str(pattern), _field(info, key), re.IGNORECASE):
            return False
    return True


def match(profiles, info):
    """First profile whose conditions all match `info`, else None."""
    for p in profiles:
        if matches(p, info):
            return p
    return None


def apply(args, explicit, settings):
    """Set engine options from a profile's `settings`, skipping options given on the command line.
    Returns {option: value} of what was applied."""
    applied = {}
    for key, value in (settings or {}).items():
        if not hasattr(args, key):
            raise ValueError("profile sets unknown option %r" % key)
        if key in explicit:
            continue
        setattr(args, key, value)
        applied[key] = value
    return applied
