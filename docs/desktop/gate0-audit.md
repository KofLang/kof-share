# KofShare — Gate 0 audit (factual inventory, no code changes)

Method: each row below was verified against the code and the pin's runtime
objects (`f2629e32d`) at the current HEAD of this branch, and against a
golden or a `run` execution when claimed as proved. Classifications are
strict: `IMPLEMENTADO E PROVADO` requires reproducible code + a test;
`IMPLEMENTADO PARCIALMENTE` means code exists but production conditions or
proofs are missing; `DOCUMENTADO, NÃO IMPLEMENTADO` means only documentation;
`SIMULADO` means a golden analog stands in for a mechanism; `AUSENTE` means
the work has not been started.

## 1. Control plane (`control/*`, `server.kf`)

| Capability | Class | Evidence |
|---|---|---|
| Device registration + Ed25519 identity | IMPLEMENTADO E PROVADO | `control/registry.kf` + `identity.kf`; goldens `REGCHECK-OK`, `IDENTITYCHECK-OK` |
| Account bearer/JWT authentication | IMPLEMENTADO E PROVADO | `control/auth.kf` (D3=B: JWT + `security.apiKeyGenerate`); goldens `HTTPCHECK-OK` `AUTH001`–`AUTH006` + `RESTART-OK` |
| Shares: create/consume/revoke + TTL/maxUses/readOnly/`--once` | IMPLEMENTADO E PROVADO | `control/share.kf`; `SHARECHECK-OK` 22/22 JVM+Script |
| Presence + heartbeat (server side) | IMPLEMENTADO E PROVADO | `control/presence.kf`; `USERCHECK-OK`; face-heartbeat lane in `core/helpers.kf` |
| Session coordination (offer/accept/close) | IMPLEMENTADO E PROVADO | `session.kf` + `control/session.kf`; `SESSIONCHECK-OK` |
| Registry persistence + corruption refusal | IMPLEMENTADO E PROVADO | `controlSaveList/controlLoadList` + `REG009`; `PERSIST-OK` 9/9 |
| HTTP route authentication (bearer gate) | IMPLEMENTADO E PROVADO | `httpcheck` `AUTH001` refusal; runtime JWT layer + `auth.authenticated()` |
| HTTP route versioning (`/api/v1` vs plane) | AUSENTE for plane | plane routes are unversioned `/devices /shares /s/*`. Local `/api/v1/*` (this phase) is separate. |
| Rate limiting / request caps on plane | DOCUMENTADO, NÃO IMPLEMENTADO | `next-plan.md` mentions timeouts; no per-IP limiter exists |
| Multi-user account model | IMPLEMENTADO PARCIALMENTE | single-device `accounts.json` map exists; `USERCHECK-OK` covers one-user; no cross-user isolation, no signup flow, no email |
| Password / credential lifecycle (rotation, expiry of account creds) | AUSENTE | JWT bearer has expiry; account credential rotation is not implemented |
| Deployment / TLS on plane | AUSENTE for TLS | plane is plain HTTP at the pin (`web.listen`, TLS is a `listenSecure` face not used) — documented in `architecture.md` |
| Notifications (push, out-of-band) | AUSENTE | plane is polling-only (`/presence`, `/devices/:id` GET); no server push |

## 2. Data plane (`transfer.kf`, `protocol.kf`, `session.kf`, `connect.kf`, `relay.kf`)

| Capability | Class | Evidence |
|---|---|---|
| Direct chunked P2P transfer + resume offset | IMPLEMENTADO E PROVADO | `transfer.kf` chunk stream; `E2E-OK`+`SEC-E2E-OK` (JVM+Script), `RESUMECHECK-OK` |
| X25519 envelope + HKDF encrypt-then-MAC | IMPLEMENTADO E PROVADO | `protocol.kf`; `SEC-E2E-OK` resume@123456; 1-byte tamper refused before plaintext |
| Directory transfer + manifest validation | IMPLEMENTADO E PROVADO | `directory.kf`+`userflow.downDirAuto`; `FOLDERCHECK-OK` incl. `REG015` traversal refusal |
| Named error preservation (`REG*`, `DEV*`, `CONNECTIVITY_FAILED`) | IMPLEMENTADO E PROVADO | goldens read the codes; `errText` only ADDS the human sentence |
| Relay as ciphertext-only fallback | IMPLEMENTADO E PROVADO | `relay.kf` byte pump; `RELAY-OK` flips a byte mid-flight and the tag dies |
| Transport stamping (`DIRECT`/`RELAY`) | IMPLEMENTADO E PROVADO | `pickAndDial` + INTEGRATIONCHECK |
| NAT traversal (STUN/ICE) | SIMULADO as analog | goldens use `dead-port + relay` as the documented NAT analog; real STUN/ICE = AUSENTE (`post-v2-architecture.md` D10 RESERVED) |
| Sealed directory-tree envelope | DOCUMENTADO, NÃO IMPLEMENTADO | decision DEFERRED (`post-v2-architecture.md`); manifest digest-only today |
| Concurrency: revocation race with active transfer | AUSENTE as a test | revocation is proven (`SHARECHECK`) but a live-transfer-during-revoke race is not exercised |

## 3. Local client (browser-app `app/client.kf`, `app/page.kf`)

| Capability | Class | Evidence |
|---|---|---|
| Local HTTP server (`web.app`) for recipient page | IMPLEMENTADO E PROVADO | `client.kf`; `BROWSERCHECK-OK` |
| `/api/info` metadata-only view | IMPLEMENTADO E PROVADO | browserSecrets proof: no keys/bearer leak |
| `/jobs` POST + poll + detached job thread | IMPLEMENTADO E PROVADO | `client.kf`; file-handoff pattern (measured 200ms spawn latency) |
| Versioned API (`/api/v1/*`) | AUSENTE (browser lane) | current routes are `/api/info`, `/jobs`, `/` |
| CSRF / Origin / Host policing on the browser lane | AUSENTE | not enforced in `client.kf` |

## 4. Desktop (`desktop/desktopd.kf`, `desktopcheck/boot.kf`)

| Capability | Class | Evidence |
|---|---|---|
| Daemon lifecycle (`--start`/`--stop`/`--status`/`--window`) | IMPLEMENTADO E PROVADO | `desktopd.kf` + `DESKTOP-BOOT-OK steps=21` (hot+cold) |
| Local token auth (`X-Kof-Token`, 0600 file) | IMPLEMENTADO E PROVADO | `refusal-named`, `token-0600` legs |
| `/api/v1/health`, `/api/v1/state` | IMPLEMENTADO E PROVADO | `health-ok`, `state-ready`, `state-plane-live` legs |
| `/page?tok=` served shell | IMPLEMENTADO E PROVADO (with page-JS caveat) | `page-marker`, `page-refused` legs |
| Page JS sends real token | IMPLEMENTADO PARCIALMENTE | the served HTML has a literal `var tok='KOFDTOKEN';` NEVER substituted; page polling would send the literal — latent bug (fix in Gate-1 safe subset) |
| Origin/Host policing (CSRF, DNS-rebinding defense) | AUSENTE | the daemon answers any bound interface (bind is 0.0.0.0 — pin runtime fact) — Gate-1 safe subset |
| Event stream (`/api/v1/events`) | AUSENTE | not implemented — Gate-1 safe subset |
| Native window (webview/SDL/kof.ui) | AUSENTE on this machine | `node` binary absent (matrix row 19); the delivered shell is the daemon-served page + `xdg-open` |
| Tray / notifications / picker | AUSENTE at pin | no face (discovery §8-C/D/F); degraded v1 documented |
| Windows/macOS support | AUSENTE | §11: Linux x86_64 measured only |

## 5. Packaging, logging, install

| Capability | Class | Evidence |
|---|---|---|
| Launcher script + `.desktop` entry | IMPLEMENTADO E PROVADO (smoke) | `scripts/kofshare-desktop.sh`, `install-desktop.sh`, `uninstall-desktop.sh` — INSTALL/UNINSTALL smoke green |
| Structured logs | IMPLEMENTADO PARCIALMENTE | daemon log = stdout redirected to `kofshare-desktop.log`; no levels, no rotation |
| Diagnostic endpoint without secrets | AUSENTE | `/api/v1/state` is metadata-only (good) but not a diagnostics route |

## 6. Security / trust model

| Capability | Class | Evidence |
|---|---|---|
| Device private key never crosses the UI/API | IMPLEMENTADO E PROVADO | `state-no-secrets` leg + control-plane bearer never echoed |
| Control bearer isolation (browser/UI never sees it) | IMPLEMENTADO E PROVADO | `browserSecrets` proof + `client.kf` view model |
| Path traversal defense (peer paths not trusted) | IMPLEMENTADO E PROVADO | `directory.kf` + `REG015` (FOLDERCHECK traversal refusal) |
| Token-in-URL exposure (`/page?tok=`) | AUSENTE defense | accepted compromise (browser-lane precedent); the local-API spec §1.1 flagged Referer risk — DP in the boundary decision |
| CSRF / DNS-rebinding | AUSENTE | Gate-1 safe subset adds Origin/Host policing |
| Replay of local token | AUSENTE | token has no nonce/rotation-on-use; documented in spec §1.1 |

## 7. Ordered Gate plan (per gigaprompt §6)

Given the audit, the dependency order is exactly the gigaprompt's:

```
Gate 0 — audit                       THIS DOCUMENT                  [done]
Gate 1 — Local API: SAFE SUBSET      origin/host + events + token
                                     hygiene on ALREADY-shipped F1
                                     routes (no privileged mutation)   [this turn]
Gate 1 — PRIVILEGED SUBSET           shares/transfers/cancel         [DP — see below]
Gate 2 — Desktop shell wiring        page JS + tray + picker         [depends on Gate1-priv]
Gate 3 — Core workflows              share/receive progress real    [depends on 1-priv]
Gate 4 — Device management           identity + device UI           [depends on 1-priv]
Gate 5 — Production hardening        rotation/nonce, logs, race     [depends on 3-4]
Gate 6 — Packaging                   install story on a clean host  [depends on 2-5]
Gate 7 — Release verification        full battery + docs            [gate to release]
```

## 8. The gate that IS pending (gigaprompt §5 / §DP)

The **irreversible** choices recorded in `docs/desktop/phase0-matrix.md §DP`:

- **bind-address core face (§8-A)** — token-auth on 0.0.0.0 vs upstream
  `listen(host, port)` (compiler-pin bump) vs Unix socket via `ext` FFI
  (second IPC stack). The gigaprompt §5.4 explicitly forbids choosing
  silently. I do not choose here.
- **kof.ui native vs served page** — requires `node` on the host (matrix row
  19, ABSENT). Toolchain decision, not a code decision.
- **core extraction timing (D8 trigger)** — SHIPPED (commit `f05948a`,
  `RC-CHECK-OK steps=23` on that tree). Not pending.

What I DO implement this turn is decision-free **because it hardens the
already-shipped F1 boundary without expanding privileged capability**, and
every one of these holds under whichever bind option wins the vote:

- Origin / Host policing (defense in depth against DNS-rebinding + forged
  browser requests).
- Read-only `/api/v1/events` with the envelope documented in
  `docs/desktop/api-v1-spec.md`.
- Token hygiene (constant-time-ish compare; token never appears in any
  response body or log line — asserted by tests).
- Page JS bug fix: read token from `location.search` (matching `page.kf`
  precedent) instead of the never-substituted literal.
- Negative tests: missing / invalid / wrong-origin / wrong-host / replay,
  plus recovery-by-state-query after dropped events.

What remains BLOCKED at the §DP gate (this turn does NOT implement):

- `POST /api/v1/shares` (file/dir minting — writes to plane).
- `DELETE /api/v1/shares/:id` (revocation on plane).
- `POST /api/v1/transfers` (starts real byte flow).
- `POST /api/v1/transfers/:id/cancel`.

These turn the 0.0.0.0 exposure into real blast radius (a LAN attacker with
the token could mint shares or trigger downloads). Building them is an
authorization-on-a-weakened-boundary decision the maintainer has not voted
on. The evidence of the gap, the exact alternatives, and the concrete
question are delivered in the final report (§10 of the gigaprompt).
