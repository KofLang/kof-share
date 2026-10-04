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

1. **Identidade criptográfica de dispositivo (§6, §12)** — VOTADO D1=A 03/10: face `crypto.sign/verify` aprovada, registrada como `D-KOF-SIGN` no Kof4j; fatia C1 (compilador) a implementar. Até lá: LAN-trust. — **FEITA 03/10 (C1 no Kof4j + C2 aqui):** face `crypto.sign`/`crypto.verify` Ed25519 embarcada (`D-KOF-SIGN`, `CryptoSignE2ETest` 3/3 JVM+Script, SECN013 nomeado em JS/Native/cross); o control plane tem chave Ed25519 persistida (`server-control.ed25519`) e cada grant é assinado sobre o núcleo canônico. `whoami`/assinatura de devices continua opcional (o token forte já é a autorização de posse).2. **Link de autorização `/s/<token>` (§8)** — **FEITA 03/10 (C2, voto D2=A):** `control/share.kf` = modelo completo (token 64-hex via `security.randomHex(32)` na borda, `expiresAt`, `maxUses`/`--once`, `readOnly`, revocation, status) com recusas nomeadas REG030–REG041; rota `GET /s/<token>` decide via `shareTouch` (só `OK` serve metadados; usado/expirado/revogado/desconhecido recusam por nome) e persiste; golden `sharecheck/checkshare.kf` → `SHARECHECK-OK` 22/22 JVM+Script + prova de restart (`restart/probe.kf` → `RESTART-OK`: shares/devices/chave voltam do disco).3. **Contas / login (§4, §15)** — **FEITA 03/10 (C3, voto D3=B):** o control plane exige bearer em toda rota mutável/listável (`/devices* /offers* /shares* /accounts*`; `/health` e `/s/<token>` continuam públicos — o token do link É a autorização de posse). A credencial é um **JWT** assinado com o segredo de controle (`security.apiKeyGenerate` mintado uma vez, persistido em `server-control.apikey` — mesma trava honesta de host único v1); a tabela `control/auth.kf` guarda IDENTIDADE + estado (`Account(id,label,status,createdAt)`), e revogar mata o bearer mesmo com assinatura válida (`AUTH001/002/003/004/005/006`, arquivo corrompido = `AUTH043`). Nota de plataforma medida: o runtime web do Kof4j intercepta `Authorization` inválido ANTES do handler (401 JSON do passo 6 do dispatch — documentado no comentário do gate). Bootstrap: primeira conta em tabela vazia é auto-inscrição (admin em `server-control.bearer`). CLI `account list|add|revoke` + `--check` perna 6 `auth=true`. Provas: `HTTPCHECK-OK` 28/28 gateado, `RESTART-OK` 6/6 (bearer + segredo + revogação sobrevivem restart), ciclo CLI medido ao vivo.
4. **Descoberta automática de caminho (local → ICE → relay) (§13, §17)** — relay funciona mas é escolha explícita `--relay`; sem detecção automática de conectividade recusada e sem presença online/offline. → decisão D4.
5. **Destinatário abre o link no browser (§1, §25)** — exige cliente JS: `kof.net` no JS recusado no compile (`NETN001`) e `keyExchange` recusado (`SECN012`). Hoje o destinatário usa CLI. → decisão D5.
6. **Pastas (§18)** — só arquivos; diretório como coleção lógica de recursos não implementado. → decisão D6.
7. ~~**Persistência do registro (§17, crash-doesn't-forget)**~~ — **FEITA 03/10 (A1):** `PERSIST-OK` 9/9 JVM+Script; servidor salva após cada mutação e recarrega no boot (sonda de restart medida: 2 devices voltam do disco). Falta só a perna `persist=true` no `--check`.
8. **Negociação de resume (§10)** — **FEITA 03/10 (A3):** o receptor anuncia o tamanho do `.part` num HELLO head (`helloIndex`) antes de qualquer payload; o SERVIDOR verifica contra o tamanho real e serve daquele offset — offset inválido recusa **por nome** (`RESUME-ERR: server file shorter than requested offset` / `RESUME-ERR: negative offset`, head `resumeErrIndex`, nada corrompe). Vale no plain e no envelope selado. `OfferInfo` continua SEM campo de sessão (nota aposentada: a coordenação agora É in-band). Golden `resumecheck/checkresume.kf` → `RESUMECHECK-OK` (mid 2000/5000, done 5000/5000, recusas plain+selado, `.part` intacto; JVM).

## Próximo passo técnico

`docs/next-plan.md` (+PT): Track A sem decisão (A1 persistência, A2 ponte SSE/WS do §574 no compilador, A3 resume negotiation, A4 expiração de ofertas) e Track B = as decisões abaixo. Nada do Track A depende de voto.

---

# English

Ready & measured at this tip: data plane (plain+sealed envelope transfer, tamper-refused), control plane (registry+HTTP, refused-by-name; A1 persistence with corrupt-refusal REG009), C2 share model — full bearer grants (64-hex token, expiresAt, maxUses/--once, readOnly, revocation, REG030–REG041 named refusals) signed with the persisted control Ed25519 key (C1: `D-KOF-SIGN` landed in Kof4j — `crypto.sign`/`verify` JVM+Script, `SECN013` named gap on JS/Native/cross), ciphertext-only relay, full CLI (`--check` → `CHECK-OK` JVM+Script with six legs: `registry persist plain secure share auth`), packaging. Proofs: `SHARECHECK-OK` 22/22 JVM+Script, `HTTPCHECK-OK` 28/28 marker-gated (live `/shares`, `/s/<token>`, revoke, C3 bearer matrix incl. runtime-401 on tampered Authorization), `RESTART-OK` 6/6 (shares+devices+key+accounts+bearer reload from disk; revoked account stays dead after restart). C3 landed same day (vote D3=B, implemented on the runtime's native JWT layer — `auth.secret`/`auth.authenticated`/`auth.claims`, control secret minted by `security.apiKeyGenerate`). A4 registry hygiene landed same day (offer `createdAt` stamped server-side — client wire is the separate `OfferRequest`, `REG010` unstamped refusal, `controlPurgeExpired` drops stale-by-age + dangling-by-device at boot, logged not silent; the plan's 'OfferInfo unchanged' was measured impossible for time-expiry and the deviation is recorded in next-plan). Gaps left vs the original spec: automatic path selection (relay manual by vote D4=A), browser recipient (NETN001/SECN012 pinned, vote D5=A), directories (vote D6=A deferred), resume negotiation (A3 planned). The two compiler bugs found while landing C2 are now CLOSED in Kof4j: §583 fixed 03/10 (root was `json.decode<T>` typing UNKNOWN on the SEM analyzer while the emit knew T — SEM012 was skipped and the JVM died VerifyError at first dispatch; the analyzer now mirrors the emit's json branch, `JsonDecodeLongAssignE2ETest` 3/3 — the product's typed-Long form remains correct and runs green on the rebuilt jar) and §582 fixed the same day (bare packaged-record ctor in imported bodies). Validate with the commands above; see `docs/next-plan.md`.


