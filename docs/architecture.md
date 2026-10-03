# KofShare — architecture (100% Kof)

> O trabalho faltante está fatiado, ancorado e ordenado em [`implementation-plan.md`](implementation-plan.md) / [`implementation-plan.pt_BR.md`](implementation-plan.pt_BR.md) (02/10).

status: SPEC (domain model compile-validated on the Kof tip 01/10; implementation blocked on stdlib front — see §9)
last: decision `D-KOFSHARE-100KOF` (Kof repo, 01/10/2026): KofShare is a 100% Kof application; JVM interop is NOT a product route.
location: repository
state: active

## 0. Laws (from the decision, non-negotiable)

* 100% Kof — every product line (client, server, CLI, protocol) compiles as Kof on the target. No `extern`/interop in product code.
* No central file storage — the server is a control plane, not a drive.
* Files stay on the owner's device; a share is an authorization, not a copy.
* Data plane goes device→device whenever possible; the relay is an encrypted fallback transport, never a storage tier.
* Honest blocking: while the stdlib socket front (§9) does not exist, the product is BLOCKED, not worked around.

## 1. Components

| Component | Role | Runs on | Plane |
|---|---|---|---|
| `kofshare` (CLI) | user surface: share / download / devices | user machine | client |
| `node` | owns files + device identity; accepts peer sessions | user machine | data plane |
| `control` | identity registry, authorization, discovery, signaling relay | hosted server | control plane |
| relay transport | end-to-end-encrypted byte pipe when direct P2P fails | hosted server | transport fallback |

The product is ONE Kof program compiled for two deployment modes (`node`, `control`); the CLI is the user driver of `node`. No third-party runtime is assumed anywhere.

## 2. Domain model (Kof)

```
enum ShareScope { Device, Person, Public }        // Public = link-only, still token-gated
enum SessionState { Hello, KeyExchange, Ready, Transferring, Done, Failed }

record Device(String id, String pubKey, String label, String lastSeenIso)
record Person(String id, String label)
record Share(String id, String deviceId, String pathDigest, String label,
             ShareScope scope, String token, String? expiresAt,
             Boolean allowResume)
record Link(String id, String shareId, String url, String createdAtIso)
record PeerSession(String id, String shareId, String peerDeviceId, SessionState state,
                  String cipherSuite, String keyHash)
record Transfer(String id, String shareId, String peerDeviceId, SessionState state,
                Int offset, Int totalBytes, String sha256)
record Chunk(Int index, Int offset, Int length, String digest)
```

**Compile-validated on the Kof 0.5.0-beta tip (01/10):** `kof check` + `main` execution green (`Share("s1", …, ShareScope.Device, …)` → id prints). Enums are constants-only (`enum Name { A, B }` — PARSE034 guards the `|` form); timestamps are ISO `String`/`String?` until a temporal value type exists; `pathDigest` is `crypto.sha256` over the canonical path bytes.

## 3. Identity & trust

* A device generates an **Ed25519** keypair; the private key never leaves the device (`security`/`secrets` storage face).
* Device registration: `control` stores `Device{id, pubKey}` after an ownership proof (challenge → sign → verify).
* Peer trust is the *link/token*, not the transport: whoever presents a valid token for an unexpired `Share` is authorized. TLS/Noise-level channel encryption is still required and is provided by the data-plane session (§5), never assumed from the network.
* Key exchange: **X25519** ECDH → HKDF session keys → **AES-GCM** chunk framing — LANDED 02/10 over the stdlib `keyExchange` face (D-KOF-X25519): `session.kf` with HELLO frames (pub 64-hex + server salt), per-direction HKDF keys (enc/mac × c2s/s2c) and encrypt-then-MAC on the transfer framing (split out of `handshake.kf` on 03/10 into `protocol.kf` framing/codec + `session.kf` state machine; §10 of `docs/stdlib/security.md` in Kof4j; the interop probe of 01/10 became the real face).

## 4. Control-plane contract (HTTP, Kof `web`/`http` stdlib)

```
POST /v1/devices                 {label, pubKey, challengeSig}      -> Device
POST /v1/devices/{id}/proof      {nonce, sig}                       -> token
POST /v1/shares                  {deviceId, pathDigest, scope, ttl} -> Share+Link
GET  /v1/shares?mine=token                                          -> List<Share>
DELETE /v1/shares/{id}                                              -> 204
GET  /v1/resolve/{linkId}        {peerPubKey}                       -> {ownerDeviceId, candidateAddrs[], shareMeta, tokenClaims}
POST /v1/sessions                {shareId, peerDeviceId, offerKey}  -> PeerSession (relays signaling until direct/relay established)
GET  /v1/sessions/{id}           -> PeerSession
```

* The control server stores **metadata only**; it cannot read file content (chunk ciphertext never passes it in cleartext).
* The relay fallback transports **ciphertext only** (end-to-end encrypted session; the relay is untrusted for content).

## 5. Transfer protocol (data plane, Kof)

Session (device↔device, or device↔relay↔device):

1. `HELLO` — plaintext framing: protocol version + device ids + share token.
2. `KEY_EXCHANGE` — X25519 public values both directions over HELLO frames; per-direction session keys derived by HKDF-SHA256; the first tagged chunk is the key confirmation (v1 transcript binding — `session.kf`, landed 02/10, split 03/10).
3. `READY` — authorized + encrypted channel; exchange `Transfer{totalBytes, sha256, chunkSize, resumeOffset}`.
4. `TRANSFER` — chunks: `len(4) | index(4) | cipher(hex-ASCII AES-GCM) | tag(64 hex HMAC-SHA256 over the CIPHER bytes)` — encrypt-then-MAC, receiver verifies the tag BEFORE unwrapping and writes `file.part`.
5. finalize: whole-file SHA-256 verified → atomic `moveTo` `file.part` → `<name>`; session `DONE`.
6. `FAILED` — resume is safe: the protocol is offset-idempotent; re-download only missing chunks.

Chunk framing semantics (`channel`+`readRange`+`hmacSha256` composition) were measured green on 01/10 — the interop probes are the spec's test oracle.

## 6. CLI surface (Kof `kof-cli`-style app in the product repo)

```
kofshare share <path> [--to person|device|link] [--ttl <iso>]  -> link URL
kofshare download <kofshare-link> [--out <dir>]                 -> verified file
kofshare devices                                                -> registered Device list
kofshare shares [--mine]                                        -> Share list + revoke
```

`main(args: List<String>)` (measured face); no ceremony types, no DI framework — the Kof `platform` rules apply.

## 7. NAT traversal (MVP position, honest)

* MVP: direct connect on LAN + relay fallback through the `control` host (ciphertext only). **LANDED 03/10** — `relay.kf` is a framing-agnostic byte pump that forwards opaque bytes between the two peers and never parses the wire format, so the relay is untrusted for content by construction; `fetch --relay` and the `relay` command drive it, proven `RELAY-OK` on JVM+Script (direct == relayed; a tampering relay is refused by the envelope tag with nothing appended).
* STUN/ICE-grade traversal is an explicit post-MVP extension point (`resolve` already returns candidate addresses). No hole-punching is claimed.

## 8. Test plan (RED-first)

| Layer | Proof |
|---|---|
| Domain | record invariants compile + golden JSON round-trip (`json.encode/decode<T>`) |
| Protocol framing | pure-Kof unit tests on the session state machine, byte-goldens vs the measured probe oracle (01/10) |
| Control plane | HTTP-handler E2E (Kof `web`) on JVM + Script |
| Data plane | device↔device echo/transfer E2E **once the stdlib sockets exist** (§9); relay path behind the same interface |
| CLI | golden CLI runs with `--check`/`--dry` |

## 9. Required stdlib capabilities (the honest block — Kof repo §559/`D-KOFSHARE-100KOF`)

Product code may not start its network layer until these exist in Kof itself (no interop, no shim):

1. **TCP sockets** in the network namespace: listen / accept / connect / send / receive (+close).
2. **X25519 key agreement** LANDED as the `keyExchange` namespace (D-KOF-X25519, 02/10 — SECN005 unblocked for KofShare); Ed25519 sign/verify remains a separate future face (out of envelope v1).
3. AES-GCM already exists (`crypto`); the `hkdfSha256` face landed with `keyExchange` (02/10).
4. Open naming/blocking questions shared with `D-UDP` (namespace `kof.net` vs extension, blocking model, message types) — **rule 6, maintainer decides**; `D-KOFSHARE-100KOF` records the decision *that the front is (a) stdlib*, the surface still awaits its answers.

## 10. Module layout of the product (LANDED 03/10)

```
kof.toml                       [project] kof-share / [backend] jvm / [sources] app
src/main/kof/kofshare/
  domain.kf                    records (Device/OfferInfo/Transfer) + JSON
  protocol.kf                  framing + codec (slice 4)
  transfer.kf                  plain state machine (serveFile/fetchFile)
  session.kf                   X25519/HKDF sealed state machine (slice 4)
  relay.kf                     ciphertext-only relay pump (slice 5)
  e2e.kf                       plain + secure end-to-end oracle
  cli/cli.kf                   product entry (slice 3)
  server/server.kf             control daemon entry
  control/registry.kf          pure device/offer registry
  control/app.kf               HTTP surface over the registry
  control/check.kf             registry golden
  httpcheck/checkhttp.kf       HTTP client golden
  relaycheck/checkrelay.kf     relay oracle (slice 5)
  probe/tamper.kf              tamper refusal probe
```

(one responsibility per file, Kof philosophy: names describe responsibility;
the entry lives in its own subpackage because the module enforces ONE
`main()` per package, `PKG002`)
