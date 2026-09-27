# GlobalProtect / LUC HIP compliance investigation

Dated 2026-08-14. Context for [[project_globalprotect_luc]] memory and any
future work on this. Summarizes what was tried, what was ruled out, and
what the actual root cause appears to be.

## Background

LUC's GlobalProtect gateway (`secureaccess.luc.edu`) enforces a Host
Information Profile (HIP) policy that requires a detected firewall *and*
antivirus before granting full network access. Non-compliant connections
still get a tunnel, but are quarantined to a restricted network (no DNS
push, no route to real internal hosts) rather than rejected outright.

ITS's only guidance, both times asked, was "try iptables instead of
nftables, GlobalProtect sometimes has issues with it" -- generic, not
Linux-HIP-specific, and (per their own words) they don't have Linux
documentation for this.

## What was tried

1. **`networking.firewall.package = pkgs.iptables-legacy`** (true legacy
   iptables, not the iptables-nft compatibility shim that's the actual
   default when `networking.nftables.enable = false`). Got the tunnel
   negotiating cleanly -- but this was never actually proven necessary,
   since the real blocker (below) turned out to be unrelated to which
   local packet-filter backend is in use. Never A/B tested against the
   default.

2. **`enableGpHipComplianceExperiment = true`** (installs and enables
   ClamAV -- `configuration.nix`). Confirmed `clamav-daemon` running with
   an up-to-date virus database at the time of testing.

3. **`services.firewalld.enable = true`** (with `networking.nftables.enable
   = true`, since firewalld defaults to an nftables backend and asserts on
   it). Confirmed firewalld active, zones correctly inheriting the existing
   `networking.firewall.*` settings (trusted tailscale0, SSH/tailscale/kdeconnect
   ports preserved).

None of the three changed the gateway's HIP verdict. The rejection
notification (`Firewall and AV` / `LUC Network Base`, both value=0) was
byte-for-byte identical before and after every change:

> "Access to resources on the LUC network is not permitted without a
> working firewall (installed and enabled) and antivirus (installed and
> enabled with real-time protection). Your machine does not currently meet
> these criteria."

## Root cause (confirmed, not inferred)

An accidental standalone invocation of the vendored `PanGpHip` binary
(`./PanGpHip --help`, which it doesn't recognize as a flag, so it just ran
its default report-generation behavior and dumped XML to stdout/disk
instead of going through the usual IPC flow) revealed the actual HIP
report content sent to the gateway, captured at
`/var/lib/globalprotect/pan_gp_hrpt.xml`, timestamped seconds before a real
submission in the same session:

```xml
<entry name="anti-malware">
    <list>
    </list>
</entry>
<entry name="firewall">
    <list>
    </list>
</entry>
```

Both lists are **completely empty** -- at a moment when `clamav-daemon` and
`firewalld` were both actively running. This isn't "wrong product
detected," it's "detecting nothing at all, regardless of what's actually
installed." GlobalProtect Linux client version in use: `6.2.8-1057`.

**Conclusion**: this looks like a genuine limitation of the OPSWAT SDK's
Linux product-detection support bundled with this GlobalProtect client
build, not a local NixOS misconfiguration. OPSWAT's Linux signature
coverage has historically been much thinner than Windows/Mac. No amount of
installing "the right" firewall/AV product is likely to fix this if the
detection mechanism itself isn't functional for Linux in this client
version.

## Current live state

- `networking.firewall.package = pkgs.iptables-legacy;` -- present but
  commented out / inert (superseded by firewalld taking over packet
  filtering; see the comment above it in `configuration.nix`)
- `networking.nftables.enable = true;`
- `services.firewalld.enable = true;`
- `enableGpHipComplianceExperiment = true;` (ClamAV running)

None of these are harmful to keep, but none of them are proven to matter
for the actual GlobalProtect/HIP problem either -- they're just where
testing left off.

## Resolution (2026-08-24)

Confirmed via a clean Ubuntu 26.04 VM (virt-manager/QEMU, set up specifically
for this) that OPSWAT's Linux detection genuinely works given a normal
`.deb`/apt install -- it correctly named IPTables, nftables, and UFW as
separate firewall products (with accurate enabled/disabled state), and
correctly tracked ClamAV being installed and later purged. That ruled out
"OPSWAT's Linux support is broken" and pointed at something specific to how
NixOS packages things.

**Root cause**: `PanGpHip` runs inside the FHS sandbox built by
`lib/globalprotect-fhs.nix` (`pkgs.buildFHSEnv`). That sandbox's `targetPkgs`
list was deliberately minimal (just GlobalProtect's own runtime deps --
`iproute2`, `iputils`, `procps`, etc.) and never included any firewall/AV
tooling. So even with real root and firewalld genuinely running on the real
host, `PanGpHip`'s filesystem view inside the sandbox had no
`/usr/sbin/iptables`, no `nft`, nothing to find -- it wasn't failing to
recognize our firewall, it had no visibility into it at all.

**Fix**: added `pkgs.iptables` and `pkgs.nftables` to `targetPkgs` in
`lib/globalprotect-fhs.nix` (`ufw` isn't packaged in nixpkgs, so not
included -- iptables + nftables covered 2 of the 3 products the Ubuntu VM
test showed). This is "make the real, already-running software visible
to OPSWAT's own legitimate detection," not report forgery -- the sandbox
just needed the binaries present at the paths OPSWAT checks.

Result: `nftables` now reports `enabled: yes` (correctly reflecting
firewalld's actual nftables backend), IPTables reports `enabled: no`
(correctly reflecting it's present but not the active enforcement layer).
`anti-malware` list is still empty (ClamAV deliberately left out --
confirmed via the Ubuntu VM that antivirus isn't required for the "LUC
Network Base" tier, only the separate "Firewall and AV" / high-security
tier, which isn't needed for this use case). Base-tier access confirmed
working (`ping 10.17.28.88` succeeds).

Current live state:
- `lib/globalprotect-fhs.nix`: `targetPkgs` includes `iptables` + `nftables`
- `services.firewalld.enable = true;` / `networking.nftables.enable = true;`
  (configuration.nix) -- this is what's actually being detected as "enabled"
- `enableGpHipComplianceExperiment = true;` (ClamAV) -- no longer load-bearing
  for what's needed, could be reverted; left on, harmless either way
- `networking.firewall.package = pkgs.iptables-legacy;` -- inert/superseded,
  see the comment above it

## Separate bug found along the way: local-subnet route hijack

GlobalProtect's full-tunnel config injects a duplicate, higher-priority
route for the *entire local subnet* (not just LUC's own ranges) through the
VPN tunnel interface (`gpd0`), with no explicit metric (defaults to 0),
beating the real local route. Confirmed identically on both the test VM
(broke host->VM SSH) and the real NixOS host (broke DNS, since the home
router/DNS server sits on that same local subnet). `PanGPS` has a
netlink-reactive watchdog that re-asserts this route within milliseconds of
manual deletion, so a one-off `ip route del` or a polling loop don't hold.

**Working fix**: policy routing that bypasses the main table entirely
instead of fighting the watchdog:
```
sudo ip route add <local-subnet>/24 dev <real-interface> table 100
sudo ip rule add to <local-subnet>/24 table 100 priority 100
```
This is currently a **manual, one-off fix** applied per-network -- it does
not persist across reboots or automatically adapt when the laptop moves to
a different WiFi network with a different subnet. Worth automating (e.g. a
NetworkManager dispatcher script triggered on `gpd0` coming up, detecting
whatever the current non-tunnel subnet actually is) if this keeps coming up.
