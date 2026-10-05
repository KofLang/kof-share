# KofShare — architecture (100% Kof)

status: v2 RELEASE CANDIDATE (05/10) — every plane below is implemented and
golden-proven; per-track proofs in `STATUS.md`.
last: decision `D-KOFSHARE-100KOF` (Kof repo, 01/10/2026): KofShare is a 100%
Kof application; JVM interop is NOT a product route. Priority law:
correção → compatibilidade → segurança → testes → simplicidade → feature.

## 0. Laws (non-negotiable)

* 100% Kof — every product line compiles as Kof (JVM + Script faces). No
  `extern`/interop in product code.
* No central file storage — the server is a control plane, never a drive.
* Files stay on the owner's device; a share is an authorization, not a copy.
* Data plane goes device→device whenever possible; the relay is a
  ciphertext-only fallback transport, never a storage tier.
* The wire is honest: a session's `transport` row is stamped by the dial that
  actually happened; NAT traversal is reserved, not faked.
* Named internal errors are a diagnostic contract (REG0xx, DEV-OFFLINE,
  CONNECTIVITY_FAILED, …) — user verbs add a human `Hint:` line ON TOP, they
  never replace or swallow the code.

## 1. Components

```
Control Plane (HTTP, control/)            Data Plane (TCP frames, transfer/)
  identity   device Ed25519                 HELLO → [KEY_EXCHANGE] → READY
  accounts   bearer gate (D3)               → TRANSFER chunks → finalize
  resources  device-scoped logical ids      digest-verified, offset-idempotent
  shares     token/expiry/maxUses/revoke    relay/ (ciphertext-only pump) when
  sessions   claim/advance machine                    direct dial refused
  presence   heartbeat+TTL
        |
        +-- NO FILE BYTES EVER
Local lanes: userflow.kf (up/down/dir/auto), app/client.kf (browser lane's
localhost client), cli/cli.kf (user verbs + operator verbs + CHECK legs).
```

| Component | Role | Runs on | Plane |
|---|---|---|---|
| `cli` | user surface (`share`/`receive`/`stop`) + operator verbs | user machine | both |
| `app client` | browser page's contract: `/api/info`, job queue, receive | recipient machine | local HTTP |
| `node` lanes | owns files+identity; publish/serve/fetch legs | user machine | data plane |
| `control` | the contract above; recomputes dir digests server-side | hosted | control plane |
| relay worker | opaque byte pump between two peers (never parses) | hosted | transport |

One product, two deployment modes (client / control); `server --start`
detaches + waits for `/health` readiness; `stop` kills only what this device
started (pidfiles + ss-sweep by port).

## 2. Domain model (Kof)

`domain.kf` v1 records (Device/OfferInfo/Transfer/Chunk, ISO-string clocks)
plus v2:

```
resource.kf   Resource(kind FILE|DIRECTORY, deviceId, resourceId r-<hash>,
                      name, size, digest, logicalPath, children)
              binding table resource<->path: LOCAL only, device-scoped —
              the remote plane never carries a path (wireNoLayout proof)
directory.kf  DirEntry/DirTree; sortEntries = root-first lexicographic;
              directoryDigest = H(children only) — root excluded, cycles
              refused (dirValidate rejects `..`/absolute/`/`-escape)
identity.kf   Ed25519 keypair per install; challenge-signed enrollment;
              identityBoot is idempotent across restarts
session.kf    claim/advance state machine + X25519/HKDF sealed envelope
              (encrypt-then-MAC; tamper refused BEFORE bytes hit the file)
connect.kf    classifyConnect/pickAndDial: honest DIRECT→RELAY selection
              (probe by net.connect, then stamp the real result)
```

Share = token with expiry, maxUses (`--once` = single-use), readOnly, dir
flag. One link per tree; `?child=N` selects the N-th FILE of the
server-sorted manifest (`/s/:token` + grant selector, `GET /api/shares`).

## 3. Identity, trust & auth

* Device: Ed25519, TOFU enrollment, revocation is transitive (kills grants
  and live links through the device — `revokedDevice` proof).
* Person/account: register/login → bearer token; every mutating route and
  grant resolution is bearer-gated or token-gated (`accountGate` proof).
* Channel: X25519 ECDH → HKDF → per-direction AES-GCM + HMAC tag, first
  tagged chunk = key confirmation (`--secure`; sealed dir-tree lane is
  documented-deferred, not faked).
* Browser: talks ONLY to the local client; keys, bearers and paths never
  cross to the page (`browserSecrets` proof).

## 4. Transfer protocol (data plane)

1. `HELLO` — version + ids + token; directory face appends child manifest
   info BELOW the v1 sentinel line (additive, v1 peers unaffected).
2. `KEY_EXCHANGE` (sealed) — X25519 both ways over HELLO frames.
3. `READY` — `Transfer{totalBytes, sha256, chunkSize, resumeOffset}`.
4. `TRANSFER` — `len | index | cipher(hex) | tag(HMAC over cipher)`;
   receiver verifies tag then writes `file.part` at offset (idempotent).
5. finalize — whole-file SHA-256 → atomic move; DIRECTORY pull = one
   session per child, resume/verify per child (`dirPerChildResume` proof).
6. failure — safe by construction: offset-idempotent, re-run continues.

`sendChunks`/`fetchRest` are shared between v1 and dir lanes (no fork).

## 5. Directories as logical collections (D6 + Track G/H)

Publish: walk + validate local → manifest (logical paths) → plane recomputes
the digest (REG015 mismatch / REG016 malformed refuse BEFORE insertion).
Receive: single link; per-child grant resolution through the local client;
`dirJoinSafe` re-validates every landing path client-side. Identical content
on two devices = two resources (device-scoped ids — `RESOURCECHECK-OK`).

## 6. Connectivity (Track D/H)

`pickAndDial` order: DIRECT probe → RELAY (only with a relay worker) →
`CONNECTIVITY_FAILED` named error + human hint (`noPath` proof). NAT/ICE
slot reserved in the strategy; STUN/ICE does not exist in Kof4j — the
goldens use dead-port+relay as the documented NAT analog. Honest claim only:
transport on the session row comes from the dial that happened.

## 7. UX layer (Tracks I/H)

`share`/`receive`/`stop` = the whole product for users; `--raw` keeps the
machine lines for scripts. Rules proven by `UXCHECK-OK`: first run works
from the five README lines (self-spawn via `kofshare-cli.config`, no env
vars); no stack trace reaches a terminal (`errText` maps named errors);
links copy-pasteable and single-use when asked; restarts don't orphan faces
(`freePort` + pidfile stop). Operator verbs keep v1 flags 100% compatible
(`--once` consumes via `downAutoWithGrant`, never double-shares).

## 8. Module layout (landed)

```
src/main/kof/kofshare/
  domain.kf protocol.kf session.kf transfer.kf relay.kf   v1 core
  identity.kf account.kf resource.kf directory.kf connect.kf
  control/{registry,app,share}.kf        plane: routes + recomputes + grants
  userflow.kf                            up/down/dir/auto lanes
  app/client.kf                          browser-lane localhost client
  cli/cli.kf                             verbs + 14 CHECK legs
  goldens: control/check, httpcheck, relaycheck, e2e, usercheck,
    identitycheck, sessioncheck, connectcheck, browsercheck,
    resourcecheck, foldercheck, servecheck, resumehash, persistcheck,
    sharehash, restart, uxcheck, integrationcheck, rc/runrc.kf
```

## 9. Test plan (RED-first) — status

| Layer | Proof | Status |
|---|---|---|
| Compile | `--check` 14 legs JVM+Script; 39/39 files check-clean | ✅ |
| Domain/pure | goldens per module (`--check` legs 1–14) | ✅ |
| Control plane | HTTP E2E (`HTTPCHECK`, `PERSIST-OK`, `RESTART-OK`) | ✅ |
| Data plane | JVM+Script E2E (`USERCHECK`…`RELAY-OK`, `SECURE`) | ✅ |
| Directories | `FOLDERCHECK-OK` (13 legs) | ✅ |
| UX | `UXCHECK-OK` (15 legs) | ✅ |
| Full product | `INTEGRATIONCHECK-OK` (22 legs, real processes) | ✅ |
| Release | `RC-CHECK-OK` full battery (`rc/runrc.kf`) | RC gate |

## 10. Known gaps (honest)

* COMP002 + HTTP-ConnectException upstream packets: `docs/upstream/`.
* Sealed-envelope directory trees: deferred, documented.
* `web.app().listen()` binds 0.0.0.0 (runtime contract) — plane page is
  LAN-reachable by construction.
* GUI/billing/Android/central storage: out of scope by design.
