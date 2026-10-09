# KofShare

Direct, digest-verified file & directory sharing for humans. **v2 = RELEASE**
(cut 06/10; compiler pin `f2629e32d`, jar sha256 `0b1893b4…`; the full
battery `RC-CHECK-OK steps=23` green on the cut tree). The wire never packs a tree, never fakes a transport, and never
sees the recipient's disk layout. The control plane coordinates and carries
zero file bytes; data flows device→device (DIRECT) or through a
ciphertext-only relay.

```text
Control Plane (HTTP)
      |
      +---- identity (Ed25519 device keys)
      +---- accounts (bearer/JWT)
      +---- offers / resources
      +---- shares (links, expiry, use counts, revocation)
      +---- sessions (claim / advance state machine)
      +---- presence (heartbeat + TTL)
      |
      +---- NO FILE BYTES, EVER
                |
                v
         Data Plane (TCP frames)
          /       \
      DIRECT      RELAY (ciphertext-only pump)

Resource ──(local binding table)──▶ filesystem
   (remote identity is an id, never a path)
```

## Quick start (the whole product in five lines)

```bash
J=/path/to/kof-cli.jar
java -jar $J run src/main/kof/kofshare/cli/cli.kf server 18323 --start
java -jar $J run src/main/kof/kofshare/cli/cli.kf share ./report.pdf --server 127.0.0.1:18323
# → "Link (copy and send):" http://host:port/s/<token>
java -jar $J run src/main/kof/kofshare/cli/cli.kf receive http://host:port/s/<token>   # recipient
java -jar $J run src/main/kof/kofshare/cli/cli.kf stop                                  # end offering
```

`share` works on FILES and DIRECTORIES (`share ./docs` → "Files: N"); the
directory is a COLLECTION of resources — every child transfers, resumes and
verifies on its own. `receive` drives the browser page's exact contract
through the local client (the page is `app`; the browser talks only to
localhost and never sees a key, a bearer, or a path). There is no daemon to
install: the plane is `server`, the offering helper is `stop`-pable.

`share` picks the best REAL path: DIRECT → (NAT reserved, see Limits) →
RELAY when given `--relay`. It never reports a transport it did not use —
the session row is stamped by the actual dial (proof: `INTEGRATIONCHECK-OK`).

## CLI

| verb | audience | what |
|---|---|---|
| `share <path>` | user | one command: identity, offer, link, active offer (file **or directory**) |
| `share <path> --to <account>` | user | RESTRICTED link: only that authenticated account can open it — possession of the URL grants nothing |
| `receive <link> [dest] [--bearer <key>]` | user | resolves once, auto-connects, verifies digest per file, resumes per file; `--bearer file:<path>` keeps the key out of the process table |
| `stop` | user | kills the helper processes this device started (face/app/server pids) |
| `app <plane> <port> <token> <key> <dir>` | browser lane | local client: page + `/api/info` metadata + job queue |
| `server [port] [--start]` | operator | the control plane (`--start` = detached + readiness wait) |
| `up` / `down` | operator | signed publish / fetch legs (v1-compatible flags: `--id`, `--relay`, `--secure`, `--resume`, `--auto`) |
| `updir` / `downdir` / `serve-dir` | operator | directory publish / pull / serve face |
| `offer` / `fetch` / `serve` | operator | raw plane and data-plane verbs |
| `device` / `account` / `heartbeat` | operator | identity, auth, presence |
| `relay <port> <peer>` | operator | ciphertext-only relay worker |
| `shares` / `revoke` / `authorize` | operator | share lifecycle |
| `--check` | CI | 14 pure legs, JVM and Script |
| `--raw` (with `share`) | scripts | machine-readable `UP-OK` / `SHARED` / `SHARE-LINK` lines |

Named internal errors (`REG015`, `DEV-OFFLINE`, `CONNECTIVITY_FAILED`, …) are
NEVER removed — they are the diagnostic contract. `share`/`receive` add a
human `Hint:` line on top (`UXCHECK-OK` proves no stack trace reaches a user).

## Concepts (five)

- **device** — one Ed25519 identity per installation (`d-<hash>`), enrollment
  is TOFU, revocation kills every future grant AND live links through it.
- **resource** — a name+size+digest with a LOGICAL, device-scoped id
  (`r-<hash>`); the path only exists in the owner's local binding table.
  Two devices with identical bytes get different resources.
- **share** — a token with expiry/maxUses/readOnly/dir flags. One link per
  tree; `?child=N` resolves the N-th file of the server-sorted manifest.
- **session** — the claim/advance state machine that coordinates a transfer;
  the plane never carries payload.
- **transport** — the honest result of `pickAndDial`: `direct` or `relay`,
  stamped on the session by the real dial that happened.

## Security

Ed25519 signed enrollments/offers/shares (public half verifies); bearer/JWT
account gate on the plane; IDENTITY-BOUND GRANTS (`share --to`): the minted
link is a LOCATOR, not a capability — redemption requires the plane-verified
recipient identity (`GRANTCHECK/HTTPGRANT/RECIPIENTAUTHCHECK` goldens; wrong
identity gets the opaque `REG035`, byte-identical to a dead link, and the
attempt consumes NO budget); revocation is owner-enforced (`AUTH005` for
non-owners) and propagates grant↔share; the desktop daemon keeps its account
bearer `0600` device-local, hands it to workers only as `file:` references,
and its mutating API rides the token+Host+Origin boundary (`DESKTOP-PRIV`
legs include the bearer-leak scan — zero occurrences across every observed
byte); X25519 + HKDF encrypt-then-MAC chunk envelope for
`--secure` sessions (tamper refuses before bytes reach the file); the relay
pumps ciphertext and cannot parse; share/device revocation is transitive to
grants; directory manifests are recomputed by the plane (`REG015/REG016`) and
re-validated by the recipient client (`dirJoinSafe`) — traversal dies twice;
the browser lane receives metadata only (never keys, never bearer, never
paths). Proof per property: `SECURITY` section of `STATUS.md` and each golden.

## Limits (honest, from the prompt)

- **NAT/ICE**: the strategy reserves the slot; Kof4j has no STUN/ICE today.
  The goldens use a DEAD direct grant + relay as the documented NAT analog.
  No real NAT traversal is claimed.
- **Directories over `--secure`/relay**: per-child sessions work; the sealed
  (X25519) envelope on the directory face is plain transport only — the
  sealed-tree lane is deferred (Track H boundary, documented, not faked).
- **Desktop GUI, billing, Android, central storage**: out of scope by design.
- `web.app().listen()` binds 0.0.0.0 (runtime contract): the plane page is
  LAN-reachable by construction; hardening is a known open item, not hidden.
- Upstream compiler issues CLOSED/FIXED (verified by reproduction A/B
  06/10): KofLang/Kof4j#770 (`COMP002` nullable parameters — ledger
  §609+§610+§612) and #771 (HTTP `ConnectException` escape — §608). The
  permanent reproduction packets stay in `docs/upstream/`; product
  workarounds stay (tested, correct, wire-independent).

## Tests

```bash
java -jar $J run src/main/kof/kofshare/cli/cli.kf --check          # 14 legs
java -jar $J run src/main/kof/kofshare/rc/runrc.kf                 # release battery → RC-CHECK-OK steps=23
```

The post-v2 architecture is a recorded DECISION (D7–D10, 06/10): central
control plane / decentralized data plane forever, CLI+desktop GUI over one
kofshare-core, ownership table + NEVER-list of secrets, session.transport
grows additively only — see `docs/post-v2-architecture.md`. The cut itself
changed no contract.

Per-suite markers: `UXCHECK-OK`, `INTEGRATIONCHECK-OK`, `FOLDERCHECK-OK`,
`RESOURCECHECK-OK`, `BROWSERCHECK-OK`, `CONNECTCHECK-OK`, `SESSIONCHECK-OK`,
`IDENTITYCHECK-OK`, `USERCHECK-OK`, `SERVECHECK-OK`, `RESUMECHECK-OK`,
`SHARECHECK-OK`, `PERSIST-OK`, `RELAY-OK`, `HTTPCHECK-OK`, `RESTART-OK`.

The compiler history of this product (bugs caught by the goldens, with
reproductions) is in the Kof4j ledger (`§583/§588/§590/§593/§603` + the
#770/#771 family §608/§609/§610/§612); the permanent reproduction packets live
under `docs/upstream/`.
