{ pkgs, ... }:

let
  # Pulls a Google Calendar "secret address in iCal format" feed and flattens
  # it into ~/.local/share/coel/gcal-events.json, in the same
  # {date,start,end,title,where,cal} shape the desktop calendar widget and the
  # panel calendar dropdown already read. Written to its own file, not
  # events.json, so a sync never clobbers hand-written events; the todos in the
  # panel dropdown stay in their local SQLite db and are never touched.
  #
  # The feed URL is a bearer secret (anyone holding it can read the calendar),
  # so it lives outside this repo in ~/.config/coel/gcal-url, one URL per line
  # (blank lines and #comments ignored). Missing file = silent no-op.
  # A line may start with a label: `class https://...`. Its events get that
  # label as `cal` (unlabelled feeds are "google"); a `class` feed is what
  # drives Class mode (home/quickshell/modes/Modes.qml), so deadlines from the
  # school's LMS feed never count as being in class.
  gcalSync = pkgs.writers.writePython3Bin "coel-gcal-sync"
    {
      libraries = with pkgs.python3Packages; [ icalendar recurring-ical-events ];
      flakeIgnore = [ "E501" "E741" ];
    }
    ''
      import datetime as dt
      import json
      import os
      import sys
      import urllib.request

      import icalendar
      import recurring_ical_events

      HOME = os.path.expanduser("~")
      URLS = os.path.join(
          os.environ.get("XDG_CONFIG_HOME", HOME + "/.config"), "coel/gcal-url")
      OUT = os.path.join(
          os.environ.get("COEL_DATA_DIR", HOME + "/.local/share/coel"),
          "gcal-events.json")

      if not os.path.exists(URLS):
          sys.exit(0)

      feeds = []  # (label, url)
      for line in open(URLS):
          parts = line.split()
          if not parts or parts[0].startswith("#"):
              continue
          if len(parts) >= 2 and "://" not in parts[0]:
              feeds.append((parts[0], parts[1]))
          else:
              feeds.append(("google", parts[0]))

      today = dt.date.today()
      start = today - dt.timedelta(days=60)
      end = today + dt.timedelta(days=366)


      def local(v):
          # aware -> local wall clock; floating (naive) is taken as local
          if v.tzinfo is not None:
              v = v.astimezone()
          return v.replace(tzinfo=None)


      def fetch(url):
          req = urllib.request.Request(url, headers={"User-Agent": "coel-gcal-sync"})
          with urllib.request.urlopen(req, timeout=30) as r:
              return icalendar.Calendar.from_ical(r.read())


      # Feeds fail independently. A label with any failed feed keeps its events
      # from the last good sync, so a network hiccup on the class feed can't
      # silently drop Class mode (or wipe the deadlines). Errors name the label
      # only: the URL itself is a secret.
      try:
          previous = json.load(open(OUT))
      except (OSError, ValueError):
          previous = []
      events, failed = [], set()
      for label, url in feeds:
          try:
              cal = fetch(url)
          except Exception as err:
              print(f"coel-gcal-sync: feed '{label}' failed: {err}", file=sys.stderr)
              failed.add(label)
              continue
          for e in recurring_ical_events.of(cal).between(start, end):
              if str(e.get("STATUS", "")).upper() == "CANCELLED":
                  continue
              s = e["DTSTART"].dt
              f = e["DTEND"].dt if "DTEND" in e else s
              title = str(e.get("SUMMARY", "(no title)"))
              where = str(e.get("LOCATION", "")).split("\n")[0]
              if not isinstance(s, dt.datetime):
                  # all-day: DTEND is exclusive; one entry per day covered
                  d = s
                  while d < max(f, s + dt.timedelta(days=1)):
                      events.append(dict(date=d.isoformat(), start="", end="",
                                         title=title, where=where, cal=label))
                      d += dt.timedelta(days=1)
              else:
                  s, f = local(s), local(f)
                  events.append(dict(date=s.date().isoformat(),
                                     start=s.strftime("%H:%M"),
                                     end=f.strftime("%H:%M"),
                                     title=title, where=where, cal=label))

      events = [e for e in events if e["cal"] not in failed]
      events += [e for e in previous if e.get("cal") in failed]
      events.sort(key=lambda x: (x["date"], x["start"]))
      os.makedirs(os.path.dirname(OUT), exist_ok=True)
      tmp = OUT + ".tmp"
      with open(tmp, "w") as fh:
          json.dump(events, fh, indent=1)
      os.replace(tmp, OUT)  # atomic, so the FileView watchers never see a torn file
      sys.exit(1 if failed else 0)
    '';
in
{
  home.packages = [ gcalSync ];

  systemd.user.services.gcal-sync = {
    Unit = {
      Description = "Sync Google Calendar iCal feed for the quickshell calendars";
      After = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${gcalSync}/bin/coel-gcal-sync";
    };
  };

  systemd.user.timers.gcal-sync = {
    Unit.Description = "Periodically sync Google Calendar";
    Timer = {
      OnBootSec = "1min";
      OnUnitActiveSec = "15min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
