# kof-share
## Transfer core (sliced 02/10)

`src/main/kof/kofshare/transfer.kf` — 100% Kof over `kof.net` (D-KOF-NET):
frame `len(4 BE) | index(4 BE) | payload`, offset-idempotent resume
(`serveFile` from `resumeOffset`, `fetchFile` appends the `.part`).

## Session envelope (landed 02/10)

`src/main/kof/kofshare/handshake.kf` — over the now-real `keyExchange`
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
```

## O que falta / próximo
Fatias em 02/10 em [`docs/implementation-plan.md`](docs/implementation-plan.md) (EN) / [`docs/implementation-plan.pt_BR.md`](docs/implementation-plan.pt_BR.md) (PT): control plane (registro + HTTP), CLI (`--check`/`--dry`), extração `session.kf`/`protocol.kf`, relay fallback, empacotamento. As âncoras do stdlib estão medidas (D-KOF-NET, D-KOF-X25519, `web.app`+`http` verdes em `KofHttpE2ETest`); identidade/confiança continua rule-6 (sem face Ed25519).
