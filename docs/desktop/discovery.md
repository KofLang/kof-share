# Desktop client — FASE 0: Architecture Discovery (no GUI code)

status: DELIVERABLE of the desktop gigaprompt §19 FASE 0. Evidence read from
this repo at the RELEASE tree (`v2.0.0`+`278bc97`) and from the pinned
compiler `f2629e32d` (git objects, not HEAD). No code was written by this
document. Decisions here are PROPOSTO unless marked DECIDIDO.
pin law: §18 respected — everything below works against `f2629e32d`; the
three faces the pin lacks are listed as core dependencies (§8), NOT worked
around in the product.

## 1. Core inventory (what exists, LOC at this tree)

34 product `.kf` files, 11,735 LOC. The pieces a desktop client touches:

| Area | Files | What it is | Desktop relevance |
|---||---|---|
| orchestration | `userflow.kf` (614) | `upPublish`, `upPublishSigned`, `upPublishDir`, `downFetch`, `downAuto`, `downAutoWithGrant`, `downDir`, `downDirAuto(WithGrant)`, `serveDirLoop`, `pickNthFile`, `dirWalk`, `dirBindLocal`, `takeAndVerify` | **the core API the desktop drives** — every §4 screen is a thin caller of these |
| identity | `identity.kf` (91) | `identityBoot(keystore)` (generate-or-load, persist), `identityPub`, `identityDeviceId(derive)` | first boot, "identity survives restart" |
| plane client | `control/*` (1,674) | registry/share/auth/presence/session pure + `app.kf` routes | desktop talks to the SAME routes the CLI uses (`/devices* /shares /s/<tok> /sessions /presence`) |
| transport | `connect.kf` (126) | `classifyConnect`, `pickAndDial`, `negotiatePath` — DIRECT→(NAT reserved)→RELAY→named `CONNECTIVITY_FAILED` | transport line in Transfer UI; honesty law for §8 events |
| transfer | `transfer.kf`/`protocol.kf`/`session.kf`/`relay.kf` (614) | chunk stream, framing, X25519 envelope, relay pump | NEVER re-entered by the GUI (§3) |
| resource/directory | `resource.kf`/`directory.kf` (377) | logical ids, binding table `kofshare-resources.json`, manifest, `dirValidate`, `sortEntries`, digests | folder share screen |
| browser lane | `app/client.kf` (220) + `app/page.kf` (65) | **existing local HTTP client**: `web.app` + `/api/info` (metadata-only) + `POST/GET /jobs` + poll + detached job run | **the reusable local-API precedent** (§3) |
| CLI | `cli/cli.kf` (2,276) | verbs + 14 CHECK legs + orchestration helpers | drift recorded post-v2 §5: `serveOne`, `startFaceHeartbeat`, `spawnDetached`, `stopHelper`, `freePort`, `errText`, `parseTtlMs` live here — they are desktop-candidate code, §8-E |

State files (device-local, never central): `kofshare-device.ed25519`,
`kofshare-resources.json`, `kofshare-*.pid/.log`, `server-registry.*.json`
(plane side). Config precedent: `kofshare-cli.config` (`jar=`, `workdir=`).

## 2. Reusable contracts the desktop consumes (DECIDIDO)

The desktop calls existing entry points; NOTHING in §1.5 of the gigaprompt
gets a parallel implementation:

```
identity      identityBoot/identityPub/identityDeviceId         (ID005 by name)
enroll        upPublishSigned → POST /devices/register           (DEV001–005)
share file    upPublishSigned + mint share → GET /s minted link  (REG030–041)
share folder  upPublishDir (manifest, REG015/016)                 (Track G)
receive link  downAuto / downAutoWithGrant (resolve-ONCE law)     (Track I)
receive dir   downDirAuto                                         (per-child)
presence      heartbeat verb (startFaceHeartbeat pattern)         (Track D)
devices list  GET /devices (plane truth, offline = no heartbeat)  — no invented rows
transports    pickAndDial result STAMPED, never narrated          (CONNECTCHECK)
errors        named codes preserved; errText human layer reused   (Track I law)
machine lane  --raw-style key:value lines are the API's ancestor  (§3)
```

Named-refusal contract (§9): the local API returns the SAME code strings the
plane/CLI return (`REG015`, `DEV-OFFLINE`, `CONNECTIVITY_FAILED`, `AUTH001`,
`RESUME-ERR: …`). The UI maps code→sentence; the code travels in the payload.

## 3. Local API / IPC proposal (DECIDIDO: reuse the proven local-HTTP precedent)

Investigation result (§6 demanded): the repo ALREADY has the pattern.
`app/client.kf` is a local HTTP server (`web.app`) exposing metadata-only
`/api/info` and a `POST/GET /jobs` queue, driven by a page that POLLS
job state. It is golden-proven on the browser lane (BROWSERCHECK-OK) and it
is the ONLY local-IPC precedent in Kof at the pin. `net.listen` TCP exists
but is raw framing (the data-plane protocol itself) — building a request
protocol over it would be inventing a second local protocol. Verdict:

```
DESKTOP UI  ──HTTP──▶  kofshare-daemon (new verb in cli.kf, NOT a new app;
                       binds a local port, loopback-first, see risk R2)
                       daemon = the SAME userflow.kf functions
```

Proposed surface (versioned on day one, minimal, names mirror the screens):

```
GET  /api/v1/state        lifecycle + identity summary + device id
GET  /api/v1/devices      plane device list (online/offline/transport truth)
GET  /api/v1/shares       my shares (status/expiry/uses/link)
POST /api/v1/shares       {path, ttl, once, readOnly} → mint (file OR folder)
DELETE /api/v1/shares/:tok revoke
POST /api/v1/receive      {link, dest}                  → job
GET  /api/v1/jobs         job state per id (progress from REAL counters)
POST /api/v1/jobs/:id/cancel
GET  /api/v1/events       long-poll/since-id cursor (state-change deltas)
GET  /api/v1/health       readiness (daemon-up gate, no sleep loops)
```

Rules carried from the existing contracts (not new architecture):
- **local auth token**: daemon writes a one-time secret to
  `kofshare-desktop.token` (0600); every request needs `X-Kof-Token`;
  mismatch → named `DESKTOP-LOCAL-AUTH` (pattern precedent: plane bearer gate
  + control secret file). The UI webview receives the token at injection
  (§5) so the LAN never holds it.
- **no secrets in responses**: `/api/v1/*` bodies carry the same view model
  `/api/info` guarantees today — no device private key, no control secret,
  no bearer echo (browserSecrets proof is the template for §13 security).
- progress is computed from observable state (bytes done/total already
  exist in `Transfer`; per-child directory counts exist in `downDirAuto`),
  never synthesized (§8 "no fake progress", §15 "no sleeps").
- `--raw` lines stay the wire format of job events: `--raw` was frozen for
  scripts, so reuse, don't re-invent.

## 4. Lifecycle proposal (resident process, clean shutdown)

```
daemon states: STARTING → READY → BUSY(transfer) → STOPPING → STOPPED
                                                    ↘ ERROR(named code + msg)
window states: OPEN ↔ MINIMIZED(tray) ; closing window ≠ stopping daemon
```

- `kofshare daemon --start` (spawnDetached pattern + pidfile
  `kofshare-desktop.pid`, port from token file; freePort sweep reused — the
  Track I orphan-sweep law), `kofshare daemon --stop` (stopHelper law: only
  this device's process), `status` via `/api/v1/health`.
- Transfers in flight continue when the window closes; the daemon owns
  transfers, the window is a view (prompt §5).
- Shutdown: cancel-or-park jobs by explicit UI choice (resume-safe by the
  A3 offset law — no data loss either way), then STOPPING stops heartbeat,
  closes listener, removes pidfile. No orphans, proven by port-bindable.

## 5. GUI proposal (DECIDIDO against the pin's real faces)

Evidence: the pin carries `kof.ui` — Window, Label, Button, Column, Row,
Grid, Input, Form, Image, Icon, Canvas, Event, AppState (compiler intrinsics
→ DOM) — and `KofJsWebview` opens a `kof.ui` window in the **system
webview (WebKitGTK), real DOM events executing in-page**, browser-as-fallback
(read at `f2629e32d`: `KofJsWebview.java`, `CmdRun.java:316`,
`WindowE2ETest`, `KofUi.java`). SDL3 exists at the pin only as **headless
vendored ABI** (slice 3.1 "doing" — no window backend shipped yet). So:

```
desktop shell = KofJS target (kof.ui widgets + the §3 local API over fetch)
                opened by the pin's own kof.ui webview
                — the sanctioned Kof GUI route, NOT Electron, NOT a new stack
core daemon   = JVM target (same jar, same net/crypto/file faces that made
                the goldens green)
bridge        = fetch(http://127.0.0.1:<port>/api/v1/…, X-Kof-Token)
```

Rejected and recorded: Electron (gigaprompt §10 — no justification exists
because §10-priority-1 holds: Kof IS the runtime for this); pure-JVM AWT/Swing
interop (would be JVM-side UI code the language doesn't sanction on the
product's own face list); SDL3 custom renderer (its backend slice is
unfinished at the pin — building the product on it now would depend on an
unmeasured HEAD, violating §18). Native dialog/tray are NOT available in the
pin's faces (§8) — desktop v1 degrades honestly: text-input path form +
"choose recent" instead of a native picker; tray = window-hides-on-close,
documented; notifications = in-window. All three listed as core
dependencies, none faked.

The UI NEVER owns logic (§7): it calls `/api/v1/*`; the daemon/core does
identity, auth, crypto, dialing. The GUI cannot read the private key file
(the daemon's token contract doesn't expose it; §13 proves refusal).

## 6. Packaging proposal (Linux x86_64 first)

- `kof.toml` build → two artifacts from this repo: the daemon (JVM:
  `kofshare-desktop.jar` runnable) and the UI (JS target bundle).
- launcher: `kofshare-desktop` shell script that (1) checks/starts the
  daemon via `--start`, (2) waits `/api/v1/health` observable-ready (no
  sleep), (3) execs `java -jar … run --target js app/` … — or simply opens
  the kof.ui window (the webview route is the pin's face).
- `.desktop` entry + icon + Exec line; state dir convention `~/.kofshare/`
  for token/pid/history; tray icon file optional.
- install story v1 = `scripts/install-desktop.sh` copying the artifacts +
  registering the entry; upgrade = re-run; uninstall = remove entry, kill
  daemon by pidfile ONLY (Track I discipline). No repo-manual-install sales
  pitch in §16 docs.
- Windows/macOS: explicitly NOT attempted (§11; the `ext.*` tooling already
  shows Windows paths land in Kof4j later, not here).

## 7. Risks (honest, measured at the pin)

| # | Risk | Evidence | Mitigation now |
|---|---|---|---|
| R1 | `web.app().listen()` and `net.listen()` bind `0.0.0.0` | read at pin: `JvmRuntimeSockets.kof_net_listen` binds `"0.0.0.0"`; web contract documented in `architecture.md` §10 | daemon requires `X-Kof-Token` on EVERY request; token file 0600, never in URL/query; §13 proves a LAN-shaped refusal. Real fix = §8 core face |
| R2 | TCP `peer()`/remote address not exposed (only UDP `peer`) | `KofNet.java` surface: `connect` is 2-arg; `peer` = NetEndpoint only | can't drop non-loopback peers at socket layer — R1's token covers it; core face requested |
| R3 | webview availability (WebKitGTK present? fallback = default browser) | `KofJsWebview` fallback documented at pin | acceptable v1 (browser-as-window); golden must run headless-friendly (`SDL_VIDEODRIVER=dummy` analog: the webview path needs an X/wayland session or browser dump — DESKTOP-BOOT-OK uses the fallback + HTTP-readiness, NOT pixel assertions) |
| R4 | kof.ui is "interface platform, not widget kit-complete"; progress bar/list primitives unknown at UI level | `docs/ui/architecture.md` | v1 renders progress as text+pct (state-driven), avoids canvas; widgets are view-only anyway |
| R5 | double-resolve of `--once` (Track I RED law) | `downAutoWithGrant` family | the API takes grant-or-link exactly once; `receive` handler resolves via the WithGrant paths only |
| R6 | new daemon verb grows cli.kf drift | post-v2 §5 recorded | §8-E marks the extraction boundary explicitly so the daemon does NOT re-implement; daemon calls userflow directly |

| R7 | shared FIXED-name state files (`server-control.bearer`, `server-registry.*`) poison concurrent suites — MEASURED this session: a desktop golden plane running while the RC battery starts = 3 early-suite FAILs with raw ConnectException stacks; same suites GREEN standalone with clean state. Law: no external plane state may exist when the battery starts (kill + rm the named files; the battery is sequential BY DESIGN). |

## 8. Core dependencies / extension points (requests, NOT hacks — §12/§18)

Small, named, upstream-first (each needs its own Kof4j decision; none is a
KofShare-side workaround):

- **A. `net.listen(host, port)` / web bind-address face** — kills R1/R2 for
  the desktop local API. Request: loopback bind parameter.
- **B. TCP peer address accessor** — server-side loopback policing (R2).
- **C. native file/folder picker face** (`dialog.openFile/openFolder`) —
  §4 screens; degraded v1 exists (§5), full UX needs it.
- **D. tray/status icon face** (graphics slice 3.1's sibling or a small FFI
  `ext` module) — resident-app UX; degraded v1 = hide-on-close.
- **E. core extraction trigger** — the post-v2 D8 says the extraction ships
  when the GUI is scheduled. **This gigaprompt schedules it.** The
  extraction set: move `serveOne/startFaceHeartbeat/spawnDetached/stopHelper/
  freePort/errText/parseTtlMs/fieldOf/baseHost/basePort` from `cli.kf` into
  a `core` home (`kofshare/cli` stays the thin driver). Gate: `RC-CHECK-OK
  steps=23` green on the extraction commit with ZERO behavior diff, then the
  desktop ships on top. (This is the documented procedure, not new scope.)
- **F. clipboard/notification faces** — degraded: page `navigator.clipboard`
  in the webview (JS target), in-window toast otherwise.

Nothing here blocks FASE 1–6: every degraded path is honest and tested.

## 9. Phase plan (the gigaprompt's, with pin-grounded adjustments)

```
F0 discovery            THIS DOCUMENT                                [done]
F1 desktop shell        daemon verb + lifecycle + window open      → DESKTOP-BOOT-OK steps=21 DELIVERED (boot.kf; hot re-run OK; F7-launcher scripts + install/uninstall smoke included; matrix in docs/desktop/phase0-matrix.md)
F2 local API            /api/v1/* + token auth + events            → DESKTOP-IPC-OK
F3 identity/account/devices screens on the existing client lanes   → DESKTOP-IDENTITY-OK
F4 share/receive screens (file+folder, pickers-degraded)            → DESKTOP-SHARE-OK
F5 transfer UX (real counters, transport stamp, cancel, resume)     → DESKTOP-TRANSFER-OK
F6 two real clients + plane + direct + relay                        → DESKTOPCHECK-OK
F7 packaging (Linux x86_64: launcher, entry, icon, install/upgrade/
   uninstall story) — scripts + docs only
```

Golden discipline (every phase): observable conditions only (health
endpoint 200, token file exists, job state transitions, port bindable,
sentinel files, digest equality), zero sleeps; the v2 battery runs UNCHANGED
alongside (`RC-CHECK-OK` is the release proof, §20 — a desktop commit that
reddens it is reverted, not the golden).

## 10. What FASE 0 explicitly did NOT do

No GUI code, no daemon code, no pin bump, no protocol change, no Electron,
no fake tray/picker, no new named error without cause (`DESKTOP-*` codes are
proposed only for the local-API layer, additive to the frozen plane codes),
no Track letter. The next move is the maintainer's go for FASE 1 (or edits
to §3/§5/§8 before code exists — that is cheaper than after).
