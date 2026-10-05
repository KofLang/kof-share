[English](next-plan.md) | [Português](next-plan.pt_BR.md)

# KofShare — what is missing (as slices)

**Owner:** `192.168.15.15:9092` (lane security/connectors; `D-PLAN-ONE-OWNER` applies).
**Status of the previous plan:** `implementation-plan.md` is COMPLETE (all 6 slices landed; `--check` → `CHECK-OK` JVM+Script at tip `b6596ef`). This file is the successor: what is left, ordered by dependency, split between (A) work that needs NO decision and (B) rule-6 items that need a maintainer vote first.
**Scope law:** the product stays 100% Kof (`D-KOFSHARE-100KOF`) — no interop, no shims, no invented stdlib face without rule-6. Every claim below was measured at this tip (03/10), not remembered.

## 0. Measured state of the edges this plan touches

* `crypto` today: `sha256`/`sha256Bytes`, HMAC, `keyExchange` (X25519, D-KOF-X25519). **`grep -rli ed25519` across `kof-compiler/src/main/java` = ZERO** — there is no signing face at all (B1 is genuinely missing, not hidden).
* `InterpretedCallable` exposes only `invoke()` and `invoke(String×5)` (HTTP routes). The runtime also reflects `invoke(SseConnection)` (SSE) and WS message handlers — the Script bridge for those is NOT done (A2; §574's fix scope note says the same).
* Persistence faces exist and are measured: `File.readText()`/`File.writeText(s)` instance forms (D-FILE-STATIC keeps static arms unwired). `json.encode(record)`/`json.decode<T>` work on packaged records (§573 fixed; `--check` registry leg uses them).
* ~~The CLI has no mid-transfer resume NEGOTIATION~~ — RESOLVED by A3 03/10: the `.part` size now crosses in-band as a HELLO head and the server verifies it (`RESUME-ERR` refusals); `OfferInfo` intentionally keeps no session field.

## 1. Track A — decision-free (Kof faces already exist)

**Slice A1 — registry persistence (crash-doesn't-forget).**
`control/registry.kf` gains `saveRegistry(path)` / `loadRegistry(path)`: `json.encode` of the devices+offers maps (sorted keys keep goldens stable), atomic-ish write via temp file + rename using only measured `file`/`path` faces; corrupt file → named `REG009` refusal, never silent empty. `server.kf` and `cli.kf server` load at boot and save after every successful mutation. Proof: golden `checkpersist.kf` (JVM+Script): register 2 devices + 2 offers → save → fresh load → byte-identical listings + `RESOLVE-SAME` assertions; tamper the file by 1 byte → `REG009`. DoD: `--check` extended with a persistence leg (`persist=true`). **LANDED 03/10:** `persistcheck/checkpersist.kf` → `PERSIST-OK` 9/9 on JVM AND Script (save/reload byte-identical listings, `REG009` on corrupt, empty on missing); server + `cli server` load at boot and save after every successful mutation (`SERVER-READY … devices=N`); restart probe measured: fresh process serves the 2 devices from disk. The `--check` leg is the remaining DoD half (tracked below).

**Slice A2 — Script SSE/WS bridge (§574 residual). **LANDED 03/10** (Kof4j `ScriptSseWsE2ETest` 1/1; product gains target parity — interpreted handlers now receive SSE connections; no product code required).
Kof4j-side (compiler lane): `InterpretedCallable` gains the handler shapes the runtime reflects for SSE (`invoke(SseConnection)`) and WS messages, delegating to `invokeLambda` exactly like the HTTP arms; interpreted handlers receive the connection object the same way compiled ones do. Proof: RED-first sibling of `ScriptWebRouteE2ETest` (SSE send-through + WS echo over loopback under `--target script`). DoD: §574's "SSE/WS not covered" scope note retired; no KofShare code required (the product gains the capability by target parity). **Boundary:** if WS handshake under interpretation hits a deeper interpreter gap, record the refusal by name (R6) instead of forcing — the HTTP/SSE split is one committable unit.

**Slice A3 — honest resume negotiation.** LANDED 03/10 (in-band HELLO head `helloIndex` announces the receiver's .part size; server-side `resumeVerify` checks it against the real file size; refusal travels as `resumeErrIndex` head and the client throws the name; plain + sealed; `resumecheck/checkresume.kf` → `RESUMECHECK-OK`; the out-of-band divergence note is retired — `OfferInfo` stays session-free).
Server (`serveFile` path) already answers a client-chosen offset; make it explicit: `fetch --resume` sends its local `.part` size in the HELLO/meta exchange and the SERVER verifies it (≤ size) and serves from it — a wrong offset refuses by name (`RESUME-ERR: server file shorter than requested offset`) instead of corrupting. `resumeOffsetHint` is NOT added to `OfferInfo` (the offer describes the file, not a session). Proof: golden — 5000 B file, `.part` of 2000 → `offset=5000/5000` + `cmp` clean (already measured, now asserted through the negotiation), plus the refusal case (hint > size). DoD: the plan-v1 "peer must cooperate out-of-band" divergence note is retired.

**Slice A5 — device-side `cli serve` (the missing operational leg).** LANDED 03/10. Measured gap: `fetch <host> <port>` exists and e2e.kf proves the state machine inside ONE process (spawned thread), but nothing in the CLI actually SERVES a file to a fetcher — real transfers between two processes were only exercised through the relay path with test-local servers. DoD: `cli serve <path> <port> [--resume <n>] [--key <hex>] [--secure] [--salt <hex>] [--once]` (single-session semantics honest in help), plus a two-process JVM golden `servecheck/checkserve.kf` that (1) detaches a serve process, waits on its `SERVE-LISTENING` line, (2) plain fetch with resume from a `.part` across the process boundary (A3 HELLO negotiation proven between REAL processes), (3) secure fetch (handshake + sealed) cross-process, (4) oversize resume refused by name across processes, byte-identity asserted; `--check` keeps its in-process legs (spawn threads; Script can't fork a JVM — recorded, the golden carries the multi-process proof).

**Slice A4 — offer expiry + registry hygiene (cheap, pure).** LANDED 03/10. Deviation recorded honestly: the plan said `OfferInfo` unchanged — impossible for time-based expiry (no stamp existed), so `OfferInfo` gained `createdAt` and the CLIENT wire type became a separate `OfferRequest(id,deviceId,path,size,sha256Hex)` (the server stamps freshness itself; a client cannot fake it or resurrect an expired id). `REG010: offer has no registration timestamp` refuses unstamped offers. `controlPurgeExpired(offers, devices, now, ttl)` (pure, sorted-keys stable) drops offers older than `offerTtlMs()` (24 h) AND dangling-by-device; the server calls it at boot (persisted purge + log line, never silent) and the control plane serves only live rows. Proofs: `REGCHECK-OK` gained `offerNoStamp/purged/purgeKeepsFresh` lines JVM+Script; `PERSIST-OK`, `HTTPCHECK-OK` 28/28, `RESTART-OK` all green on the new wire.
`OfferInfo` unchanged; registry gains a `purgeExpired(nowMs, ttlMs)` pure function + `/offers` listing already sorted; server calls it at boot and after mutations. Proof: pure golden lines in `check.kf` (JVM+Script). DoD: named `REG010` refusal only where needed (never silent behavior).

**Slice A6 — user-flow glue (`up`/`down`).** LANDED 04/10. Measured gap: every plane verb existed but no single command closed "I installed the client" → "I talk to the control plane" → "I received a link, I download": `offer` only printed local JSON, `fetch` needed a hand-passed host/port. `kofshare/userflow.kf`: `upPublish` (POST /devices + /offers over the A4 `OfferRequest` wire, bearer-gated, accepts the plane's `REGISTERED:`/`OFFERED:` grammar) and `downFetch` (GET /s/<token> → decode `ShareGrant` → dial the address THE GRANT CARRIES → A3 resume from any `.part` → verify sha256 the offer promised — `DOWN-ERR: content digest mismatch` by name, never silent). CLI verbs `up`/`down` thin over the module; `down --relay <rhost> <rport>` added same day (D4=A completion: `fetch` had the manual relay path, the recipient command must not lack it — `downFetch` 6-arg overload dials the relay instead of the grant address, A3/tags ride the byte pump; golden leg `serveUpRelay`+`downRelay` green). `share` already prints the full `SHARE-LINK http://host:port/s/<token>`. Proof: golden `usercheck/checkuser.kf` → `USERCHECK-OK` (addr matrix + plane boot + publish + mint + full `down` + `downResume` + `tamperRefuse`), REAL human loop measured end-to-end via the CLI binaries (up → SHARED/SHARE-LINK → serve → down → cmp identical). Found+fixed on the way: `cli server` printed `SERVER-READY` BEFORE binding (a lying READY let a zombie plane keep the port and the fresh bearer 401 against the stale secret — bind probe + `SERVER-ERR:` refusal now precede the marker); golden owns its port range deterministically via `ss -tlnp` kill-by-pid after `pkill -f` proved unreliable (self-matching wrappers); `transfer.kf` gained the explicit `import kofshare.session` its `tagBytes` use always needed (21/21→23/23 files check-clean standalone).

## 2. Track B — maintainer VOTED 03/10 (chat): D1=A · D2=A · D3=B · D4=A · D5=A · D6=A

**B1 → C1 — Device identity + offer signing (Ed25519). VOTED A — face approved.**
The trust hole of v1: anyone can register a device and claim any path. Landed stdlib has X25519 key exchange (`D-KOF-X25519`) but NO signing face (measured: zero Ed25519 anywhere). A 100%-Kof signature needs a new stdlib face (proposal: `crypto.sign`/`crypto.verify` over `Byte[]` + `KeyPair` handling on `Secret`, JVM first; JS/Native honest refusals per `SECN012` family). **Recorded:** the vote landed Kof4j `D-KOF-SIGN` (DECISIONS EN+PT) — proposed contract frozen for implementation: `sign(Secret, Byte[]) -> Byte[]`, `verify(Secret, Byte[], Byte[]) -> Bool`, pubkey raw-32-hex export, JS/Native named `SECN013`. Slice C1 lives in the Kof4j compiler lane (RED-first like every face).

**B2 — NAT traversal. VOTED A — relay stays manual `--relay` in v1; ICE-lite deferred.**
The relay covers "both peers reachable by the control host"; it does NOT cover two peers behind separate NATs with no inbound ports. Pure-hole-punching needs UDP rendezvous + timed simultaneous open + the relay as fallback-of-fallback — all `kof.net` UDP faces EXIST and are measured (slice 5 of the network plan). No stdlib decision needed to TRY a Kof-level ICE-lite, but the architecture calls hole-punching post-MVP (architecture §7), so it is listed here as the maintainer's call on scope, not on faces. **Decision asked:** schedule an ICE-lite slice (pure Kof, no new stdlib face) or keep traversal = relay-only.

**B3 — JS/Native product targets. VOTED A — recipient stays CLI in v1; browser deferred.**
`kof.net` on JS refused at compile (`NETN001`, `D-KOF-NET` amendment), `keyExchange` JS/Native refused (`SECN012`); both are honest, pinned refusals. The v1 product = JVM server + Script/JVM peers. **Decision asked:** none required to stay as-is; reopen only if the maintainer wants browser peers (needs both refusals fixed first) or a Native headless appliance.

## 3. Not in this plan (explicitly)

* GUI/desktop of any kind (out of the authorized scope).
* Multi-process persistence (single writer assumed; the file lock face exists but A1 stays lock-free by design: one server process owns the file).
* Upstream/CI packaging beyond `kof.toml` (slice 6 landed) — release protocol is repo-side (`D-RELEASE-CADENCE`).

## 4. Order and cadence

Landed: **A1 persistence** (`PERSIST-OK` ×2 + restart probe); **C1 Ed25519 face** in Kof4j (`D-KOF-SIGN` frozen contract: `crypto.sign/verify` over `Secret`+`Byte[]`, hex house format, SECN013 named gap, `CryptoSignE2ETest` 3/3); **C2 `share.kf` full model** (token = `security.randomHex(32)`, `expiresAt`/`maxUses`/`--once`/`readOnly`/revocation, `GET /s/<token>` gate via `shareTouch` — only `OK` serves metadata — REG030–REG041 refusals, A4 expiry folded via `sharesPurgeExpired`; goldens `SHARECHECK-OK` 22/22 JVM+Script + live `HTTPCHECK-OK` 21/21 + `RESTART-OK`; product hits + fixed the packaged-ctor bug §582; §583 was later FIXED compiler-side 03/10 (json.decode<T> was UNKNOWN to the SEM analyzer while the emit knew T — SEM012 skipped → VerifyError at dispatch; analyzer now mirrors the emit, `JsonDecodeLongAssignE2ETest` 3/3) — the typed-Long form stays as the correct code either way). Next, in order: **A2** SSE/WS bridge — LANDED 03/10 (`ScriptSseWsE2ETest` 1/1: interpreted `app.sse` streams over a real socket, interpreted `app.ws` handshakes 101 + echoes; §574 scope note retired) → **C3** bearer auth — LANDED 03/10 (vote D3=B; implemented on the runtime's native JWT layer: control secret minted by `security.apiKeyGenerate` + `auth.secret`, bearer = signed JWT with `{sub,name,roles}`, per-request gate `auth.authenticated()` then table check (AUTH001–AUTH006, AUTH043 corrupt-file refusal; tampered Authorization gets the runtime's measured 401 before the handler); open enrollment only on an empty table; goldens `HTTPCHECK-OK` 28/28 marker-gated + `RESTART-OK` 6/6 with revocation surviving restart) → **A3** resume negotiation. `--check` accumulates a leg per landed slice (now six: `registry persist plain secure share` all true). B2/B3 stay voted-A (manual relay, CLI recipient).
Compiler front closed 04/10: **§591** retired the cross-arch false-REDs (as+ld+qemu gate + `KOF_CROSS_PREFIX`-aware `has()`); Kof4j `lab` full suite measured 5180/2F/661S with the only 2F being `InteropTimeoutE2ETest` suite-load cancel races that are 0F solo (interop-front condition, not product). Product jar rebuilt from the final tip; every golden re-swept green incl. SERVECHECK-OK two-process and HTTPCHECK-OK+RESTART-OK on a fresh control-plane state.

## 5. PRODUCT EVOLUTION (v2 — maintainer prompt 05/10)

KofShare stops being a proof of planes and becomes THE PRODUCT: "um link, um
cliente, uma autorização, uma conexão direta". Baseline v1 is CONTRACT: the
existing goldens (USERCHECK/SERVECHECK/HTTPCHECK/RESTART/SHARE/RESUME/
PERSIST/RELAY + the eight CHECK legs) must stay green at every step; anything
that worked and stops working is a bug of the NEW implementation (R6 rule
extended to the v2 program).

Mandatory order (one track per slice: implement → test → golden → regression
→ document → commit; a compiler limitation STOPS the feature and opens an
explicit Kof4j task — no silent architectural workaround):

```text
1. Identity / device            LANDED 05/10 (v2-Track A, IDENTITYCHECK-OK)
2. Resource abstraction         (FileResource: id/name/size/hash/type — never
                                 a remote path on the wire)
3. Directories                  (logical tree, per-file integrity + collection
                                 digest; packing may be internal, NEVER the
                                 protocol contract)
4. Session / signaling          (CREATED→OFFERED→CLAIMED→NEGOTIATING→
                                 CONNECTED→TRANSFERRING→COMPLETED/FAILED/
                                 CANCELLED/EXPIRED; invalid transition = named
                                 refusal; the plane NEVER carries file bytes)
5. Automatic connectivity       (ConnectionStrategy DIRECT→NAT→TRAVERSAL→
                                 RELAY; relay stays ciphertext-only; the voted
                                 D4 manual --relay becomes the fallback leg,
                                 not the user path)
6. Browser recipient            (kofshare.app/s/<token> page drives the local
                                 client — REQUIRES the Kof4j primitives first:
                                 kof.net + keyExchange in JS; NETN001/SECN012
                                 are refused BY NAME today and must be closed
                                 IN THE LANGUAGE, never by external JS hacks)
7. UX / CLI simplification      (`share ./file --expires 24h --once` →
                                 SHARE-LINK; no ports/hosts/tokens for the
                                 human; old verbs become internal aliases —
                                 Track M: nothing removed without a documented
                                 migration + regression test)
8. Full integration             (two-real-process connectivity tests; all
                                 goldens; cold-start flakes documented)
9. Documentation                (README = the whole product story: honest
                                 limits — P2P ≠ availability when the owner is
                                 offline (DEVICE-OFFLINE), control plane is
                                 real infrastructure, relay traffic exists)
10. Release candidate           (final success criteria of the prompt)
```

Not-now, stated by the prompt: billing, desktop GUI, Android, central
storage. The architecture must not FORECLOSE them (Account/Organization/
Policy/Usage/RelayQuota/Audit stay addable without a protocol rewrite) — the
binding tables of v2-Track A are exactly that kind of seam.
### v2-Track A — device identity (LANDED 05/10, `IDENTITYCHECK-OK`)

One Ed25519 identity PER INSTALLATION, kept SEPARATE from the account bearer
(the prompt's law: "a conta autentica o usuário; a chave identifica o
dispositivo"). `kofshare/identity.kf`: boot (generate once, persist 184-hex
secret quasi-atomically, survive restart — same storage discipline as the
control key, ID005 by name on a corrupt file), deviceId DERIVED as
`d-<sha256(pub64)[0:16]>` (copying an identity between machines yields a
different id — duplication refused BY CONSTRUCTION; DEV005 still guards a
client that lies about its derived id), canonical version-pinned strings
(`v1|reg|…`, `v1|offer|…`) signed with the private half and verified with the
PUBLIC half alone (`crypto.verify(secrets.of(pub64),…)` — D-KOF-SIGN contract;
the secret never leaves the device). Control plane (`registry.kf` +
`app.kf`): binding table deviceId→{pub,status} persisted
(`server-registry.devkeys.json`, REG009 corrupt), NEW route POST
/devices/register (TOFU enrollment — first enrollment trusts the
self-signature, every later op verifies against the stored key), GET
/device-keys/:id (public read of pub+status), POST /devices/:id/revoke; the
offer gate runs BEFORE insertion (measured before landing: the naive order —
controlOffer inserts, then verify — half-inserted a refused offer) and is
CONTEXTUAL (Track I): enrolled devices must sign (DEV002 invalid/DEV004
missing/DEV003 revoked), keyless v1 devices pass UNTOUCHED (Track M: POST
/devices, hand-picked ids, offer bodies without the field — the v1 lanes are
green in the golden's legs legacyV1/RESTART-OK/HTTPCHECK-OK). Revocation
reaches the DATA path: GET /s/<token> refuses DEV003 by name (a consumed
authorization is dead, not just a missing future one). `downFetch` refusal
detection fixed on the way (checked only "REG" prefix; ANY non-`{` body is a
named refusal — a DEV003 would have decoded as garbage). userflow
`upPublishSigned` (derived id, signed enrollment, signed offer); CLI: `up`
without `--id` takes the identity lane (boot
`kofshare-device.ed25519`, prints the derived id), `--id` keeps the v1 lane;
new verb `device new|enroll|revoke|list`; `--check` grew leg 8 `identity=`
(pure matrix, green JVM AND Script — keyExchange/sign/verify work on the
interpreter; SECN012 remains a Native/JS gap only). Golden
`identitycheck/checkidentity.kf` — 14 prints incl. real second/third processes
(plane spawn, serve spawn, plane RESTART over persisted devkeys) and named
refusals AUTH001/DEV002/DEV003/DEV004/DEV005 at enrollment, offer, republish,
grant and restart-survival; it also CAUGHT a real product truth during RED:
offer ids are content-addressed (o-<digest[0:12]), so a second device
publishing the SAME bytes overwrites the first offer slot — v1 semantics,
documented in the golden, Track 2/3 (resource identity) owns revisiting it.
No-regression: HTTPCHECK-OK + RESTART-OK (full seed→restart→verify against
standalone server.kf with the 12-arg controlServe), USERCHECK-OK 13 legs,
SHARECHECK-OK, SERVECHECK-OK, RELAY-OK, RESUMECHECK-OK, PERSIST-OK, CHECK-OK
×8 legs JVM+Script, 25/25 files check-clean standalone.

