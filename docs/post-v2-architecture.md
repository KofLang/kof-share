# KofShare — post-v2 architecture decision (DRAFT — awaiting maintainer vote)

status: DECISION DOCUMENT (no implementation). v2 is RELEASE (see STATUS.md);
this file decides the SHAPE of what comes after, from the code that exists.
date: 06/10. Owner lane: security/connectors `192.150.15.15:9092`.
PT-BR: [post-v2-architecture.pt_BR.md](post-v2-architecture.pt_BR.md)

## 0. Ground truth (what v2 already is, file by file)

```
control plane    server/server.kf + control/{app,registry,share,auth}.kf
  - one process, one host; state = in-memory maps + save-on-mutation JSON
    (controlSaveList/controlLoadList) — persistence proven by RESTART-OK
  - identity (Ed25519 devkeys), accounts (bearer JWT), offers, shares,
    sessions (claim/advance), presence (heartbeat+TTL), grants (/s/<token>)
  - carries ZERO file bytes (proven: SESSIONCHECK, INTEGRATIONCHECK)
data plane       transfer.kf + session.kf + protocol.kf + relay.kf + connect.kf
  - device↔device chunk stream; digest-verified; offset-idempotent resume
  - transport chosen honestly: DIRECT → (NAT/ICE RESERVED, not faked) →
    RELAY (opaque ciphertext pump, separate worker process)
device           identity.kf + resource.kf + directory.kf + userflow.kf
  - one keypair per install; resources are LOGICAL device-scoped ids;
    the path↔resource binding table never leaves the owning device
surfaces         cli/cli.kf (user verbs + operator verbs + CHECK legs)
                 app/client.kf (browser lane's localhost client)
```

## 1. Control plane — the definitive central server

Responsibilities it MUST keep (all implemented, do not move):
identity enrollment/revocation · account auth · offer/share registry ·
grant mint+validation+touch · session signaling · presence · policy hooks.

Responsibilities it must NEVER gain: file content, chunk ciphertext,
recipient filesystem layout (three laws already golden-proven; any future
proposal that violates them is rejected at review, not in code).

Telemetry (open question D10): the minimum that already exists as plain
signals (session states, share used-counts, presence timestamps). A
definitive server may add structured audit — but ONLY metadata, same shape
as the registry entries. No new tracking surface without a vote.

## 2. Data plane — stays decentralized, stays honest

```
device A ⇄ DIRECT ⇄ device B        (LAN/whenever dialable)
device A ⇄ RELAY(ciphertext) ⇄ B    (fallback, worker process today)
NAT/ICE: RESERVED — closes only when Kof4j ships real STUN/ICE primitives
```

The relay worker is a byte pump with zero parse (RELAY-OK + tamper proof).
Multiple relay NODES are addable without any protocol change: the grant
already carries relay address as a peer tuple; the session row stamps the
real transport. What is NOT addable without a vote: relays that buffer,
transform, or persist bytes (storage-by-the-back-door).

## 3. Desktop client — layering decision (D7/D8), not a rewrite

Target split:

```
kofshare-core    ← the v2 logic AS A LIBRARY: userflow, connect, transfer,
                   control clients, identity, resources, directories
                   (it already has zero CLI dependencies by file structure)
kofshare-cli     ← thin driver over core (today's cli.kf minus orchestration)
kofshare-desktop ← GUI over core — SAME orchestration calls, never a new
                   protocol client; reads/writes NOTHING the CLI cannot do
```

Laws for the GUI when (not if) it is scheduled:
- the CLI remains the functional reference; CI keeps `--check`+goldens
  green with ZERO GUI code — a GUI bug can never take the product down;
- the GUI may hold NO secret the device keeps: control secret never crosses
  to any client; private key stays in `kofshare-device.ed25519`-equivalent
  storage; bearer stays in the session store; the browser lane keeps its
  metadata-only contract (INTEGRATIONCHECK `browserSecrets`);
- graphics face: Kof4j D-GRAPHICS-WINDOW-FORM + SDL3 (landed 05/10) are the
  only sanctioned windowing route; no Electron/webview-remotes-the-plane.

The split is a packaging move with a hard gate: `kofshare-core` extraction
happens ONLY as a no-behavior-change refactor with the full RC battery as
the proof (same discipline as the 03/10 protocol/session split).

## 4. Server deployment — seams first, scale later

Today: single-node control plane + file-backed state. Seams already in place:

| Future need | Seam that exists today | Still bound to single node |
|---|---|---|
| external DB (replace JSON files) | `controlSaveList/controlLoadList` choke points | the in-memory maps + per-mutation save |
| replicated control plane | HTTP contract is stateless per request | bearer secret + devkeys + file stores |
| multiple relay nodes | relay = separate process + peer tuple in grant | nothing (already separable) |
| multi-tenant accounts | `Account(id,label,status)` record | authorization is plane-global today |
| orgs/policies/quotas | addable records (original v1 §"not-now" law) | — |

DECISION: keep single-node until a real second tenant exists; do NOT build
generic multi-node infra speculatively (the prompt's own anti-rule). When
the DB swap is scheduled, the persistence unit is `control/{registry,share,
auth}` loaders — a contained, testable cut with `PERSIST-OK`/`RESTART-OK`
as its regression net.

## 5. Storage — the non-goal, stated as an invariant

The central server stores: metadata, identities, grants, sessions, account
state, presence, minimal audit. It does NOT store shared content. The
relay does NOT buffer content to disk. This is not a policy preference —
it is what the code measurably does today (HTTPCHECK/RELAY/INTEGRATION
goldens). Any "make it a drive" proposal is OUT OF SCOPE by definition of
the product, not by oversight.

## 6. Security boundaries — component × knowledge matrix

```
                      control  relay  publisher  recipient  browser  desktop
 control secret          YES     no      no        no         no      NO EVER
 device private key       no     no      own one   own one    no      no
 account bearer           mints   no     own       own*       NO      own
 share token              YES     no      owner     presented  page    via core
 resourceId              YES     no      local tbl local tbl  metadata n/a
 plaintext file bytes      NO     NO     disk only  disk only   NO     disk only
 ciphertext on the wire    NO    passes   —          —          NO      —
```
(`*` recipient bearer only in CLI/desktop; the browser NEVER sees one.)
The desktop row is a CONTRACT for D7/D8, not an observation. The GUI must
not concentrate secrets that are isolated today — the matrix is the gate.

## 7. What this document deliberately does NOT do

No Track K. No GUI code. No Android/billing/subscriptions/central storage.
No fake STUN/ICE. No protocol change. No new named refusal. No rewrite of
a v2 contract. No abstraction without a consumer. It states the shape so
the FIRST code after v2 is a decision with a proof plan, not a demo.

## 8. Open decisions for the maintainer (vote format, like D1–D6)

- **D7** desktop toolkit/form: SDL3 window + Kof-drawn UI (recommended,
  matches the landed graphics faces) vs webview-over-local-client vs defer.
- **D8** core extraction moment: now as a battery-verified no-behavior
  refactor (recommended) vs at GUI scheduling time.
- **D9** deployment target: single-node stays the reference until a second
  tenant (recommended) vs plan DB/replication first.
- **D10** telemetry floor: metadata-only audit table (recommended) vs none.

When a vote lands, the roadmap section of `docs/next-plan.md` gains the
matching slice — implement→test→golden→regression→document→commit, same
cadence, compiler limitations stop features (never silent workarounds).
