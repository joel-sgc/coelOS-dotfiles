{ pkgs, ... }:

# Boot-to-login seam: boots the real splash (modules/boot-splash.nix), the
# session hub and the real Quickshell greeter in a VM, grabs the screen as fast
# as QEMU allows from power-on until the greeter is up, and fails if any frame
# after the splash first appears is black, or is the bare backdrop colour
# without the splash's wordmark. Prints the frame timeline either way.
#
#   python3 tests/run.py boot-seam          (slow: boots a VM; opt-in, or use --all)
#
# The VM has no GPU, so cage and Quickshell render in software here (the
# environment overrides below); what's under test is who owns the screen when,
# not rendering.
{
  name = "boot-seam";

  nodes.machine = { lib, pkgs, ... }: {
    imports = [
      ../../modules/boot-splash.nix
      ../../modules/greeter.nix
      ../../modules/session-hub.nix
    ];
    services.qs-greeter.enable = true;
    services.coel-hub.enable = true;

    boot.kernelParams = [ "quiet" "splash" "plymouth.ignore-serial-consoles" ];
    boot.initrd.kernelModules = [ "bochs" ];
    boot.initrd.systemd.enable = true;
    virtualisation.qemu.options = [ "-vga std" ];
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;

    systemd.services.greetd.environment = {
      WLR_RENDERER = "pixman";
      QT_QUICK_BACKEND = "software";
    };

    users.users.alice = { isNormalUser = true; password = "secret"; };
  };

  testScript = ''
    import os
    import time

    shots = os.path.join(os.environ.get("out", "/tmp"), "frames")
    os.makedirs(shots, exist_ok=True)

    def classify(path):
        # ("black" | "base" (mostly #282c34: splash or greeter backdrop) | "other",
        #  a signature of the sampled pixels, to spot when the picture changes).
        with open(path, "rb") as f:
            data = f.read()
        parts = data.split(b"\n", 3)          # P6, "w h", maxval, pixels
        if parts[0] != b"P6":
            return "?", None
        w, h = map(int, parts[1].split())
        px = parts[3]
        black = base = exact = n = 0
        sig = []
        for y in range(0, h, 16):
            row = y * w * 3
            for x in range(0, w, 16):
                i = row + x * 3
                r, g, b = px[i], px[i + 1], px[i + 2]
                sig.append(r >> 4)
                n += 1
                if r < 12 and g < 12 and b < 12:
                    black += 1
                elif abs(r - 0x28) < 10 and abs(g - 0x2c) < 10 and abs(b - 0x34) < 10:
                    if abs(r - 0x28) < 3 and abs(g - 0x2c) < 3 and abs(b - 0x34) < 3:
                        exact += 1
                    base += 1
        # "flat": nothing but the backdrop colour (no wordmark, no greeter
        # gradient), i.e. the frame between the splash and the greeter is
        # missing the splash's picture.
        kind = ("black" if black > 0.9 * n else "flat" if exact >= n - 2
                else "base" if base > 0.6 * n else "other")
        return kind, hash(bytes(sig))

    # Capture for a fixed time: anything that talks to the guest (execute,
    # wait_for_*) blocks until its shell is up, which would leave a hole in the
    # timeline right where the seam is.
    machine.start()
    t0 = time.monotonic()
    frames = []
    i = 0
    while time.monotonic() - t0 < 90:
        p = os.path.join(shots, f"f{i:04d}.ppm")
        machine.send_monitor_command(f"screendump {p}")
        t = time.monotonic() - t0
        try:
            kind, sig = classify(p)
        except Exception:
            kind, sig = "?", None
        frames.append((t, kind, p, sig))
        i += 1
        # Each grab stalls the guest; ~8 per second still catches any gap
        # worth seeing and keeps the boot close to its normal speed.
        time.sleep(0.12)
    greeter_up = machine.execute("pgrep -u greeter -f bin/quickshell")[0] == 0

    # Timeline: collapse runs of the same kind.
    runs = []
    for t, kind, p, _ in frames:
        if runs and runs[-1][0] == kind:
            runs[-1][2] = t
            runs[-1][4] += 1
        else:
            runs.append([kind, t, t, os.path.basename(p), 1])
    print("frame timeline (kind, from s, to s, first frame, count):")
    for r in runs:
        print("  %-6s %6.2f %6.2f  %s  x%d" % tuple(r))
    print(machine.execute("journalctl -b -o short-monotonic --no-pager | grep -E 'Plymouth|plymouth|greetd|cage' | head -40")[1])
    print(machine.execute("systemctl list-jobs --no-pager; systemctl status --no-pager -n 15 greetd greetd-host-7 greetd-host-8 coel-splash-handoff plymouth-quit-wait 2>&1 | head -120")[1])
    print(machine.execute("cat /tmp/qs-greeter-cage.log | grep -v -E 'EGL|GLES2|extensions' | tail -40")[1])
    print(machine.execute("cat /run/user/*/quickshell/by-id/*/log.qslog 2>/dev/null | strings | tail -30")[1])

    # Keep only the frames where the picture changed (the first of each run).
    keep, last = set(), object()
    print("picture changes (s, frame, kind):")
    for t, kind, p, sig in frames:
        if sig != last:
            keep.add(p)
            print("  %6.2f  %s  %s" % (t, os.path.basename(p), kind))
            last = sig
    for _, _, p, _ in frames:
        if p not in keep:
            os.remove(p)

    assert greeter_up, "greeter never started"
    first_base = next((k for k, r in enumerate(runs) if r[0] == "base"), None)
    assert first_base is not None, "never saw the splash / greeter colour"
    bad = [r for r in runs[first_base:] if r[0] in ("black", "flat")]
    assert not bad, f"black or picture-less frames after the splash appeared: {bad}"
  '';
}
