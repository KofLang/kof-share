# FASE 0 — requirement matrix (gigaprompt §4) + FASE 1 evidence

Method: every row was decided by reading code/tests at the RELEASE tree and
the pin `f2629e32d` (git objects), then — for the FASE 1 rows — by running
`src/main/kof/kofshare/desktopcheck/boot.kf` (real processes, loopback).
States: **EP** = EXISTENTE E PROVADO · **ES** = EXISTENTE SEM PROVA
SUFICIENTE · **A** = AUSENTE · **DP** = DECISÃO PENDENTE (mantainer).

| # | Requirement (gigaprompt §5 unless noted) | State | Evidence / where it lives |
|---|---|---|---|
| 1 | Central plane: identity, devices, grants, sessions, presence, registry | EP | control/* goldens (REGCHECK/SHARECHECK/SESSIONCHECK/CHECKUSER green at cut; runrc steps=23) |
| 2 | Desktop finds & configures the central service | EP | `desktopd.kf` conf (`kofshare-desktop.conf plane=`) + golden legs `prestart-conf`/`prestart-plane` |
| 3 | Live connection state shown (not cached) | EP | `/api/v1/state` `plane` via `healthNow` probe per call; golden `state-plane-live` (plane actually up on 19911) |
| 4 | Start without manual terminals (lifecycle verbs) | EP | `--start/--stop/--status/--window`; golden `restart-start`/`status-verb`/`stop-verb` |
| 5 | Local client init/detect/connect | EP | daemon = the local client itself (spawnDetachedEntry + waitHealth + pidfile); golden `daemon-health` |
| 6 | Init errors useful, no stack traces in UI | EP | named `DESKTOP-LOCAL-AUTH`, `DESKTOP-START-ERR`, `DESKTOP-STOP-ERR`; refusal golden legs; errText lane reused |
| 7 | No orphan processes / ports / dup instances | EP | `desktopStart` guard (healthNow → already=true), stop = pidfile + product port law; golden `port-released`/`pidfile-gone`; hot re-run OK |
| 8 | Local auth between UI and daemon | EP | token 0600 file + `X-Kof-Token` + page-token refusal; golden `token-0600`/`refusal-named`/`page-refused` |
| 9 | Secrets out of UI/responses | EP | metadata-only view (client.kf /api/info law); golden `state-no-secrets`; daemon never reads device key |
| 10 | Loopback-only exposure | **ES→A** | pin binds `0.0.0.0` (R1/R2 measured at `f2629e32d`: JvmRuntimeSockets + KofWeb); token law mitigates; REAL fix = core face **bind-address** (discovery §8-A) — A at pin, requested upstream, NOT hacked |
| 11 | Account login/creation desktop-side | A (F3) | plane auth exists (control/auth EP), desktop screens not built; discovery §9 F3 |
| 12 | Device registration recognized | A (F3) | `identityBoot/identityDeviceId` EP at core; not surfaced in F1 scope |
| 13 | Share file/folder UI + real links | A (F4) | `upPublishSigned/upPublishDir/mint` EP (SHARECHECK); UI not built; no mock buttons added |
| 14 | Receive link + destination choice | A (F4–5) | `downAutoWithGrant/downDirAuto` EP (TRACK I/FOLDER goldens); UI not built |
| 15 | Progress from REAL counters, done only after digest | A (F5) | Transfer byte counters + digest verify EP (TRANSFERCHECK); UI feed not built |
| 16 | Cancel/stop per existing contracts | A (F5) | session cancel/resume offset law EP (RESUMECHECK); UI not built |
| 17 | Native file/folder picker | A | no face at pin (`kof.ui` has no dialog); degraded F1: text paths (discovery §5/§8-C) |
| 18 | Tray/notifications | A | no face at pin; degraded: hide-on-close + in-window (discovery §8-D/F) |
| 19 | Desktop shell technology = Kof route | EP | daemon JVM + served page via `web.app` + `xdg-open` (env: firefox/xdg-open present, **node ABSENT** ⇒ JS target impossible here — recorded; kof.ui Window needs the JS toolchain) |
| 20 | Wire/CLI/browser compatibility untouched | EP | zero protocol files changed; battery runrc steps=23 (this branch) + goldens import cli only for verb main; CLI `--check` legs green incl. moved helpers |
| 21 | Relay only when selected, never shown as direct | EP (plane) / A (desktop UI) | relay pump + stamping EP (RELAYCHECK/CONNECTCHECK); desktop surface = F5 |
| 22 | No central file storage | EP | architecture law + plane registry holds metadata only (control/* read; runrc HTTPCYCLE); desktop adds zero storage |
| 23 | P2P DIRECT real | **ES** | loopback/direct-lan transfers EP (E2E/DIRECT legs); NAT traversal A by design (STUN/ICE reserved, §10) — proof stays NOT_DEMONSTRATED for real-NAT (discovery §7 honesty) |
| 24 | Packaging install/upgrade/uninstall story | A (F7) | scripts + `.desktop` entry + launcher land with F7; not claimed until run |
| 25 | Windows/macOS support | A | §11; Linux x86_64 only (measured env facts above) |

## Gate 1 — SAFE SUBSET result (this branch, post-audit)

Delivered decision-free hardening + read-only events on the already-shipped
F1 boundary. New golden `desktopapi/apicheck.kf` → **DESKTOP-API-OK legs=22**
(RED-before-GREEN demonstrated: disabling the host/origin gate flips the
`origin-refused` + `raw-forged-host-refused` legs to FAIL; restore → PASS).

| Added | Class | Proof (leg) |
|---|---|---|
| Host policing (DNS-rebinding defense) | IMPLEMENTADO E PROVADO | unit `unit-host-shape` + real-socket `raw-forged-host-refused`/`raw-loopback-allowed` (forged Host via raw net.connect; Java http forbids Host override so raw socket is the only honest proof — and it measures that the web runtime delivers header("host")) |
| Origin policing (CSRF/forged-browser) | IMPLEMENTADO E PROVADO | unit `unit-origin-shape` + integration `origin-refused`/`origin-allowed` |
| `/api/v1/events` (observable subset) | IMPLEMENTADO E PROVADO | `events-array`/`events-have-boot-state`/`events-envelope`/`events-cursor-empty`/`events-deny-no-token` |
| Page JS reads token from location.search | IMPLEMENTADO E PROVADO | fixes the F1 latent `KOFDTOKEN` literal (boot `page-marker` still green) |
| Token not echoed in bodies/logs | IMPLEMENTADO E PROVADO | `token-not-echoed` + `token-0600` |
| Boundary logic as pure importable package | IMPLEMENTADO E PROVADO | `kofshare/boundary/boundary.kf` (unit-tested without a server) |

**Two real bugs the unit legs caught** (honest, not theoretical): naive
`originAllowed` accepted the prefix-confusion host `127.0.0.1.evil.example`,
and `isLoopbackHost` mishandled bracketed IPv6 `[::1]:port`. Both fixed and
re-green.

Events are the OBSERVABLE subset only (DAEMON_STATE, PLANE_PRESENCE).
Transfer/share events are deliberately ABSENT until the privileged mutating
routes exist — emitting them now would be inventing transitions the real
state has not confirmed (§4 event law).

## Pending-decision register (DP) — nothing irreversible taken unasked

- **bind-address core face (§8-A)**: the daemon's honest answer for now is
  token-auth + Host/Origin policing on a 0.0.0.0 bind (measured pin behavior;
  the safe subset shipped above). The **irreversible** choice — and the gate
  on the PRIVILEGED mutating surface (`POST /shares`, `POST /transfers`,
  `DELETE`, cancel), which is NOT implemented — remains open:
  - **Option A** keep HTTP on 0.0.0.0 + token + host/origin policing (status
    quo, shipped). Mutating surface would sit on this boundary.
  - **Option B** request upstream `web.app().listen(host, port)` face →
    compiler-pin bump + full `RC-CHECK-OK` re-run (law 2, §7 of the gigaprompt).
  - **Option C** Unix-domain socket via `ext` FFI → second IPC stack + native
    dependency, breaks the browser/webview face.
  Building the mutating endpoints turns the 0.0.0.0 exposure into real blast
  radius (a LAN attacker holding the token could mint shares / trigger
  downloads). That authorization is the mantainer's call — recorded, not made
  silently.
  **DECIDED 09/10/2026 (gigaprompt §5 orders the gate closed): OPTION A.**
  Contracts compared, not invented: B needs a face `web.listen(host, port)`
  that does NOT exist at the pin (`KofWeb.java:154` types `listen(Int)` only)
  ⇒ it is a Kof4j change + pin promotion + full re-battery, which the pin law
  reserves for a maintainer-verified candidate (20a3207e1 precedent: three
  failed full batteries). C (Unix socket via `ext` FFI) does bind at the pin
  (`CompilerFfiBinding`: JVM target binds externs) but is a second IPC stack
  that breaks the daemon-served webview face — the only shell the product
  ships today (node absent). A is therefore the least-privilege option
  COMPATIBLE WITH THE EXISTING RUNTIME: blast radius closed by the shipped
  boundary instead — 0600 device-local token (never in API URLs), Host
  policing (DNS-rebinding), Origin allow-list (CSRF/malicious-page), named
  refusals, all RED-before-GREEN proven at `DESKTOP-API-OK`. The mutating
  surface is hereby UNLOCKED under these conditions. B remains the named
  upstream request (row 10, discovery §8-A) and will supersede A the day a
  pin candidate carries `listen(host, port)` and passes RC twice clean.
- **kof.ui vs served page as the v1 shell face**: node is ABSENT on this
  machine ⇒ the JS target can't build here today; the webview route exists
  at the pin but its toolchain is unavailable. F1 therefore ships the
  daemon-served page + `xdg-open` (the browser-lane precedent, BROWSERCHECK
  EP). If the mantainer wants kof.ui-native immediately, that is a toolchain
  install decision (DP), not a code change.
- **core extraction timing (D8 trigger)**: shipped BEFORE the desktop code
  merged (commit A of this branch), per discovery §8-E procedure; RC gate
  result recorded in STATUS.

## FASE 1 delivered golden (the proof of rows 2–9, 20)

```
java -jar <pin jar> run src/main/kof/kofshare/desktopcheck/boot.kf
DESKTOP-BOOT-OK steps=21          (cold and hot re-run both green)
```
Legs: plane via existing `server --start` verb · conf kept · daemon
healthable · token present/0600 · unauthenticated named refusal · health ·
state READY + live plane + no-secret body · page marker + wrong-token
refusal · status verb · stop verb · port released · pidfile gone · cold
restart + health + stop. No sleeps without observable exit; cleanup uses the
product's own port law; window leg asserts the SERVED page (pixels are not
evidence).

## Test-environment preconditions (gigaprompt §8: explicit preconditions)

- P1: pin jar present with verified SHA-256 `0b1893b4…f9c…` — the build from
  git objects reproduces it BYTE-IDENTICAL (measured this session: rebuild of
  `f2629e32d` → same sha), so the pin is re-creatable, not a loose file.
- P2: NO java/suites running when a battery/golden starts; ports 8799/19911
  free (`ss` observable, never assumed).
- P3: shared plane state files (`server-control.bearer`,
  `server-registry.*.json`) belong to ONE suite at a time — verified failure
  mode recorded as discovery §7 R7 (3 early RC steps poisoned by a live
  external plane with the same bearer; all green standalone after `rm`).
- P4: `kofshare-desktop.conf/token/pid` fresh-deleted before the desktop
  golden (the golden itself enforces it).

## FASE 1 result (this commit)

`DESKTOP-BOOT-OK steps=21` cold + hot re-run; `RESOURCECHECK-OK` standalone
post-cleanup; full `runrc` battery re-running with clean state — result
recorded in STATUS.md the moment it lands (`RC-CHECK-OK steps=23` = the
release gate; anything else = this branch does not merge as-is).
