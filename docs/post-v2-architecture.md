# KofShare — post-v2 architecture (DECIDED)

status: DECISION RECORD. v2 is RELEASE (cut 06/10). This document decides
the shape of what comes after, from the code and proofs that already exist.
supersedes: the 06/10 DRAFT of this file (whose D7–D10 were poll questions);
the maintainer's post-v2 directive re-specified them as decisions — this is
that record. Sub-questions of the draft (GUI toolkit, core-extraction
timing, telemetry floor) are absorbed into D8/D9/D7 respectively.
date: 06/10 (decided) . Owner lane: security/connectors `192.150.15.15:9092`.
PT-BR: [post-v2-architecture.pt_BR.md](post-v2-architecture.pt_BR.md)

Category discipline used throughout — nothing else is allowed:

```text
DECIDIDO/DECIDED   recorded with a status below; may be relied upon
PROPOSTO/PROPOSED  described, NOT a contract until it gets a status
RESERVADO/RESERVED a slot in the architecture, deliberately empty
ADIADO/DEFERRED    a real question with a recorded decision procedure
FORA DE ESCOPO     cannot enter the architecture without a scope change
```

## 1. Contexto pós-v2 / Post-v2 context

KofShare v2 shipped: file sharing, directory sharing (logical collections),
resource abstraction (device-scoped logical ids), Ed25519 device identity,
bearer/JWT account auth, share tokens with expiry/maxUses/readOnly/
revocation, plane persistence with corrupt-refusal, offset-idempotent
resume, session lifecycle (claim/advance) coordinated by the plane,
presence heartbeat, honest connectivity strategy (DIRECT→RELAY, NAT
reserved), ciphertext-only relay, browser recipient through the localhost
local client, simplified UX (`share`/`receive`/`stop`, Hint+code errors,
`--raw` lane) and end-to-end integration in real processes.

Release facts (do not re-litigate here):

```text
KofShare v2 = RELEASE        tag v2.0.0
compiler_pin = Kof4j f2629e32d
jar_sha256   = 0b1893b4e4de365cacd3d4cdfcdd2bcd066fcd9f8ca2352910077a07107effe0
RC-CHECK-OK steps=23         (release proof; battery = rc/runrc.kf)
40/40 files check-clean standalone
compiler_upstream_pending = NONE
candidate 20a3207e1: measured, NOT repinned (3 battery load-races on
different steps; all green in isolation on the same jar). Law: a new HEAD
is not automatically better than the verified jar.
```

The question this document answers is NOT "what feature next" but: **"what
is the definitive shape of KofShare now that the protocol and the base
product are proven?"** No code is written by this decision. No track is
created. The RC battery stays the release proof.

## 2. Estado atual / Current state (ground truth, file by file)

```text
control plane   server/server.kf + control/{app,registry,share,auth}.kf
  one process, one host; state = in-memory maps + save-on-mutation JSON
  (the ONLY seam: controlSaveList / controlLoadList in registry.kf);
  identity (devkeys), accounts (bearer), offers, shares, sessions,
  presence, grants. Carries ZERO file bytes — proven (SESSIONCHECK,
  INTEGRATIONCHECK wireNoLayout).
data plane      transfer.kf + session.kf + protocol.kf + relay.kf + connect.kf
  device↔device chunk stream; per-file digest verify; resume
  offset-idempotent; transport stamped by the dial that actually happened.
device/library  identity.kf resource.kf directory.kf userflow.kf
  userflow.kf is the orchestration library the CLI drives — the core's
  embryo already exists as a file boundary, not as a fiction.
surfaces        cli/cli.kf (user verbs + operator verbs + CHECK)
                app/client.kf (browser lane's localhost client: /api/info,
                jobs; metadata-only to the page — proven browserSecrets)
```

## 3. D7 — the definitive role of the CONTROL PLANE

```text
Decision:   the post-v2 topology is central control plane + decentralized
            data plane, with NO central content storage, ever.
Status:     ACCEPTED
Chosen:     D7-A (central control plane / decentralized data) — and it is a
            description of what v2 ALREADY does, now recorded as the
            definitive shape rather than an MVP accident.
Why:        every v2 proof depends on it: the plane never sees bytes
            (wireNoLayout), the relay never parses (RELAY tamper), the
            content lives only on owner disks (digest-verified transfers).
            Changing it would not evolve the product — it would replace it.
Rejected:   central storage as a product mode (see D7-C); "the GUI/browser
            talks protocol directly" (see D8/D9).
Current impact: none — this is a ratification, not a change.
Future impact:  replication (D7-B) stays RESERVED; the ratification tells
            the replication designer WHICH invariants must survive it.
Compatibility: v1/v2 wire untouched. Security: unchanged, now contractual.
```

### D7-B — multi control plane: evaluated, not adopted (RESERVED)

Honest inventory (read from the code, not projected):

| Question | Answer today |
|---|---|
| what is local state? | the in-memory maps in `server.kf` + `server-registry.*.json` files written by `controlSaveList` after every mutation |
| what is global identity? | `deviceId = d-<sha256(pub)[0:16]>` and `resourceId = r-…(device,name,size,digest)` — DERIVED, so they are portable across any number of planes by construction |
| what could replicate? | the registry payloads (devices/offers/shares/accounts/devkeys/sessions/presence) — they already exist as complete JSON documents with versioned field names |
| what is naturally stateless? | signature verification (public half only), grant signature validation, the whole data plane (the plane is not on the byte path) |
| where does the model assume single-node? | the control signing key (`server-control.ed25519` — one file per host), the bearer secret (`server-control.apikey`), the JSON file store (no atomicity across hosts), `shareTouch` counters (per-node local writes) |
| which contracts BLOCK future HA? | NONE on the wire — clients speak HTTP and never pin a plane generation; the blockers are deployment-only (shared store + key distribution), which is exactly why replication is a RESERVED slot and not a protocol debt |

Status: **RESERVED** — replication is possible without touching any frozen
contract; it gets scheduled when an actual second node is needed, not before.

### D7-C — central storage

```text
Decision:   the control plane may store ONLY: accounts, devices, shares,
            sessions, presence, resource METADATA, audit/telemetry metadata.
            It may never become file storage, backup storage or a content
            repository through any future feature drift.
Status:     ACCEPTED (as an architectural invariant, not a preference)
Rejected:   any proposal that makes the server hold content (including a
            relay that buffers to disk — that turns transport into storage
            through the back door).
Why:        content-decentralization is a PROPERTY the goldens measure
            (wireNoLayout, RELAY tamper, browserSecrets); making storage a
            mode would invalidate the release proofs, not merely add a flag.
Telemetry floor (absorbed from the draft): metadata already present (share
used-counts, session states, presence timestamps) is the floor. Structured
audit is addable ONLY in the same shape as registry records — metadata only.
```

## 4. D8 — the definitive CLIENT architecture

```text
Decision:   the next primary client is a DESKTOP GUI built on a shared
            kofshare-core; CLI and GUI are two presentation layers over one
            domain. Option C. The extraction of the core itself is
            DEFERRED to GUI scheduling time and must be a zero-behavior
            refactor proven by the full battery.
Status:     ACCEPTED (direction) / DEFERRED (the packaging move)
Chosen:     Option C — core + CLI-on-core + GUI-on-core.
Why:        only C keeps the law "the GUI is not a second implementation of
            the protocol" true BY CONSTRUCTION: one identity model, one
            resource model, one transfer engine, one security model; CLI
            automation and GUI UX and future clients (D8's "future clients"
            row) all drive the same code. Evidence it is not fiction:
            userflow.kf IS already the orchestration library — today's CLI
            delegates the flows; the extraction formalizes a boundary that
            already measures clean.
Rejected:   Option A (GUI wrapping the CLI process): stdout scraping cannot
            observe lifecycle (share progress, session states, named
            refusals as events) and would freeze CLI human output as an IPC
            contract — it poisons both surfaces.
            Option B (GUI on core, CLI left as-is): leaves the CLI holding
            orchestration the GUI would re-implement — a guaranteed drift
            between the two clients, the exact failure D9 exists to forbid.
Current impact: NONE. No core is extracted now. (The directive's own rule:
            decide the boundary first; don't build the abstraction without
            its consumer. The consumer — the GUI — is not scheduled yet.)
Future impact:  when (not if) the GUI is scheduled, the extraction unit is:
            kofshare-core = identity.kf + resource.kf + directory.kf +
            userflow.kf + connect.kf + transfer.kf + session.kf +
            protocol.kf + relay.kf + control clients; cli.kf becomes thin;
            GUI binds to the same entry points. Gate: RC-CHECK-OK on the
            extraction commit with zero src/ behavior diffs (the 03/10
            protocol/session split is the precedent and the method).
Compatibility: every CLI verb, flag, --raw line and named refusal is FROZEN
            across the extraction; the CLI stays the functional reference
            and CI keeps it green with zero GUI code.
Security:   the GUI may hold NO secret that is isolated today (matrix §7):
            control secret — never in any client; device private key —
            device store only; bearer — session store; browser — metadata.
```

The eight GUI pre-questions (scheduling gate, answered BEFORE any window
exists) are recorded in §9; answering them is the decision, not coding them.

## 5. D9 — the boundary between CORE, CONTROL PLANE, CLIENT, RELAY, BROWSER

```text
Decision:   this ownership table IS the architecture; any future change of
            ownership is a new decision requiring this document's update
            FIRST (no code-first migrations).
Status:     ACCEPTED
```

| Capability | Owner | Today's proof/file |
|---|---|---|
| Device identity (keypair, derivation) | CORE (device side) | identity.kf; IDENTITYCHECK |
| Device enrollment/revocation records | CONTROL PLANE | registry + devkeys; DEV001–005 |
| Share authorization (mint/touch/validate) | CONTROL PLANE | share.kf REG030–041; /s route |
| Resource resolution (id→path) | CORE, OWNER DEVICE ONLY | resource.kf binding table; RESOURCECHECK |
| Session state machine | CONTROL PLANE coordinates; CORE clients drive legs | session lifecycle; SESSIONCHECK |
| Connectivity strategy | CORE (on the dialing device) | connect.kf; CONNECTCHECK |
| Transfer engine (chunks/resume/digest) | CORE | transfer.kf; E2E, RESUMECHECK |
| Encryption (envelope) | CORE; plane holds only its own signing keys | session.kf; SEC-E2E, TAMPER |
| Relay transport | RELAY WORKER PROCESS — stateless, ciphertext-only | relay.kf; RELAY-OK |
| Account auth | CONTROL PLANE | auth.kf AUTH001–043 |
| CLI presentation | cli.kf (thin; orchestration already in userflow.kf) | UXCHECK; CHECK legs |
| Desktop presentation | DEFERRED GUI → CORE only (§8 rules) | — (not built) |
| Browser UI | PAGE + local client only (metadata-only API) | app/client.kf; BROWSERCHECK, browserSecrets |

The NEVER list (any architecture violating one of these is rejected on
sight, not reviewed):

```text
the browser owning keys or bearers          (browserSecrets proves the law)
the relay owning/buffering content          (RELAY is a pump; tamper proves it)
the GUI duplicating the protocol            (D8 option C exists to prevent it)
the control plane receiving file bytes      (wireNoLayout)
each new client re-implementing security    (one core = one model)
the CLI hoarding logic that belongs to core (known drift today: serveOne,
    startFaceHeartbeat, spawnDetached live in cli.kf; the extraction moves
    them — recorded so the refactor is a migration, not a discovery)
```

## 6. D10 — the future of the DATA PLANE

```text
Decision:   the strategy chain DIRECT → NAT/ICE → RELAY is the permanent
            shape. session.transport remains the abstract contract it is
            today: a string stamped by the dial that actually happened.
            Concrete values may only GROW additively; TransferSession is
            never rewritten.
Status:     ACCEPTED for the contract / RESERVED for NAT-ICE
Today:      DIRECT = REAL · RELAY = REAL · NAT/ICE = RESERVED (never faked;
            goldens use dead-port+relay as the documented NAT analog)
Future:     when Kof4j ships real STUN/ICE primitives (candidate gathering,
            connectivity checks), new stamped values — e.g. ICE-DIRECT,
            ICE-RELAY — are ADDITIVE enum values for the session row and
            for --raw consumers; the wire, the envelope and the state
            machine stay byte-identical. The reserved slot is connect.kf's
            strategy ladder, which was designed to be exactly this:
            classifyConnect → (DIRECT | [NAT] | RELAY | CONNECTIVITY_FAILED).
Rejected:   fake STUN/ICE, ICE guessed by heuristics, relay promotion to a
            content tier, "transport = direct" when relayed (honesty law —
            INTEGRATIONCHECK stamps the real dial).
Compatibility: values already printed by v2 keep their exact strings.
Security:   ciphertext-only relay holds under every future transport.
```

## 7. Security boundaries (inherited from v2, frozen for what comes)

```text
device private key → device identity → signed authorization → share
capability → session → data plane          (the whole chain, unchanged)

control secret ≠ device private key ≠ share token ≠ account bearer ≠ resource id
```

| Component | May know | Must NEVER know |
|---|---|---|
| control plane | tokens, ids, states, presence, metadata | file bytes, owner paths, device private keys |
| relay | nothing (opaque frames) | plaintext (under `--secure`), keys |
| publisher device | its own keys + offered files | anything new |
| recipient device | its own keys + received bytes | publisher private key |
| browser | share metadata for the page | control secret, bearer, private key, paths |
| future desktop | same as CLI: own keys, own bearers | control secret |

Any post-v2 architecture that weakens one of these boundaries is **REJECTED
by this document** (not "flagged", not "reviewed" — rejected), because each
row is carried by a golden that the RC battery runs before any release.

## 8. Compatibility rules

Frozen by this decision (v2 is RELEASE — these are the product):

```text
v1 wire compatibility · named refusals (REG/SES/DEV/AUTH/ID/…) · resource
IDs · directory manifest (root-first lexicographic, children-only digest) ·
TransferSession · share tokens · device identity · resume semantics ·
--raw machine lines · JVM+Script dual-face CHECK
```

If a future change would break one: (1) name the broken contract;
(2) justify against the release proofs it invalidates; (3) version it;
(4) provide the migration; (5) NEVER hide the break behind heuristics.
Steps 1–4 are the decision's procedure; a change that cannot complete step 2
without weakening §7 is not a compatibility problem — it is a different product.

## 9. Deferred / Reserved register

| Item | Category | Decision procedure (what would change the status) |
|---|---|---|
| sealed (X25519) envelope over DIRECTORY trees | **DEFERRED** — security/protocol decision, NOT an implementation gap | answer first: one envelope per tree vs one per file vs hierarchical composition (per-child already works plain); the choice changes the HELLO dir branch and the key schedule, so it needs a protocol decision in THIS document before any code |
| STUN/ICE real traversal | **RESERVED** (connect.kf ladder + session.transport additive values) | Kof4j ships the primitives; then a slice measures them; then the slot fills — ladder design already assumes this |
| `web.app().listen()` binds 0.0.0.0 | **RUNTIME CONTRACT** (recorded, not hidden) | a Kof4j bind-address face, or a proxy decision; hardening is a runtime conversation, not a KofShare feature |
| kofshare-core extraction | **DEFERRED** until GUI scheduling | the eight pre-questions below get answered; extraction then ships as a zero-behavior refactor gated by RC-CHECK-OK |
| desktop GUI itself | not FORA DE ESCOPO forever — but **PROPOSED** only; the next major step after these boundaries; no framework is picked, no interfaces are invented now | scheduling decision by the maintainer |
| eight GUI pre-questions (scheduling gate) | recorded unanswered, ON PURPOSE | (1) core API surface (2) client lifecycle (3) where keys live (4) how the GUI observes TransferSession (5) how it controls shares (6) offline behavior (7) named refusals as events (8) transfer start/pause UX |
| control-plane replication / external DB / multi-tenant | **RESERVED** (§4-D7-B table names every seam and every single-node assumption) | a real second node/tenant exists; then the seam list becomes the slice list |
| Android · billing · subscriptions · central storage · fake STUN/ICE · relay-as-storage · protocol rewrite | **FORA DE ESCOPO** (prompt law; storage additionally REJECTED as invariant D7-C) | scope change by the owner of the product, not by convenience |

## 10. Rejected alternatives (explicit, so nobody re-litigates informally)

```text
GUI wrapping the CLI (D8-A)                    — stdout-as-IPC; kills both surfaces
GUI on core, CLI left fat (D8-B)               — two orchestrations drift apart
Browser with direct JS networking              — still REJECTED as in D-NET-JS-V1
   (NETN001/SECN012 close in the language, never by external hacks)
Central content storage, relay that buffers    — D7-C invariant; invalidates release proofs
Fake STUN/ICE / heuristic NAT claims           — honesty law; CONNECTCHECK stamps real dials
Replication/microservices/external DB now      — no second consumer; speculative infra
Track K/L/M to keep activity going             — the battery is the proof, not a to-do list
Abstractions without consumers                  — "future-proof" interfaces are forbidden
   by this document until D8's extraction ships
```

## 11. Decision summary

| # | Decision | Status |
|---|---|---|
| D7 | control plane = central coordinator, data plane decentralized, NO content storage (HA analysis recorded, replication RESERVED) | ACCEPTED |
| D8 | definitive client = CLI + future desktop GUI on a shared kofshare-core (option C); extraction DEFERRED to GUI scheduling | ACCEPTED (direction) / DEFERRED (packaging) |
| D9 | ownership table + NEVER list are the boundary law; changes require document-first procedure | ACCEPTED |
| D10 | DIRECT→(NAT/ICE RESERVED)→RELAY forever; session.transport grows additively only | ACCEPTED / RESERVED (NAT-ICE) |
| — | sealed directory envelope | DEFERRED (protocol question recorded) |
| — | web.listen 0.0.0.0 | RUNTIME CONTRACT (recorded) |

## 12. Consequences

- The topology is now law, not default: central-control + decentralized-data
  cannot be "accidentally" traded for a drive; the goldens are the tripwire.
- The GUI is authorized as the next major shape — and simultaneously
  constrained: it cannot exist before the eight pre-questions are answered
  and cannot exist as anything but a consumer of the (future) core.
- The extraction of `kofshare-core` has a definition of done (battery-green,
  zero behavior diff) and a trigger (GUI scheduling) — so it can never be
  used as a pretext for refactors in between.
- NAT/ICE has a named slot with an additive-value contract; when Kof4j
  grows the primitives, the product fills the slot without touching the wire.
- The known gaps stay exactly as honest as they were at the cut — this
  document records their categories and their decision procedures, it does
  not discharge them.
- Nothing in this document changes code. The next real work is: the
  maintainer answers/schedules D8's trigger, or commissions the sealed-tree
  protocol decision (the DEFERRED question), or bumps the compiler pin (a
  full battery re-measure, per the pin law). All three are decisions with
  procedures already written — which is exactly what closes this stage.
