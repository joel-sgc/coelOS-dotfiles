# GlobalProtect VPN automation (LUC)

Scriptable connect/disconnect wrappers around the vendored GlobalProtect
client, designed to be driven by another program (e.g. a Go TUI that toggles
registered VPNs). The portal password is stored in the login keyring and
injected automatically; the only thing a human ever supplies is the
Microsoft MFA code.

Companion docs: [globalprotect-hip-investigation.md](globalprotect-hip-investigation.md)
(HIP compliance + route-hijack fix), and the module analysis in the repo
history.

Defined in [home/globalprotect.nix](home/globalprotect.nix) +
[home/globalprotect/gp-connect.exp](home/globalprotect/gp-connect.exp).

---

## Auth model

LUC's portal (`secureaccess.luc.edu`) is **not** SAML/browser auth, despite
`saml-default-browser=yes` in the prelogin response — that response carries
only an `<authentication-message>`, no `<saml-request>`. The vendor
`globalprotect` CLI talks XML-IPC to `PanGPA`, which does plain HTTPS form
posts. There are exactly two secrets:

1. **Portal**: username + password (LUC domain creds). `<can-save-password>`
   is pushed as `no` by the portal, so the client itself never remembers
   the password — it must be supplied on every connect.
2. **Gateway**: an OTP challenge — `Enter Your Microsoft verification code`
   (Entra ID / Microsoft Authenticator), submitted as `<secure-id>`.

The CLI's interactive prompt sequence (confirmed by capture):

```
Retrieving configuration...
secureaccess.luc.edu - Enter your username and password
Username(jgutierrez11@luc.edu):          <- prompts even though --username is passed; value is the default
Password:
Enter Your Microsoft verification code:
```

The password read is a `getpass()`-style `/dev/tty` read, so a plain pipe
can't feed it — the wrapper drives the CLI through a pty via `expect`
([gp-connect.exp](home/globalprotect/gp-connect.exp)). The caller of the
wrapper needs **no** tty of its own.

---

## Commands

| Command | Purpose |
| --- | --- |
| `coel-vpn-set-password` | Store the LUC portal password in the login keyring. Run once; re-run after a password change. Prompts on stderr, reads silently. |
| `coel-vpn-forget-password` | Remove the stored password from the keyring. |
| `coel-vpn-connect [MFA_CODE]` | Connect. Emits `GP_STATUS:` lines on stdout, raw client output on stderr. See the contract below. |
| `coel-vpn-disconnect` | Disconnect. Prints `GP_STATUS: disconnected`, exit 0. |
| `coel-vpn-status` | Print one token: `connected` / `connected-internal` / `disconnected` / `unknown`. Exit 0 iff connected. For polling. |

All are on `PATH` via `home.packages`. The underlying client (system daemon
`globalprotect-daemon`, user agent `globalprotect-agent`) must be running —
they are enabled by default in the NixOS/home-manager config.

---

## Secret storage

The password lives in the **login keyring** via the Secret Service API
(`libsecret` / `secret-tool`). On this host `org.freedesktop.secrets` is
owned by **gnome-keyring**, PAM-unlocked at login. (`kwallet-query
--write-password` silently no-ops here, which is why libsecret is used.)

Lookup key:

```
service = coel-vpn
account = jgutierrez11@luc.edu
label   = LUC GlobalProtect
```

Equivalent manual operations:

```sh
printf '%s' 'THEPASSWORD' | secret-tool store --label='LUC GlobalProtect' \
  service coel-vpn account jgutierrez11@luc.edu
secret-tool lookup service coel-vpn account jgutierrez11@luc.edu
secret-tool clear  service coel-vpn account jgutierrez11@luc.edu
```

To bypass the keyring entirely (headless, no D-Bus session — see
[Headless use](#headless--no-d-bus-session)), set `GP_PASSWORD` in the
environment `coel-vpn-connect` is spawned with.

---

## `coel-vpn-connect` contract

### stdout — `GP_STATUS:` lines

| Line | Meaning | Next action |
| --- | --- | --- |
| `GP_STATUS: connecting` | Portal contacted, auth started. | wait |
| `GP_STATUS: mfa-required` | Gateway wants the MFA code. | write `<code>\n` to the process **stdin** (unless already supplied via arg / `GP_MFA_CODE`) |
| `GP_STATUS: mfa-rejected` | Last code was wrong; another `mfa-required` follows. | prompt again |
| `GP_STATUS: connected` | Tunnel up (verified via `show --status`). | done — process exits 0 |
| `GP_STATUS: auth-failed` | Bad password, too many bad codes, or portal refused. | give up / re-prompt password |
| `GP_STATUS: no-password` | No password in keyring and `GP_PASSWORD` unset. | run `coel-vpn-set-password` |
| `GP_STATUS: mfa-timeout` | No code supplied within 300 s of `mfa-required`. | — |
| `GP_STATUS: needs-attention` | Client cert passphrase / cert-trust prompt — not automatable here. | run `coel-vpn-connect` by hand once |
| `GP_STATUS: timeout` | No recognised prompt within 120 s. | check client health |

stderr carries the raw client chatter (`Retrieving configuration...`,
`Password:`, error text). Log it or discard it; don't parse it.

### Exit codes

| Code | |
| --- | --- |
| `0` | connected |
| `2` | auth-failed |
| `3` | no-password |
| `4` | timeout / needs-attention |
| `5` | MFA not supplied in time |

### MFA code — delivery, in precedence order

1. **Argument**: `coel-vpn-connect 123456`
2. **Env**: `GP_MFA_CODE=123456 coel-vpn-connect`
3. **stdin stream** (the useful one for TOTP): run `coel-vpn-connect`, read
   stdout; on `GP_STATUS: mfa-required`, prompt your user and write
   `code\n` to the child's stdin. On `mfa-rejected` → `mfa-required`,
   repeat. A rejected arg/env code also falls back to this stdin path.

---

## Go integration

`coel-vpn-connect` needs no pty — spawn it with plain pipes. Read stdout
line by line; when you see `mfa-required`, get the code from your UI and
write it to the child's stdin.

```go
package vpn

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os/exec"
	"strings"
)

// Status mirrors the "GP_STATUS: <state>" lines coel-vpn-connect prints.
type Status string

const (
	StatusConnecting    Status = "connecting"
	StatusMFARequired   Status = "mfa-required"
	StatusMFARejected   Status = "mfa-rejected"
	StatusConnected     Status = "connected"
	StatusAuthFailed    Status = "auth-failed"
	StatusNoPassword    Status = "no-password"
	StatusMFATimeout    Status = "mfa-timeout"
	StatusNeedsAttn     Status = "needs-attention"
	StatusTimeout       Status = "timeout"
	StatusDisconnected  Status = "disconnected"
)

// CodeFunc is called each time the gateway asks for an MFA code. rejected
// is true when the previous code was refused. Return the code the user
// entered, or ("", err) to abort.
type CodeFunc func(rejected bool) (string, error)

// Connect runs coel-vpn-connect and drives the MFA exchange. onStatus, if
// non-nil, receives every status line for UI updates.
func Connect(ctx context.Context, getCode CodeFunc, onStatus func(Status)) error {
	cmd := exec.CommandContext(ctx, "coel-vpn-connect")

	stdin, err := cmd.StdinPipe()
	if err != nil {
		return err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	cmd.Stderr = io.Discard // or a log writer

	if err := cmd.Start(); err != nil {
		return err
	}

	rejected := false
	sc := bufio.NewScanner(stdout)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		st, ok := strings.CutPrefix(line, "GP_STATUS: ")
		if !ok {
			continue
		}
		status := Status(st)
		if onStatus != nil {
			onStatus(status)
		}

		switch status {
		case StatusMFARejected:
			rejected = true
		case StatusMFARequired:
			code, err := getCode(rejected)
			rejected = false
			if err != nil {
				_ = cmd.Process.Kill()
				return fmt.Errorf("mfa aborted: %w", err)
			}
			if _, err := io.WriteString(stdin, code+"\n"); err != nil {
				_ = cmd.Process.Kill()
				return err
			}
		case StatusConnected:
			// keep draining until the process exits
		}
	}
	if err := sc.Err(); err != nil {
		_ = cmd.Wait()
		return err
	}

	// Exit code carries the final verdict: 0 ok, 2/3/4/5 per the contract.
	if err := cmd.Wait(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return fmt.Errorf("coel-vpn-connect exited %d", ee.ExitCode())
		}
		return err
	}
	return nil
}

// Disconnect runs coel-vpn-disconnect (always quick, non-interactive).
func Disconnect(ctx context.Context) error {
	return exec.CommandContext(ctx, "coel-vpn-disconnect").Run()
}

// Connected reports tunnel state via coel-vpn-status (exit 0 iff up).
func Connected(ctx context.Context) (bool, error) {
	out, err := exec.CommandContext(ctx, "coel-vpn-status").Output()
	token := strings.TrimSpace(string(out))
	switch token {
	case "connected", "connected-internal":
		return true, nil
	case "disconnected", "unknown":
		return false, nil
	default:
		return false, fmt.Errorf("coel-vpn-status: %q (%v)", token, err)
	}
}
```

Usage sketch:

```go
err := vpn.Connect(ctx,
	func(rejected bool) (string, error) {
		prompt := "Microsoft verification code:"
		if rejected {
			prompt = "Code rejected — try again:"
		}
		return tui.AskString(prompt) // your modal
	},
	func(s vpn.Status) { tui.SetVPNStatus(string(s)) },
)
```

### Pre-supplying the code

If the TUI collects the code up front (e.g. a single "connect" form with a
code field), skip the stdin dance:

```go
cmd := exec.CommandContext(ctx, "coel-vpn-connect", code)
// or: cmd.Env = append(os.Environ(), "GP_MFA_CODE="+code)
```

A wrong code still drops back to the stdin path, so keep a `getCode`
handler wired anyway if you want ret/ries.

---

## Headless / no D-Bus session

`secret-tool` needs the session bus (`DBUS_SESSION_BUS_ADDRESS`) and an
unlocked keyring. If the TUI runs outside the graphical session (a bare
tty, `ssh`, a system service), the keyring lookup fails with
`GP_STATUS: no-password`. Options:

- Run the TUI inside the Plasma/systemd user session so it inherits the bus.
- Pass the password directly: `cmd.Env = append(os.Environ(),
  "GP_PASSWORD="+pw)` — read `pw` from wherever the TUI keeps its own
  secrets. The wrapper uses `GP_PASSWORD` verbatim and never touches the
  keyring when it's set.

---

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Hangs after `GP_STATUS: connecting`, no `mfa-required` | A prompt didn't match. Reproduce with `expect -f home/globalprotect/gp-connect.exp` under `log_user 1` / `exp_internal 1` and compare the CLI's real prompt text against the regexes near the top of the `expect {}` block. |
| `GP_STATUS: no-password` despite `coel-vpn-set-password` succeeding | Keyring not unlocked, or no session bus. `secret-tool lookup service coel-vpn account jgutierrez11@luc.edu` should print the password. |
| `GP_STATUS: needs-attention` | The client hit a cert-trust / PEM passphrase prompt. Run `coel-vpn-connect` interactively once to clear it, then retry. |
| `GP_STATUS: auth-failed` immediately | Wrong stored password — `coel-vpn-set-password` again. Repeated failures can lock the LUC account; back off. |
| MFA never arrives on phone | Portal auth (password) didn't complete — check stderr for the `Password:` exchange and any error line. |
| Connected but local subnet / DNS broken | Separate issue — the route-hijack fix. See [globalprotect-hip-investigation.md](globalprotect-hip-investigation.md); `gpd0` up should trigger `gp-route-fix-up.service`. |

Do not hot-loop `coel-vpn-connect` on failure — repeated bad portal auth
risks locking the account. Add backoff in the TUI.

---

## Files

| Path | Role |
| --- | --- |
| [home/globalprotect.nix](home/globalprotect.nix) | Defines the five `coel-vpn-*` commands and the user agent service. |
| [home/globalprotect/gp-connect.exp](home/globalprotect/gp-connect.exp) | The `expect` script `coel-vpn-connect` runs — prompt matching, MFA exchange, `GP_STATUS` emission. |
| [modules/globalprotect.nix](modules/globalprotect.nix) | System daemon, FHS wrapper, route-hijack fix. |
| [lib/globalprotect-fhs.nix](lib/globalprotect-fhs.nix) | Shared FHS sandbox builder (daemon + agent). |
| [modules/vendor/opt/paloaltonetworks/globalprotect/](modules/vendor/opt/paloaltonetworks/globalprotect/) | Vendored client `6.2.8-1057`. |
