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
2. Resource abstraction         LANDED 05/10 (v2-Track F,
                                 RESOURCECHECK-OK; FileResource: id/name/size/hash/type — never
                                 a remote path on the wire)
3. Directories                  LANDED 05/10 (v2-Track G, FOLDERCHECK-OK;
                                 logical tree, per-file integrity + collection
                                 digest; NOTHING packed on the wire — the
                                 protocol contract stays one file per grant)
4. Session / signaling          LANDED 05/10 (v2-Track C, SESSIONCHECK-OK;
                                 actual states CREATED→CLAIMED→NEGOTIATING→
                                 CONNECTED→TRANSFERRING→COMPLETED/FAILED/
                                 CANCELLED/EXPIRED; invalid transition = named
                                 refusal; the plane NEVER carries file bytes)
5. Automatic connectivity       LANDED 05/10 (v2-Track D, CONNECTCHECK-OK;
                                 ConnectionStrategy DIRECT→NAT→TRAVERSAL→
                                 RELAY; relay stays ciphertext-only; the voted
                                 D4 manual --relay becomes the fallback leg,
                                 not the user path)
6. Browser recipient            LANDED 05/10 (v2-Track E, BROWSERCHECK-OK;
                                 the kofshare.app/s/<token> page drives the local
                                 client — REQUIRES the Kof4j primitives first:
                                 kof.net + keyExchange in JS; NETN001/SECN012
                                 are refused BY NAME today and must be closed
                                 IN THE LANGUAGE, never by external JS hacks)
7. UX / CLI simplification      LANDED 05/10 (v2-Track I, UXCHECK-OK;
                                 `share ./file --ttl 24h --once` → SHARE-LINK;
                                 no ports/hosts/tokens for the human; old verbs
                                 stay as internal aliases — nothing removed,
                                 `--raw` keeps machine output byte-compatible,
                                 named errors keep their code and gain a Hint)
8. Full integration             LANDED 05/10 (v2-Track H, INTEGRATIONCHECK-OK;
                                 22 legs with REAL processes: page→client→
                                 digest-verified bytes, dir story, NAT-analog
                                 relay, revocation, restart, account gate)
9. Documentation                LANDED 05/10 (Track J: README v2 = the whole
                                 product story, architecture v2,
                                 quick-start EN+PT, honest limits in
                                 architecture §10 + README Limits)
10. Release candidate           `rc/runrc.kf` (23 steps: standalone check
                                 sweep of the whole tree, CHECK/E2E on JVM
                                 AND Script, every golden including the
                                 browser/UX/integration process suites) →
                                 RC-CHECK-OK
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
### v2-Track C — session & signaling (LANDED 05/10, `SESSIONCHECK-OK`)

The control plane learns COORDINATION without ever carrying bytes. Pure
domain `control/session.kf`: TransferSession{id, shareId, token,
ownerDeviceId, offerId, recipientDevice, recipientAddr, ownerAddr, state,
createdAt, expiresAt, transport}; lifecycle CREATED→CLAIMED→NEGOTIATING→
CONNECTED→TRANSFERRING→COMPLETED with FAILED/CANCELLED per edge and EXPIRED
by clock — ONE legal-matrix function shared by routes and golden; invalid
transition = SES002 by name, unknown SES001, clock-stamp SES003 on touch
(same discipline as shares), bad-token SES004, empty-recipient SES006,
one-ACTIVE-session-per-share SES005 (terminal frees the slot), corrupt file
SES041. Routes (`app.kf`, 14-arg controlServe): POST /sessions (bearer —
recipient announces itself with the share token), GET /sessions?device=&state=
(owner DISCOVERS via pull — honest v1 signaling: the runtime web face has no
server-push yet, documented not hidden), GET /sessions/:id (token holder OR
bearer — recipient reads its own session without an account),
POST /sessions/:id/claim (owner-only; CLAIMED refuses through generic
advance — measured pre-landing: the first guard `!holdsToken` let the
recipient SELF-CLAIM whenever its POST also carried an account, exactly the
authorization confusion the prompt forbids), POST /sessions/:id/advance
(token-only face for the recipient steps). ownerAddr is STAMPED from the
REGISTRY at claim (the plane is the address authority — C2 law; a body cannot
move the rendezvous). Persistence: server-registry.sessions.json (quasi-atomic,
purge-at-boot keeps TERMINAL sessions until their own TTL — measured: the
first purge dropped terminal entries immediately and the restart-survival leg
correctly refused it). CHECK leg 9 `session=` (pure ladder + all refusals,
green JVM AND Script). Golden `sessioncheck/checksession.kf` (ports
19380-19382, REAL serving process + REAL plane + restart): door refusals
(AUTH001/SES004/SES006), ladder over the wire incl. stamped ownerAddr
verified in the JSON, transport field (direct) recorded at CONNECTED,
DATA moves while state==TRANSFERRING (downFetch bytes identical), COMPLETED
then terminal rules, CANCELLED path, session table reload after plane RESTART.
Three golden bugs caught BY THE RED (each fixed with a named condition, not
a sleep): claimPath false (JSON keys asserted with invented names — the
discriminator is `state`, the id field `id`); restartSurvives false (purge
window, above); and the usercheck RELAY hang (three reproductions + thread
dumps: the Kof spawn THREAD starts ~200ms after the statement — the client
dialed the relay listener before relayServeOn had accepted/dialed, contended
JVMs crossed a half-set-up pump; fix = flag-file FIRST statement in the spawn,
client dials only after seeing it — the language has no connect-with-timeout
and I did not invent one; also servecheck's spawnServe trusted a STALE log
marker — delete-then-sync + bindable-port proof before every spawn, and
usercheck got servePortClear before all four serve legs). No-regression:
USERCHECK-OK (15 prints), IDENTITYCHECK-OK, SHARECHECK-OK, SERVECHECK-OK,
RESUMECHECK-OK, PERSIST-OK, RELAY-OK, HTTPCHECK-OK + RESTART-OK (full
standalone-server cycle with the 14-arg controlServe), CHECK-OK 9 legs ×
JVM+Script, 27/27 files check-clean standalone.

### v2-Track D — automatic connectivity & presence (LANDED 05/10, `CONNECTCHECK-OK`)

Prompt items 2 (resource abstraction) and 3 (directories) remain OPEN and
are scheduled as Tracks F/G before integration — the lettering of this repo
tracks C/D landed session/connectivity first because the human loop (up/
down/serve) was already shipping v1 bytes without them.

Pure strategy `connect.kf`: `classifyConnect` (case-insensitive, captures
both "Conexão recusada" and "Connection refused"; timed/tempo → "timeout";
anything else "other"), `negotiatePath(attempts)` — the first "ok" wins, no
ok → `CONNECTIVITY_FAILED` —, `pickAndDial(host, port, relayHost, relayPort)`
with DIRECT tried first and RELAY as the voted-D4 fallback. The
"nat-traversal" label is RESERVED in the strategy vocabulary and the runner
NEVER fakes it: `kof.net` is TCP/UDP sockets only — no STUN/ICE exists in
the language — so NAT legs surface as dead/timeout and route to relay or to
the named refusal, documented not hidden. `pumpOn` reuses `fetchFile` — a
transport choice never forks transfer logic (same resume + digest path over
direct AND relay, measured). The environment has no real NAT: the golden's
"dead grant address" is the documented stand-in for one — the claim is about
the DECISION, not about emulating networks.

Presence `control/presence.kf` is an ORTHOGONAL table (v1 `DeviceInfo` wire
does not grow): `PresenceInfo{deviceId,status,lastSeen}`; POST
`/devices/:id/heartbeat` (bearer) + GET `/presence/:id`; TTL 120 s;
`presenceGate` on GET /s refuses ONLY explicit OFFLINE with the NAMED
operational refusal `DEV-OFFLINE: … (share still valid)` — an un-beat legacy
(v1 keyless) device is NOT blocked (Track M: operational state never became
an authorization wall silently; measured GREEN: unknownNotBlocked). Boot
marks EVERY loaded device OFFLINE and DEMOTES persisted ONLINE entries
(measured RED twice: the first version only added missing entries, so a
restarted plane still claimed to have seen everyone — presence is operational
truth and a restarted plane has none). UP-OK now carries `presence=ok` /
`presence=skipped(…)`, never silent.

`downAuto(controlBase, token, dest, key, sessionAuth, recipientDevice,
relayHost, relayPort)` = the whole Track C lifecycle driven over the wire
WITH the role matrix (claim through `/claim`, never through advance — the
Track C guard refuses that and the golden proved it): grant→verify→session
CREATED→CLAIMED→NEGOTIATING→`pickAndDial`→CONNECTED with `transport`
stamped by the REAL choice→TRANSFERRING→pump→COMPLETED; message
`DOWN-AUTO-OK transport=… sid=… offset=… digest verified`. The session stays
BYPASSABLE (v1 downFetch untouched — data never rides on a coordination
layer's availability).

Golden `connectcheck/checkconnect.kf` (ports 19390-19394, three real JVMs
+ restart): pureMatrix (negotiatePath ladder + refusal classes IN-PROCESS,
labelled as such), beatPresence (signed up beats → GET /presence ONLINE),
autoDirect (session COMPLETED with transport "direct", bytes digest-
verified), autoRelay (second device publishes a DEAD grant address = the
NAT-analog; relay worker + flag-file sync; same bytes over transport
"relay", session stamped relay), allDeadNamed (`CONNECTIVITY_FAILED` by
name — no silent infinite retry), unknownNotBlocked (legacy v1 served),
offlineAfterRestart + grantRefusedOffline (`DEV-OFFLINE` refusal names it;
the share itself still mints and lists) + heartbeatRevives (beat → digest-
verified download). CHECK leg 10 `connect=` (pure ladder both JVM AND
Script). Four RED-side bugs caught by the harness, each fixed by a named
condition: presence boot-demote (above); restart PROBE never checked a
served grant (`grantAfterRestart` only asserted "no error prefix" — the
DEV-OFFLINE/REG035 body passed; now asserts the grant BODY, and the seed
gained a maxUses=0 share on a dedicated offer o2 — o1 is revoked by design;
firstToken now skips exhausted too; `offersGone` was global-state-coupled —
now o1-absent/o2-present); usercheck's spawnCli still trusted a STALE
SERVE-LISTENING log (same class fixed for servecheck/connectcheck in Track
C — the suite hung on the relay leg again; delete-then-sync everywhere
now); and the cli presence-wiring landed in `sessionLeg` through an
ambiguous one-shot replace anchor (ambiguous anchors are banned for
multi-occurrence edits — python-located now). No-regression (all on the
FINAL tree): IDENTITYCHECK-OK, SESSIONCHECK-OK, CONNECTCHECK-OK,
USERCHECK-OK (15 prints), SERVECHECK-OK, RESUMECHECK-OK, PERSIST-OK,
RELAY-OK, SHARECHECK-OK, HTTPCHECK-OK + RESTART-OK (standalone cycle,
18322), CHECK-OK 10 legs × JVM+Script, 30/30 files check-clean standalone
(new law: EVERY file must also check CLEAN STANDALONE — `presence.kf` had
been compiling only via the import graph; the same-package cross-file type
reference needed an explicit `import kofshare.control.registry`).

### v2-Track E — browser recipient (LANDED 05/10, `BROWSERCHECK-OK`)

The prompt's own architecture resolves the compiler question: the page DRIVES
THE LOCAL CLIENT, it is not itself a crypto endpoint. Maintainer option A
chosen 05/10 — the page is an HTML/JS asset served and driven by the `app`
client; `kof.net`/`keyExchange` are NOT needed in JS, and D-NET-JS-V1 (net is
refused on JS by the maintainer's own vote) STANDS UNTOUCHED. No external JS
hacks, no fighting the compiler: the browser speaks `fetch()` to localhost,
the JVM client does the Track D story with the primitives that LIVE there.

`app/page.kf` — `pageHtml()` builds the recipient page as a List<String> join
(no `String.join` in the language, measured); contract asserted PURE: carries
`/api/info` + `/jobs`, never the words `Bearer`/`server-control`. `baseName`
is the ONLY path exposure (basename of the grant path — never `/srv/...`).

`app/client.kf` — local client (web.app, JVM-only surface): `GET /` serves
the page (dynamic route BEFORE serveDir fallback — documented runtime order),
`GET /api/info?token=` resolves the grant ANONYMOUSLY through the control
plane and answers METADATA ONLY (name/size/sha; refusal → `GrantView.error`
carries the NAMED refusal head, `errName` cuts multi-line throw text at the
first line — the browser never sees a stack), `POST /jobs` starts the REAL
`downAuto` in a `spawn` thread (hand-off by FILES — the measured ~200ms
spawn-thread start law), `GET /jobs` exposes state for the page's poll.
Credentials never cross to the browser: the bearer lives in the client
(`AppConfig` scratch file), `/api/*` responses were ASSERTED free of it
(`secretAbsent`). Every request is UA-ATTRIBUTED to `app-view.log`
("PAGE-VIEW …"/"API /api/info …") — that attribution is what lets the golden
distinguish a REAL browser from harness calls. Honest limitation recorded:
`app.listen` binds 0.0.0.0 (runtime contract, stdlib-web docs) — the LAN
surface is documented here and queued for the hardening track, not hidden.

Golden `browsercheck/checkbrowser.kf` (ports 19400-19402, plane + serve + app
as three real JVMs + REAL headless Firefox with a FRESH isolated profile at
/tmp/bc-ffprof, `--delay 5000 --screenshot`): `browserFound` REFUSES the
golden by name if no Firefox exists (no fake browser story); `apiInfo`,
`secretAbsent`, `ghostNamed` (REG035/DOWN-ERR inside the JSON — client
survives); `jobDone` + `fileDownloaded` (COMPLETED message contains
DOWN-AUTO-OK transport=direct, bytes digest-verified — Track D story through
the Track E face); `browserViewed` — the page's OWN fetch reached the API and
the log line carries a FIREFOX UA (a Kof http.get can never forge it);
`screenshotReal` — PNG >1500 bytes, POLLed (the flush happens at browser
EXIT, after the log proof — third application of the delete-then-sync law).
CHECK leg 11 `app=` pure green JVM AND Script (Script proved to compile the
`kof.web` import graph — measured, the verb lives in the CLI after all).
RED-caught bugs: `cliRunApp` bound the PLANE port because `tail(args, start)`
KEEPS the verb token (every run* strips it internally — my parse didn't;
measured by standalone probe, not guessed); screenshot race (above); zombie
firefox profiles (fresh profile per run). No-regression on the final tree:
BROWSERCHECK-OK, USERCHECK-OK, CONNECTCHECK-OK, IDENTITYCHECK-OK,
SESSIONCHECK-OK, SERVECHECK-OK, RESUMECHECK-OK, PERSIST-OK, RELAY-OK,
SHARECHECK-OK, HTTPCHECK-OK + RESTART-OK (unchanged paths, standalone sweep),
CHECK-OK 11 legs × JVM+Script, 33/33 files check-clean standalone.
### v2-Track F — resource abstraction (LANDED 05/10, `RESOURCECHECK-OK`)

The domain stops identifying files by location or by content. `resource.kf`
(pure): `Resource{id,name,type,size,modifiedAt,hash,metadata}` (type FILE now,
DIRECTORY reserved for Track G — no packing, no OOP ceremony: a record +
functions is what Kof wants), `resourceIdFor(deviceId,name,size,contentHash)`
= `r-<sha256("v1|res|…")[0:16]>` — device-scoped, NEVER a path, NEVER the
content hash itself: identity and integrity are separate attributes (§5).
The OFFER slot `offerIdFor(deviceId,resourceId)` closes, by construction, the
collision the Track A and Track D goldens each MEASURED as a product truth
(two devices publishing the same bytes overwrote one another's slot).

The plane RECOMPUTES (`controlOffer`): a proposed id that is path-shaped →
`REG013`; one that disagrees with the derivation → `REG014`; legacy v1 offers
(no id fields) still work and get the derivation STAMPED into the stored
record (additive §11 — the wire grew fields and dropped none;
`OfferRequest`/`OfferInfo`/`ShareGrant` decode v1 bodies to ""/0 defaults —
the measured json law). The session (`SessionInfo`) carries `resourceId`
stamped at creation via token→share→offer — the STATE MACHINE is untouched
(§8: gradual, no aesthetic changes). `serve --resource r-… <port>` resolves
the LOCAL binding table `kofshare-resources.json` (written by the signed `up`
lane); an unbound id refuses `SERVE-ERR: no local binding` — the peer
authorizes IDs, never paths (§6/§7); traversal is UNEXPRESSIBLE in the id
charset rather than "filtered".

Golden `resourcecheck/checkresource.kf` (ports 19410-19412, two REAL
identities, REAL serve processes, relay worker, plane restart —
`RESOURCECHECK-OK` 15/15): sameContentDiffIds (THE collision, dead),
wireNoPaths (offer/grant JSON carries the BASENAME; no /home, no /srv),
foreignResourceRefused REG014 over the wire, pathLikeIdRefused REG013,
grantCarriesResource, bindingServe + resourceTransfer (digest-verified),
resumeOverResource (dest pre-head = offset law), unknownBindingRefused,
relayOverResource, restartKeepsResources (both slots + ids reload; local
bindings survive). CHECK leg 12 `resource=` pure green JVM AND Script.

RED-caught bugs, each fixed at the root: `bindingPut` assumed `moveTo`
REPLACES — it does not (the same measured law `controlSaveList` documents);
the resource-refusal leg probe first forgot that the device gate runs BEFORE
the resource checks (refusal ORDER is a contract — the leg now registers
devices first); `serve --resource` positional drift (rid get(1), port get(2),
flags from 3 — measured by standalone probe, never guessed).

FALSE GAP CAUGHT BY RE-MEASUREMENT (evidence-before-inference law, same
discipline as Track A's DEV005): I first recorded `json.decode<List<Record>>`
as inexpressible; a standalone probe REFUTED it — generic container decode
WORKS (the registry has persisted `List<DeviceInfo>` through exactly this form
since A1). No compiler task was opened; Track G starts unblocked. The lesson
is written into the code, not hidden: a gap claim is a BUG CLAIM and gets the
same reproduction duty.

No-regression on the final tree: RESOURCECHECK-OK, USERCHECK-OK,
IDENTITYCHECK-OK, SESSIONCHECK-OK, CONNECTCHECK-OK, BROWSERCHECK-OK,
SERVECHECK-OK, RESUMECHECK-OK, PERSIST-OK, RELAY-OK, SHARECHECK-OK,
HTTPCHECK-OK + RESTART-OK (standalone cycle on 18322 with the grown records),
CHECK-OK 12 legs × JVM+Script, 35/35 files check-clean standalone.

### v2-Track G — directories as logical collections (LANDED 05/10, `FOLDERCHECK-OK`)

The vote (D6=A, reopened by the v2 prompt) required directories to be
COLLECTIONS of Resources — never tarballs, never a bespoke packing protocol.
This is what landed:

- `directory.kf` is the domain: `DirEntry{resourceId,logicalPath,type,size,
  hash,modifiedAt}`; the manifest record is named `DirTree` (the bare name
  `Directory` belongs to the filesystem primitive — shadowing it broke the
  app client, measured). Children keep their real Track F resource ids.
- THE ORDER LAW: `sortEntries` puts the ROOT self-row first, then strict
  lexicographic by logicalPath. A raw lex sort placed the root AFTER
  "root/a.txt" because `'/'` is ordinal 47 — an index contract must not be an
  accident of ASCII separator order (RED-caught; golden asserts root-first).
- THE DIGEST LAW: `directoryDigest = sha256("v1|dir|<root>|<child rows>")`
  covers CHILDREN ONLY. The root row's id derives from the digest; including
  it would be circular. The root stays in the manifest for tree shape, it
  simply does not hash itself.
- THE PLANE GATES BEFORE INSERTION: `REG015` (entry id not resource-shaped,
  traversal/empty/`.`/`..` segments, `\` or `:` in a segment, unknown type,
  duplicate logical path), `REG016` (recomputed digest mismatch — the plane
  hashes the manifest itself; size ≠ entry count). Signatures verify first
  (Track A ordering), so forged manifests die before parsing accidents.
- THE CAPABILITY MODEL: one share token for the tree. `/s/<token>` (no
  selector) = the DIRECTORY grant (manifest on the wire, per-child ids +
  logical paths + BASENAMES — the creator's layout never crosses);
  `/s/<token>?child=N` = a FILE grant for the N-th FILE row of the sorted
  manifest. Directories carry no bytes and are not selectable. `shareTouch`
  runs BEFORE any resolution: maxUses stays honest across selectors (proven:
  a `--once` directory share dies `REG038` on the second resolution of any
  shape). Revocation kills every shape (`DEV003`), presence gate included.
- THE DEVICE FACE (`serve-dir`): each connection carries `[offset]` + HELLO
  type `dirHelloBase()+child` — ADDITIVE wire (1073700000+child sits strictly
  below every v1 sentinel; plain `helloIndex` keeps the single-file meaning
  untouched). The face rescans the folder, sorts with the same law, serves
  the sel-th FILE through the SAME `sendChunks` core as v1 — per-file resume,
  per-file tags, one accept per child, refusals by name.
- THE RECIPIENT (`downdir` / CLI `updir`/`downdir`/`serve-dir`): one dial per
  child, destination = recipient's chosen root + the LOGICAL path, digest per
  child (mid-child resume: a half file's size IS the announced offset — the
  A3 law per child); `dirJoinSafe` re-gates traversal on the recipient side
  (the plane is authorization, the client is a second pair of eyes).
- KNOWN LIMITS, HONEST: relay and sealed sessions for directory trees are
  NOT in this lane (v1 dir face is the plain transport; single files keep
  relay/secure — extending both is Track H integration work); empty-folder
  publishing is refused by name.

Golden `foldercheck/checkfolder.kf` — `FOLDERCHECK-OK` twice in a row, 13
legs, real processes (ports 19420-19422): real tree walk + digest identity,
signed directory publish, parent/child grant shapes, `wireNoPaths`, full
transfer with nesting preserved under the recipient's root, per-child resume,
`dirJoinSafe` refusal, plane refusal of tampered (`REG016`) and traversal
(`REG015`) manifests, honest `REG038` uses, plane restart with the manifest
reloaded byte-identical (presence earned again by heartbeat — the Track D law),
revocation killing parent AND child resolutions.

RED caught four real bugs: rootless logical paths in `dirWalk`; the `'/'`
sort accident; a HELLO parsed twice by the face (every first child died
`RESUME-ERR` until the stream shared `sendChunks`); and a golden that minted
its own `d-0123456789abcdef` while the publisher used the real identity —
digests differed only in the child id field. The golden now shares the one
identity AND cleans the plane state (server-registry/devkeys/bearer) before
running — cross-run pollution (a revoked key persisting into the next golden)
is contamination, not flakiness.

A KOF4J BUG was caught and routed around legitimately: a `T?`-typed
PARAMETER threaded through branches crashes the JVM backend
(`COMP002` / ASM `COMPUTE_FRAMES`, `ArrayIndexOutOfBoundsException: Index -1`)
— reproduced minimally, IR captured, to be filed upstream. The product shape
COALESCES the nullable query at the caller into a plain `String` (the same
narrowing discipline `json.decode` rebinds already use). The language itself
is unchanged; no feature was faked.

No-regression on the final tree: FOLDERCHECK-OK (×2), RESOURCECHECK-OK,
USERCHECK-OK, IDENTITYCHECK-OK, SESSIONCHECK-OK, CONNECTCHECK-OK,
BROWSERCHECK-OK, SERVECHECK-OK, RESUMECHECK-OK, PERSIST-OK, RELAY-OK,
SHARECHECK-OK, HTTPCHECK-OK + RESTART-OK (external server on 18322 — noted
law: those two tests need the operator-run process; sweeps must kill only
MY ports), CHECK-OK 13 legs × JVM+Script, 36/36 files check-clean standalone.

### v2-Track I — UX simplification (LANDED 05/10, `UXCHECK-OK`)

The product voice. `share <path>` (file OR directory) does identity, offer,
link and the active serving helper in ONE command with zero ceremony — no
ports, no tokens, no bearer for the human; `receive <link>` drives the whole
Track D story (`--auto` semantics by default), writes to `./received` unless
told otherwise, refuses spent/dead links with human sentences; `stop` kills
exactly the helpers this device started (pidfiles + ss-sweep by port);
`server --start` detaches and waits on observable readiness (`/health`
probe, not sleep). The named-error law stands: codes NEVER disappear —
`errText` layers a `Hint:` sentence on top (REG010 "link spent", DEV-OFFLINE
"sender offline", CONNECTIVITY_FAILED "nothing reachable"). `--raw` keeps
the machine lines (`UP-OK`, `SHARED`, `SHARE-LINK`) byte-identical for
scripts — the compatibility lane is a TEST, not a promise. Golden 15 legs
(ports 19430-19432, two processes, dead plane, `--once` spent across a
restart, per-child directory resume, zero stack traces reaching a terminal).
CHECK leg 14 `ux=` green JVM+Script. RED caught: double-consume on `--once`
(the link burned twice — once by preflight, once by the download; fixed by
`downAutoWithGrant` resolving the grant EXACTLY once), the face replacement
that orphaned a serving process, and the CLI dispatcher that handed the verb
token to sub-parsers.

### v2-Track H — full integration (LANDED 05/10, `INTEGRATIONCHECK-OK`)

The whole story with REAL processes (ports 19440-19446): a file travels
browser-page → local client → direct dial → digest-verified bytes; the
directory story end-to-end; the WIRE carries zero layout (the plane never
sees a path — `wireNoLayout`); relay as the DOCUMENTED NAT analog (dead
direct grant + relay worker → session `transport=relay`, honest stamp);
expired link; single-use across a plane RESTART; revoked share AND revoked
device kill live grants; the account gate refuses anonymous mutation; the
browser lane receives metadata only (no keys, no bearer, no paths).
22 legs ×2 consecutive runs; 39/39 files check-clean. Boundary stated in
the golden header: sealed-envelope directory trees and real hole-punching
are OUT (deferred/reserved), everything asserted is what the code actually
did.

### v2-Track J — documentation (LANDED 05/10)

README v2 rewritten as the product story (quick start in five lines, CLI
table with audiences, five concepts, security model per property, honest
Limits section, test markers). `docs/architecture.md` rewritten to the v2
reality (planes, domain, transfer protocol, directories, connectivity,
UX law, module layout, test-plan status table, §10 known gaps).
`docs/quick-start.md` + `.pt_BR.md` added: first share/first receive/end of
day/how to read errors/troubleshooting.

### v2-RC — release candidate gate (MEDIDO 05/10, `RC-CHECK-OK steps=23`)

`src/main/kof/kofshare/rc/runrc.kf` runs the ENTIRE gate in one command:
the whole-tree standalone `check` sweep (40/40 files, zero errors),
`--check` + E2E on BOTH targets, control plane goldens, the HTTPCYCLE step
(the documented recipe pairing: fresh state → external plane on 18322 →
`HTTPCHECK-OK` → kill → REBOOT → `RESTART-OK`), data-plane goldens, all
v2 track goldens, and the browser/UX/integration process suites. Measured
green end-to-end 05/10 (`RC-CHECK-OK steps=23`). Two harness bugs caught
by the first red run: script-target steps were asserting a marker the
command never prints (fixed with an explicit echo gate), and running the
battery while manually probing goldens collided on the shared plane port —
the law recorded: never parallelize a second compile/serve session with the
RC battery. The battery is the release instrument: any future tip that
prints `RC-CHECK-OK` is RC by definition; anything that doesn't is not.
