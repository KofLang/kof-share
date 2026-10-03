# kof-share
## Transfer core (sliced 02/10)

`src/main/kof/kofshare/protocol.kf` — wire framing + codec:
frame `len(4 BE) | index(4 BE) | payload`, each payload followed by a
64-hex HMAC-SHA256 tag. `src/main/kof/kofshare/transfer.kf` — the plain
(unsealed) state machine (`serveFile`/`fetchFile`), offset-idempotent
resume (sender starts at `resumeOffset`, receiver appends the `.part`).

## CLI entry (landed 03/10)

`src/main/kof/kofshare/cli/cli.kf` (`package kofshare.cli`) — the product
entry, JVM+Script:

```
kof run .../cli/cli.kf --target jvm --check   # registry + plain + secure, prints CHECK-OK
kof run .../cli/cli.kf --target script --check
kof run .../cli/cli.kf --target jvm --dry     # print the resolved plan, no IO
kof run .../cli/cli.kf --target jvm offer <file>       # OfferInfo JSON, real content digest
kof run .../cli/cli.kf --target jvm fetch <host> <port> <dest> [--resume] [--key <hex>] [--secure] [--relay <rhost> <rport>]
kof run .../cli/cli.kf --target jvm relay <port> <peerHost> <peerPort> [--tamper]
kof run .../cli/cli.kf --target jvm server [port] [--key <hex>]
```

`--check` is the one command that shows the whole product green: pure
registry golden + the plain transfer leg (resume@100000) + the secure
X25519/HKDF envelope leg (resume@123456), real `kof.net` loopback. The
entry lives in its own subpackage because the module enforces ONE `main()`
per package (`e2e.kf` already owns the `kofshare` one).

## Relay fallback (landed 03/10)

`src/main/kof/kofshare/relay.kf` — architecture §7: direct LAN first, relay
through the control host as a **ciphertext-only** fallback. The relay is a
framing-agnostic byte pump (it never parses `protocol.kf` headers, so it
cannot read or rewrite payloads); it propagates the half-close on EOF and
survives a socket the sibling direction already closed. `fetch --relay
<rhost> <rport> [--secure]` routes through it, and `relay <port> <peerHost>
<peerPort>` serves one session (`--tamper` flips one ciphertext byte, probe
only). Proof: `relaycheck/checkrelay.kf` → `RELAY-OK` on JVM **and** Script
(`direct=true relayed=true tamperRefused=true`; the tampered relay is
refused by the envelope tag and appends nothing). No STUN/ICE, no NAT
hole-punching claimed — post-MVP.

## Session envelope (landed 02/10; split 03/10)

`src/main/kof/kofshare/session.kf` — over the now-real `keyExchange`
face (D-KOF-X25519, Kof4j `02/10`): ephemeral X25519 each side, HELLO
frame (index `1073741822`) carries the 64-hex public value + the server's
random salt (private scalars never leave `Secret` — R8), HKDF-SHA256
derives per-direction keys (`enc`/`mac` × `c2s`/`s2c`, RFC 5869), and the
transfer framing rides **encrypt-then-MAC**: chunk → hex → AES-GCM → the
64-hex HMAC tag is recomputed over the CIPHER bytes (`crypto.hmacSha256`).
A flipped byte — head, payload or tag — refuses before any plaintext
reaches the file, and the tag check alone already kills a MITM (no mac
key, no valid first chunk). Targets: `--target jvm` and `--target script`
(the face is real there); `kof.net`/`keyExchange` stay refused on JS
(`NETN001`/`SECN012`) — out of KofShare's v1 scope.

Oracle: `e2e.kf` runs BOTH legs — plain (resume@100000) and secure
(resume@123456) — and `probe/tamper.kf` now also proves the envelope
refusal (diverges / tag-differ / refused-before-decrypt / no-plaintext).

```
java --enable-native-access=ALL-UNNAMED -jar <Kof4j>/kof-cli/target/kof-cli-0.5.0-beta.jar \
     run --target script src/main/kof/kofshare/e2e.kf   # E2E-OK + SEC-E2E-OK
java --enable-native-access=ALL-UNNAMED -jar <Kof4j>/kof-cli/target/kof-cli-0.5.0-beta.jar \
     run --target jvm    src/main/kof/kofshare/e2e.kf   # E2E-OK + SEC-E2E-OK
java --enable-native-access=ALL-UNNAMED -jar <Kof4j>/kof-cli/target/kof-cli-0.5.0-beta.jar \
     run --target jvm    src/main/kof/kofshare/probe/tamper.kf   # TAMPER-OK
java --enable-native-access=ALL-UNNAMED -jar <Kof4j>/kof-cli/target/kof-cli-0.5.0-beta.jar \
     run --target jvm    src/main/kof/kofshare/relaycheck/checkrelay.kf   # RELAY-OK
```

## Packaging (landed 03/10)

`kof.toml` declares `[project] name = "kof-share"`, `[backend] target =
"jvm"` and `[sources] app = "src/main/kof"`. An explicit `--target` still
overrides the backend target, and `--check` is green on JVM and Script with
the manifest present.

## O que falta / próximo
Todas as seis fatias do plano autorizado estão POUSADAS 03/10 em [`docs/implementation-plan.md`](docs/implementation-plan.md) (EN) / [`docs/implementation-plan.pt_BR.md`](docs/implementation-plan.pt_BR.md) (PT): 1 registro, 2 control plane, 3 CLI, 4 split `protocol.kf`/`session.kf`, 5 relay, 6 empacotamento. Restam apenas os itens rule-6 do §3 (identidade/Ed25519, hole-punching/STUN-ICE, alvos de produto JS/Native). As âncoras do stdlib estão medidas (D-KOF-NET, D-KOF-X25519, `web.app`+`http` verdes em `KofHttpE2ETest`). O plano sucessor — o que falta, entre fatias sem decisão (persistência do registro, ponte SSE/WS no Script, negociação de resume, expiração de ofertas) e as faces rule-6 (identidade/Ed25519, ICE-lite, alvos JS/Native) — está em [`docs/next-plan.md`](docs/next-plan.md) (EN) / [`docs/next-plan.pt_BR.md`](docs/next-plan.pt_BR.md) (PT), com as bordas re-medidas no tip.
