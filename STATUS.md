English below

# KofShare — STATUS (03/10, tip `b6596ef`+)

## Pronto e MEDIDO neste tip (output esperado abaixo)

| Camada | O quê | Prova |
|---|---|---|
| Data plane | transferência chunked 200 KB resume@100000; envelope X25519+HKDF encrypt-then-MAC resume@123456; tamper de 1 byte recusa na tag antes do plaintext | `e2e.kf` → `E2E-OK`+`SEC-E2E-OK` JVM+Script; `probe/tamper.kf` → `TAMPER-OK` |
| Controle | registro devices/offers puro Kof (recusas nomeadas REG001–008) | `control/check.kf` → `REGCHECK-OK` JVM+Script (24/24) |
| HTTP | rotas §4 (`POST/GET /devices[:id]`, `GET/POST/DELETE /offers[:id]`, `/health`) | `httpcheck/checkhttp.kf` → `HTTPCHECK-OK` 14/14 nas 3 combinações JVM/Script servidor×cliente |
| Relay | byte-pump ciphertext-only; flip de 1 byte no relay → tag morre, zero bytes gravados | `relaycheck/checkrelay.kf` → `RELAY-OK` JVM+Script |
| CLI | `server`/`offer`/`fetch [--resume --key --secure --relay]`/`relay`/`--check`/`--dry` | `cli/cli.kf --check` → `registry=true plain=true secure=true CHECK-OK` JVM+Script |
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
# laço real com dois terminais:
$J ... run --target jvm src/main/kof/kofshare/cli/cli.kf server            # → SERVER-READY port=…
$J ... run --target jvm src/main/kof/kofshare/cli/cli.kf offer <arquivo>   # → OfferInfo JSON com sha256Bytes real
$J ... run --target jvm src/main/kof/kofshare/cli/cli.kf fetch <host> <porta> <dest> [--resume N] [--key <hex>] [--secure] [--relay <r> <rp>]
```

## Lacunas vs. o spec original (honesto, sem gloss)

1. **Identidade criptográfica de dispositivo (§6, §12)** — VOTADO D1=A 03/10: face `crypto.sign/verify` aprovada, registrada como `D-KOF-SIGN` no Kof4j; fatia C1 (compilador) a implementar. Até lá: LAN-trust.
2. **Link de autorização `/s/<token>` (§8)** — o produto hoje expõe `/offers/:id` com id fraco; não há token de alta entropia, `expiresAt`, `maxUses`, `read-only`, revogação por share. As peças existem (`security.randomHex` medido fresco JVM+Script; `web.app` rotas; `json` records) — falta o modelo `Share` e a rota. → decisão D2/D3.
3. **Contas / login (§4, §15)** — não implementado; v1 não tem authN no control plane. (Face `security.apiKeyGenerate/csrfToken` existe se optar por bearer-token local.) → decisão D3.
4. **Descoberta automática de caminho (local → ICE → relay) (§13, §17)** — relay funciona mas é escolha explícita `--relay`; sem detecção automática de conectividade recusada e sem presença online/offline. → decisão D4.
5. **Destinatário abre o link no browser (§1, §25)** — exige cliente JS: `kof.net` no JS recusado no compile (`NETN001`) e `keyExchange` recusado (`SECN012`). Hoje o destinatário usa CLI. → decisão D5.
6. **Pastas (§18)** — só arquivos; diretório como coleção lógica de recursos não implementado. → decisão D6.
7. ~~**Persistência do registro (§17, crash-doesn't-forget)**~~ — **FEITA 03/10 (A1):** `PERSIST-OK` 9/9 JVM+Script; servidor salva após cada mutação e recarrega no boot (sonda de restart medida: 2 devices voltam do disco). Falta só a perna `persist=true` no `--check`.
8. **Negociação de resume (§10)** — offset coordenado fora-de-faixa; sem verificação servidor↔cliente. → fatia A3.

## Próximo passo técnico

`docs/next-plan.md` (+PT): Track A sem decisão (A1 persistência, A2 ponte SSE/WS do §574 no compilador, A3 resume negotiation, A4 expiração de ofertas) e Track B = as decisões abaixo. Nada do Track A depende de voto.

---

# English

Ready & measured at this tip: data plane (plain+sealed envelope transfer, tamper-refused), control plane (registry+HTTP, refused-by-name), ciphertext-only relay, full CLI (`--check` → `CHECK-OK` JVM+Script), packaging. Gaps vs the original spec, all listed with the exact measured blocker above: device identity/signing (no Ed25519 face in the compiler — decision needed), share-link model with high-entropy tokens/expiry/maxUses (pieces measured, model absent), accounts/authN, automatic path selection (relay is manual), browser recipient (blocked by NETN001/SECN012), directories, persistence, resume negotiation (pure-Kof fixable, planned). Validate with the commands above; see `docs/next-plan.md`.
