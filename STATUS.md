English below

# KofShare — STATUS (03/10, tip `b6596ef`+)

## Pronto e MEDIDO neste tip (output esperado abaixo)

| Camada | O quê | Prova |
|---|---|---|
| Data plane | transferência chunked 200 KB resume@100000; envelope X25519+HKDF encrypt-then-MAC resume@123456; tamper de 1 byte recusa na tag antes do plaintext | `e2e.kf` → `E2E-OK`+`SEC-E2E-OK` JVM+Script; `probe/tamper.kf` → `TAMPER-OK` |
| Controle | registro devices/offers puro Kof (recusas nomeadas REG001–008) | `control/check.kf` → `REGCHECK-OK` JVM+Script (24/24) |
| HTTP | rotas §4 (`POST/GET /devices[:id]`, `GET/POST/DELETE /offers[:id]`, `/health`) + C2 (`POST/GET /shares`, `GET /s/<token>`, `POST /shares/:id/revoke`) | `httpcheck/checkhttp.kf` → `HTTPCHECK-OK` 21/21 nas 3 combinações JVM/Script servidor×cliente |
| Relay | byte-pump ciphertext-only; flip de 1 byte no relay → tag morre, zero bytes gravados | `relaycheck/checkrelay.kf` → `RELAY-OK` JVM+Script |
| CLI | `server`/`offer`/`fetch [--resume --key --secure --relay]`/`relay`/`--check`/`--dry` | `cli/cli.kf --check` → `registry=true persist=true plain=true secure=true CHECK-OK` JVM+Script |
| Empacotamento | `kof.toml` + árvore + README | `--check` verde com o manifesto presente |

## Como validar (uma sessão)

```bash
J=/home/mel/.local/jdk/jdk25/bin/java
K=kof-cli-0.5.0-beta.jar   # jar do tip do Kof4j (rebuild: mvn -o -q -pl kof-cli -am clean package -DskipTests)

$J --enable-native-access=ALL-UNNAMED -jar $K run --target jvm    src/main/kof/kofshare/cli/cli.kf --check   # → CHECK-OK
$J --enable-native-access=ALL-UNNAMED -jar $K run --target script src/main/kof/kofshare/cli/cli.kf --check   # → CHECK-OK
$J --enable-native-access=ALL-UNNAMED -jar $K run --target jvm    src/main/kof/kofshare/control/check.kf      # → REGCHECK-OK
$J --enable-native-access=ALL-UNNAMED -jar $K run --target jvm    src/main/kof/kofshare/probe/tamper.kf       # → TAMPER-OK
$J --enable-native-access=ALL-UNNAMED -jar $K run --target jvm    src/main/kof/kofshare/relaycheck/checkrelay.kf # → RELAY-OK
$J --enable-native-access=ALL-UNNAMED -jar $K run --target jvm    src/main/kof/kofshare/sharecheck/checkshare.kf  # → SHARECHECK-OK
$J --enable-native-access=ALL-UNNAMED -jar $K run --target script src/main/kof/kofshare/sharecheck/checkshare.kf  # → SHARECHECK-OK
$J ... run --target jvm src/main/kof/kofshare/server/server.kf &   # control plane com /shares
$J ... run --target jvm src/main/kof/kofshare/httpcheck/checkhttp.kf # → HTTPCHECK-OK (inclui as pernas de share)
# laço real com dois terminais:
$J ... run --target jvm src/main/kof/kofshare/cli/cli.kf server            # → SERVER-READY port=…
$J ... run --target jvm src/main/kof/kofshare/cli/cli.kf offer <arquivo>   # → OfferInfo JSON com sha256Bytes real
$J ... run --target jvm src/main/kof/kofshare/cli/cli.kf fetch <host> <porta> <dest> [--resume N] [--key <hex>] [--secure] [--relay <r> <rp>]
```

## Lacunas vs. o spec original (honesto, sem gloss)

1. **Identidade criptográfica de dispositivo (§6, §12)** — VOTADO D1=A 03/10: face `crypto.sign/verify` aprovada, registrada como `D-KOF-SIGN` no Kof4j; fatia C1 (compilador) a implementar. Até lá: LAN-trust. — **FEITA 03/10 (C1 no Kof4j + C2 aqui):** face `crypto.sign`/`crypto.verify` Ed25519 embarcada (`D-KOF-SIGN`, `CryptoSignE2ETest` 3/3 JVM+Script, SECN013 nomeado em JS/Native/cross); o control plane tem chave Ed25519 persistida (`server-control.ed25519`) e cada grant é assinado sobre o núcleo canônico. `whoami`/assinatura de devices continua opcional (o token forte já é a autorização de posse).2. **Link de autorização `/s/<token>` (§8)** — **FEITA 03/10 (C2, voto D2=A):** `control/share.kf` = modelo completo (token 64-hex via `security.randomHex(32)` na borda, `expiresAt`, `maxUses`/`--once`, `readOnly`, revocation, status) com recusas nomeadas REG030–REG041; rota `GET /s/<token>` decide via `shareTouch` (só `OK` serve metadados; usado/expirado/revogado/desconhecido recusam por nome) e persiste; golden `sharecheck/checkshare.kf` → `SHARECHECK-OK` 22/22 JVM+Script + prova de restart (`restart/probe.kf` → `RESTART-OK`: shares/devices/chave voltam do disco).3. **Contas / login (§4, §15)** — não implementado; v1 não tem authN no control plane. (Face `security.apiKeyGenerate/csrfToken` existe se optar por bearer-token local.) → decisão D3.
4. **Descoberta automática de caminho (local → ICE → relay) (§13, §17)** — relay funciona mas é escolha explícita `--relay`; sem detecção automática de conectividade recusada e sem presença online/offline. → decisão D4.
5. **Destinatário abre o link no browser (§1, §25)** — exige cliente JS: `kof.net` no JS recusado no compile (`NETN001`) e `keyExchange` recusado (`SECN012`). Hoje o destinatário usa CLI. → decisão D5.
6. **Pastas (§18)** — só arquivos; diretório como coleção lógica de recursos não implementado. → decisão D6.
7. ~~**Persistência do registro (§17, crash-doesn't-forget)**~~ — **FEITA 03/10 (A1):** `PERSIST-OK` 9/9 JVM+Script; servidor salva após cada mutação e recarrega no boot (sonda de restart medida: 2 devices voltam do disco). Falta só a perna `persist=true` no `--check`.
8. **Negociação de resume (§10)** — offset coordenado fora-de-faixa; sem verificação servidor↔cliente. → fatia A3.

## Próximo passo técnico

`docs/next-plan.md` (+PT): Track A sem decisão (A1 persistência, A2 ponte SSE/WS do §574 no compilador, A3 resume negotiation, A4 expiração de ofertas) e Track B = as decisões abaixo. Nada do Track A depende de voto.

---

# English

Ready & measured at this tip: data plane (plain+sealed envelope transfer, tamper-refused), control plane (registry+HTTP, refused-by-name; A1 persistence with corrupt-refusal REG009), C2 share model — full bearer grants (64-hex token, expiresAt, maxUses/--once, readOnly, revocation, REG030–REG041 named refusals) signed with the persisted control Ed25519 key (C1: `D-KOF-SIGN` landed in Kof4j — `crypto.sign`/`verify` JVM+Script, `SECN013` named gap on JS/Native/cross), ciphertext-only relay, full CLI (`--check` → `CHECK-OK` JVM+Script with five legs incl. `share=true`), packaging. Proofs: `SHARECHECK-OK` 22/22 JVM+Script, `HTTPCHECK-OK` 21/21 (live `/shares`, `/s/<token>`, revoke), `RESTART-OK` (shares+devices+key reload from disk). Gaps left vs the original spec: accounts/authN bearer (C3, vote D3=B), automatic path selection (relay manual by vote D4=A), browser recipient (NETN001/SECN012 pinned, vote D5=A), directories (vote D6=A deferred), resume negotiation (A3 planned). One live compiler bug found while landing C2: Kof4j `known-bugs` §583 (int-slot→Long widening inside captured lambdas → VerifyError at first dispatch) — product ships the honest typed-Long form; §582 (bare packaged-record ctor in imported bodies) was fixed in the same pass. Validate with the commands above; see `docs/next-plan.md`.


