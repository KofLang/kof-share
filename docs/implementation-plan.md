[English](implementation-plan.md) | [Português](implementation-plan.pt_BR.md)

# KofShare — implementation plan (what is missing, as slices)

**Owner:** `192.168.15.15:9092` (lane security/connectors; `D-PLAN-ONE-OWNER` applies to this file too — it lives in the product repo, not in `Kof4j/docs/development/`).
**Base:** tip `c7a7946` (transfer core + session envelope, measured `E2E-OK`/`SEC-E2E-OK` JVM+Script, `TAMPER-OK`).
**Scope law:** the product stays 100% Kof (`D-KOFSHARE-100KOF`) — no interop, no shims, no invented stdlib faces. Everything below rides ONLY on measured stdlib surfaces (anchors listed per slice). Anything requiring a new language surface is rule-6 → maintainer, never an agent decision.

## 0. Ready vs missing (measured, not remembered)

READY (in-tree at base, green re-measured with the tip jar):
* `transfer.kf` — framing `len|index|payload`, offset-idempotent resume, per-chunk HMAC-SHA256 over hex AAD.
* `protocol.kf` — framing + codec (`headFrame`/`be32`/`recvRaw`/`hexOf`/`tagHex` + ASCII/hex codec); `session.kf` — ephemeral X25519, HELLO (index `1073741822`, 64-hex pub + server salt), HKDF-SHA256 directional keys, encrypt-then-MAC over the cipher (split out of `handshake.kf` 03/10).
* `e2e.kf` — plain leg (resume@100000) + secure leg (resume@123456), 200000 B, both targets.
* `probe/tamper.kf` — legacy tamper + the 5 envelope assertions.
* `domain.kf` — records + JSON round-trip.

MISSING (the whole control plane, CLI, module split, relay, packaging):
1. `control/` — device registry + offers over HTTP (`architecture.md` §4). No code exists.
2. `cli.kf` — `server` / `offer` / `fetch` with `--check` / `--dry` goldens (§6).
3. ~~`session.kf` / `protocol.kf` — the state machine is inline in `transfer.kf`/`handshake.kf`; one-responsibility split (§10).~~ **DONE 03/10** (see Slice 4 LANDED).
4. ~~Relay fallback — direct LAN works in the e2e; relay-via-control (ciphertext only, §7 MVP position) has no handler.~~ **DONE 03/10** (see Slice 5 LANDED; `relay.kf` + `relaycheck/checkrelay.kf`).
5. Packaging — no `kof.toml`, no product tree, no run script.
6. Device identity/trust — Ed25519 signing is NOT a Kof face (interop-over-JDK guidance only) → **rule-6, out of v1**, recorded as an honest limitation (passive-MITM is dead; active MITM of the key exchange is NOT refused — the envelope v1 position, stated plainly).

## 1. Measured stdlib anchors (the plan may not assume anything else)

* `web.app()` → `app.get("/p") { ... }`, `app.post(...)`, `param("id")`, `body()`, `status(code, text)`, `app.listen(port)` — live subprocess server + `http` client over loopback is GREEN in `KofHttpE2ETest` (JVM; server compiled+forked as a subprocess, client in-process).
* `http.get/post/put/delete/patch/options/status(url, headers...) -> String` — stable JVM + JS (byte-parity, `learn/stdlib/http.md`); Native has partial (`HTTP002` on the missing pieces). **Script leg: NOT yet measured — slice 2 proves or refuses it first.**
* `json.encode` / `json.decode<T>` — golden-proven in `domain.kf` (JVM+Script).
* `kof.net` TCP (`listen/accept/connect/send/receive/close`) — real on JVM, Native x86-64, riscv64/aarch64, JS-host, Script (D-KOF-NET slices 1–5 + 4b).
* `random.hex(n)`, `crypto.*`, `keyExchange.*` — landed (envelope base).
* Honest refusals already encoded at the typer: `NETN001` (net on JS), `SECN012` (keyExchange on JS/Native), `INTEROP009/010` (foreign faces/failures).

## 2. Slices (dependency order; each is one committable unit, RED-first)

**Slice 1 — `control/registry.kf` (pure domain, zero IO).**
Registry model: devices (`id → {name, addresses, lastSeen}`), offers (`id → {device, path, size, sha256Hex, resumeOffsetHint}`), `register/resolve/listOffers/revoke` as pure functions over in-memory maps + JSON encoders. Proof: `RegistryE2ETest` — same source, JVM + Script, golden (register 2 devices, offer, resolve, revoke, malformed JSON refused by name via `catch`). DoD: green both targets, no stdlib invention, `json.decode<T>` invariants tested.

**Slice 2 — `control/app.kf` (HTTP surface over registry).**
`web.app()` with the §4 contract routes: `POST /devices` (register, body = signed-by-envelope nothing — v1 is LAN-trust), `GET /devices/:id`, `GET /offers?device=`, `POST /offers`, `DELETE /offers/:id`, `GET /health`. Handlers mutate ONLY an in-memory registry (one process; persistence = slice 5 keystore or refused honestly). Proof: `ControlPlaneE2ETest` cloning the `KofHttpE2ETest` harness (server subprocess + `http.get/post` client over loopback, JVM) **plus a first measurement of `http`+`web` under `--target script`** — if Script refuses, the refusal is recorded here by name and the Script leg is dropped honestly (R6: measured, not assumed). DoD: golden register→offer→resolve→fetch-metadata round-trip; 404/400 refused by name.

**LANDED 02/10 (`control/app.kf` + `server/server.kf` + `httpcheck/checkhttp.kf`):** 14/14 golden true + `HTTPCHECK-OK` in ALL THREE combos — JVM server+JVM client, SCRIPT server+JVM client, JVM server+SCRIPT client. The first Script measurement failed (`HTTP 500` on every interpreted handler — the slice pinned it honestly as Kof4j §574 for ~1h) and the same day the fix landed: `InterpretedCallable` bridge in the interpreter (`ScriptWebRouteE2ETest` RED-first) — that is why the Script legs are green now. Design notes recorded: server = own process (`listen` blocks; stop = process lifecycle) after the `/shutdown` experiment hit Kof4j §575 (a closure capturing the phantom `web.app()` handle materialized `Lkof/web/App;` as a lambda field → `NoClassDefFoundError` at JVM LOAD — FIXED the same day at the `JvmTypeMapper.toDescriptor` chokepoint; routes here still capture only the registry maps by DESIGN — daemon lifecycle = process lifecycle). Proof form: the golden lives product-side (`checkhttp.kf`, same pattern as `e2e.kf`) instead of a Kof4j `ControlPlaneE2ETest` clone — identical evidence, fewer repos.

**Slice 3 — `cli.kf` (product entry).**
`main(args)`: `server` (control+registry + serves offers), `offer <file>`, `fetch <offerId|url> <dest> [--resume]`, `--check` (full golden: spin registry in-process, register/offer/resolve, run the e2e envelope legs over `kof.net` loopback, print `CHECK-OK`), `--dry` (print the resolved plan, no IO). Args via `String[] args`; JSON bodies via `json`. Proof: golden CLI transcript test (same pattern as `e2e.kf` run instructions; output byte-identical JVM+Script where faces are real). DoD: `--check` is the one command the maintainer can run to see the whole product green; refusals named.

**LANDED 03/10 (`cli/cli.kf`, package `kofshare.cli`):** the product entry is real on JVM+Script. `--check` prints `registry=true plain=true secure=true` then `CHECK-OK` on BOTH targets (pure registry leg + plain transfer leg resume@100000 + secure X25519/HKDF envelope leg resume@123456, real `kof.net` loopback). `offer <file>` prints the `OfferInfo` JSON with a REAL content digest (`crypto.sha256Bytes` over the file bytes — `ba7816…` for `abc`, proven JVM==Script); `fetch <host> <port> <dest> [--resume] [--key <hex>]` pulls over `kof.net` and was measured byte-identical (5000 B) direct AND resuming from a 2000 B `.part` (`offset=5000/5000`, `cmp` clean); `--dry` prints the plan with no IO. Refusals are named (`OFFER-ERR`, `FETCH-ERR`, `DRY-ERR`, `CHECK-FAIL`) and `main` throws on failure (exit ≠ 0) since `Int main()` is removed (Kof `SEM044`). **Honest divergences recorded:** (a) `resumeOffsetHint` from §2 is NOT in the landed `OfferInfo` (`id/deviceId/path/size/sha256Hex`); the resume offset is coordinated out-of-band, so a bare `--resume` continues from the existing `.part` size and the PEER must `serveFile` from the same offset — a true mid-transfer offset negotiation is NOT implemented (slice-5 relay scope, documented not silent). (b) the module enforces ONE `main()` per package, so the entry lives in its own subpackage `kofshare.cli` (a root `kofshare/cli.kf` collides `PKG002` with `e2e.kf`'s `main`). (c) `File.size()` is a method, not a property (`SEM102`).

**Slice 4 — `session.kf`/`protocol.kf` extraction (no behavior change).**
Move the envelope state machine (HELLO/keys/frames) out of `transfer.kf`/`handshake.kf` into `protocol.kf` (framing + codec) and `session.kf` (handshake + keys + sealed send/receive), per §10 one-responsibility; `e2e.kf`/`probe/tamper.kf` stay the SAME goldens byte-for-byte — that is the proof of the refactor. DoD: all existing goldens green on both targets + refactor diff contains zero new semantic faces.

**LANDED 03/10 (`protocol.kf` + `session.kf`; `handshake.kf` deleted).** `protocol.kf` now owns the pure wire helpers (`metaIndex`/`chunkSize`/`tagLen`, `headFrame`/`be32`/`concatBytes`/`recvRaw`, `hexOf`/`tagHex`, `helloIndex` + the ASCII/hex codec), and `session.kf` owns the sealed state machine (`helloFrame`/`helloBody`/`sessionKeys`/`wrapChunk`/`unwrapChunk`/`readHello`/`serveFileSecure`/`fetchHandshake`/`serveLoopEncrypted`/`fetchFileSecure`). `transfer.kf` is now only the plain state machine (`serveFile`/`fetchFile`) plus the byte-oracle helpers. Import edges updated (`e2e.kf`/`cli.kf` → `session`, `probe/tamper.kf` → `protocol`+`session`). **Proof (byte-identical to the pre-refactor baseline):** `e2e.kf` JVM **and** Script → `SEC-E2E-OK` + `E2E-OK` with the same `len=200000/200000 sum=25499232/25499232 mismatch=-1 done=true offset=200000/200000`; `probe/tamper.kf` JVM → `TAMPER-OK` (all envelope refusals true); `cli --check` JVM **and** Script → `registry=true plain=true secure=true` + `CHECK-OK`. No new semantic face; the only code-shape change is the tag compare now `asciiOf(tag) != tagHex(...)` (equivalent to the old per-byte loop, proven by the tamper golden).

**Slice 5 — relay fallback (LAN-direct first, relay ciphertext-only).**
`fetch` tries `connect(deviceAddr)`; on refusal falls back to the control host relay: opaque chunk frames forwarded byte-for-byte between the two peers' TCP connections (control never sees plaintext — the envelope already encrypts the transport). Proof: `RelayE2ETest` — two peers + relay, all three sockets on loopback with distinct ports, golden equal to the direct path output; tamper-at-relay refused (relay flipping a byte = envelope tag death, reuse `probe/tamper.kf` assertions on the relayed leg). DoD: honest statement that traversal ≠ hole-punching (STUN/ICE = post-MVP, architecture §7).

**LANDED 03/10 (`relay.kf` + `relaycheck/checkrelay.kf`).** The relay is a framing-agnostic byte pump (`relayPump`/`relayPumpTamper` + `relayServeOn`/`relayServeTamperOn`/`relayServe`): it forwards opaque bytes between the client and the peer and never parses `protocol.kf` headers, so it cannot inspect or rewrite payloads. It closes the destination on source EOF (half-close propagation) and treats a read/send on a socket the sibling direction already closed as end-of-stream, so a relay does not die when one side hangs up. Proof (`checkrelay.kf`, JVM **and** Script → `RELAY-OK`): `direct=true` (secure baseline), `relayed=true` (client → relay → peer, byte-for-byte identical 200000 B with resume@100000), `tamperRefused=true` (the relay flips the ciphertext byte at absolute offset 300 → the client's envelope tag refuses and **nothing is appended**, `out.size == resume`). CLI wiring: `fetch ... [--secure] [--relay <rhost> <rport>]` and a `relay <port> <peerHost> <peerPort> [--tamper]` command; measured end-to-end through the CLI (`fetch --relay --secure` → `FETCH-OK offset=5000/5000`, relay logs `RELAY-READY`). **Honest divergence:** the CLI does not auto-detect a refused direct connect and fall back — the operator chooses `--relay` explicitly (the plan's "tries direct then falls back" is available as `relay`/`--relay`; an automatic catch-and-retry would require distinguishing a refused connect from a mid-handshake failure, deferred with the STUN/ICE work). Traversal ≠ hole-punching: no STUN/ICE, no NAT punching claimed (architecture §7).

**Slice 6 — packaging + docs.**
`kof.toml` (module entry points for `server`/`cli`), `README` run instructions updated to the CLI, `architecture.md` §10 tree marked LANDED per slice with the measured refusals, this plan gets a STATUS line per slice. DoD: fresh clone → `java -jar kof-cli.jar run cli.kf -- --check` green; docs-lang style parity EN+PT for this repo's docs.

**LANDED 03/10 (`kof.toml` + docs).** `kof.toml` declares `[project] name = "kof-share"`, `[backend] target = "jvm"` and `[sources] app = "src/main/kof"` — the manifest the CLI's `ProjectLocator` reads; the explicit `--target` on the command line still overrides the backend target, and `--check` stays green on JVM and Script with the manifest present. `architecture.md` §10 now shows the real landed tree (one responsibility per file; the `PKG002` one-`main()`-per-package note), and §3/§5/§7 carry the slice-5 relay. The README run instructions cover the CLI, the relay and the manifest.

**STATUS per slice:** 1 registry LANDED · 2 control plane LANDED · 3 CLI LANDED · 4 protocol/session split LANDED · 5 relay LANDED · 6 packaging LANDED. All six slices of the authorized KofShare plan are landed; the remaining rule-6 items are listed in §3 (identity/Ed25519, hole-punching, JS/Native product targets).

## 3. Out of scope / rule-6 (do not implement without a decision)

* Device identity & active-MITM trust (Ed25519 face, certificates, TOFU) — no stdlib face exists; the envelope v1 ships with the documented limitation.
* Hole-punching / NAT traversal beyond relay — §7 post-MVP.
* JS/Native product targets — blocked upstream by `NETN001`/`SECN012` (out of v1 scope, recorded).
* Any new language surface discovered mid-slice → STOP + rule-6 question (like `D-INTEROP-ERR-TYPE` was), never a local workaround in the product.

## 4. Verification discipline (every slice)

RED-first (test before code); JVM+Script goldens for real faces; named refusals for everything else; `probe/tamper.kf` and both e2e legs re-run at the end of every slice (regression floor); commit per slice with measured numbers; no claims about targets that were not run.
