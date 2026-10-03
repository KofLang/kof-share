[English](next-plan.md) | [Português](next-plan.pt_BR.md)

# KofShare — what is missing (as slices)

**Owner:** `192.168.15.15:9092` (lane security/connectors; `D-PLAN-ONE-OWNER` applies).
**Status of the previous plan:** `implementation-plan.md` is COMPLETE (all 6 slices landed; `--check` → `CHECK-OK` JVM+Script at tip `b6596ef`). This file is the successor: what is left, ordered by dependency, split between (A) work that needs NO decision and (B) rule-6 items that need a maintainer vote first.
**Scope law:** the product stays 100% Kof (`D-KOFSHARE-100KOF`) — no interop, no shims, no invented stdlib face without rule-6. Every claim below was measured at this tip (03/10), not remembered.

## 0. Measured state of the edges this plan touches

* `crypto` today: `sha256`/`sha256Bytes`, HMAC, `keyExchange` (X25519, D-KOF-X25519). **`grep -rli ed25519` across `kof-compiler/src/main/java` = ZERO** — there is no signing face at all (B1 is genuinely missing, not hidden).
* `InterpretedCallable` exposes only `invoke()` and `invoke(String×5)` (HTTP routes). The runtime also reflects `invoke(SseConnection)` (SSE) and WS message handlers — the Script bridge for those is NOT done (A2; §574's fix scope note says the same).
* Persistence faces exist and are measured: `File.readText()`/`File.writeText(s)` instance forms (D-FILE-STATIC keeps static arms unwired). `json.encode(record)`/`json.decode<T>` work on packaged records (§573 fixed; `--check` registry leg uses them).
* The CLI has no mid-transfer resume NEGOTIATION: `fetch ... --resume` continues from the local `.part` size and the peer must `serveFile` from the same offset; `OfferInfo` has no `resumeOffsetHint` field (measured: absent at tip).

## 1. Track A — decision-free (Kof faces already exist)

**Slice A1 — registry persistence (crash-doesn't-forget).**
`control/registry.kf` gains `saveRegistry(path)` / `loadRegistry(path)`: `json.encode` of the devices+offers maps (sorted keys keep goldens stable), atomic-ish write via temp file + rename using only measured `file`/`path` faces; corrupt file → named `REG009` refusal, never silent empty. `server.kf` and `cli.kf server` load at boot and save after every successful mutation. Proof: golden `checkpersist.kf` (JVM+Script): register 2 devices + 2 offers → save → fresh load → byte-identical listings + `RESOLVE-SAME` assertions; tamper the file by 1 byte → `REG009`. DoD: `--check` extended with a persistence leg (`persist=true`).

**Slice A2 — Script SSE/WS bridge (§574 residual).**
Kof4j-side (compiler lane): `InterpretedCallable` gains the handler shapes the runtime reflects for SSE (`invoke(SseConnection)`) and WS messages, delegating to `invokeLambda` exactly like the HTTP arms; interpreted handlers receive the connection object the same way compiled ones do. Proof: RED-first sibling of `ScriptWebRouteE2ETest` (SSE send-through + WS echo over loopback under `--target script`). DoD: §574's "SSE/WS not covered" scope note retired; no KofShare code required (the product gains the capability by target parity). **Boundary:** if WS handshake under interpretation hits a deeper interpreter gap, record the refusal by name (R6) instead of forcing — the HTTP/SSE split is one committable unit.

**Slice A3 — honest resume negotiation.**
Server (`serveFile` path) already answers a client-chosen offset; make it explicit: `fetch --resume` sends its local `.part` size in the HELLO/meta exchange and the SERVER verifies it (≤ size) and serves from it — a wrong offset refuses by name (`RESUME-ERR: server file shorter than requested offset`) instead of corrupting. `resumeOffsetHint` is NOT added to `OfferInfo` (the offer describes the file, not a session). Proof: golden — 5000 B file, `.part` of 2000 → `offset=5000/5000` + `cmp` clean (already measured, now asserted through the negotiation), plus the refusal case (hint > size). DoD: the plan-v1 "peer must cooperate out-of-band" divergence note is retired.

**Slice A4 — offer expiry + registry hygiene (cheap, pure).**
`OfferInfo` unchanged; registry gains a `purgeExpired(nowMs, ttlMs)` pure function + `/offers` listing already sorted; server calls it at boot and after mutations. Proof: pure golden lines in `check.kf` (JVM+Script). DoD: named `REG010` refusal only where needed (never silent behavior).

## 2. Track B — rule-6 (needs the maintainer's vote BEFORE code)

**B1 — Device identity + offer signing (Ed25519).**
The trust hole of v1: anyone can register a device and claim any path. Landed stdlib has X25519 key exchange (`D-KOF-X25519`) but NO signing face (measured: zero Ed25519 anywhere). A 100%-Kof signature needs a new stdlib face (proposal: `crypto.sign`/`crypto.verify` over `Byte[]` + `KeyPair` handling on `Secret`, JVM first; JS/Native honest refusals per `SECN012` family). **Decision asked:** (i) approve the new face (name it, freeze the contract), (ii) defer identity to post-1.0 and document v1 = LAN-trust-only, or (iii) route through interop (`java.security` via `interop`, touches `D-KOFSHARE-100KOF`). NOT started without the vote.

**B2 — NAT traversal (STUN/ICE, hole-punching).**
The relay covers "both peers reachable by the control host"; it does NOT cover two peers behind separate NATs with no inbound ports. Pure-hole-punching needs UDP rendezvous + timed simultaneous open + the relay as fallback-of-fallback — all `kof.net` UDP faces EXIST and are measured (slice 5 of the network plan). No stdlib decision needed to TRY a Kof-level ICE-lite, but the architecture calls hole-punching post-MVP (architecture §7), so it is listed here as the maintainer's call on scope, not on faces. **Decision asked:** schedule an ICE-lite slice (pure Kof, no new stdlib face) or keep traversal = relay-only.

**B3 — JS/Native product targets.**
`kof.net` on JS refused at compile (`NETN001`, `D-KOF-NET` amendment), `keyExchange` JS/Native refused (`SECN012`); both are honest, pinned refusals. The v1 product = JVM server + Script/JVM peers. **Decision asked:** none required to stay as-is; reopen only if the maintainer wants browser peers (needs both refusals fixed first) or a Native headless appliance.

## 3. Not in this plan (explicitly)

* GUI/desktop of any kind (out of the authorized scope).
* Multi-process persistence (single writer assumed; the file lock face exists but A1 stays lock-free by design: one server process owns the file).
* Upstream/CI packaging beyond `kof.toml` (slice 6 landed) — release protocol is repo-side (`D-RELEASE-CADENCE`).

## 4. Order and cadence

A1 → A3 → A4 (product-side, JVM+Script goldens, each = one committable unit, RED-first) · A2 (compiler lane, independent, can interleave) · B1/B2/B3 stay blocked until the maintainer answers. The `--check` command accumulates a leg per landed slice — the single-command proof of the product stays true.
