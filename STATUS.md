English below

# KofShare — STATUS (04/10, tip `199562e`+)

## Pronto e MEDIDO neste tip (output esperado abaixo)


Lado compilador (Kof4j), 04/10: o leak do analisador `json.decode<T>` do §583 está **corrigido upstream** com blast radius medido; §588 (guard de aridade json) e §591 (falsos-REDs cross-arch: gates de host só-qemu agora usam o trio as+ld+qemu do #714 e respeitam `KOF_CROSS_PREFIX`) fecharam a pauta. Suíte completa do `lab` medida: **5180 testes / 2F / 661S** — as 2 falhas são corridas de cancelamento do `InteropTimeoutE2ETest` sob carga da suíte, **0F sozinhas** em host ocioso (registrado no §591; frente interop, sem impacto no produto). Jar reconstruído do tip final e **todo o conjunto de goldens re-varrido verde**: CHECK-OK sete pernas JVM+Script, REGCHECK/SHARECHECK/PERSIST-OK JVM+Script, RESUMECHECK-OK, E2E+SEC-E2E-OK, RELAY-OK, TAMPER-OK, HTTPCHECK-OK 28/28 (estado limpo: sobe → semeadura → reinicia → probe), RESTART-OK 6/6, SERVECHECK-OK dois processos.

| Camada | O quê | Prova |
|---|---|---|
| Data plane | transferência chunked 200 KB resume@100000; envelope X25519+HKDF encrypt-then-MAC resume@123456; tamper de 1 byte recusa na tag antes do plaintext | `e2e.kf` → `E2E-OK`+`SEC-E2E-OK` JVM+Script; `probe/tamper.kf` → `TAMPER-OK` |
| Controle | registro devices/offers puro Kof (recusas nomeadas REG001–008) | `control/check.kf` → `REGCHECK-OK` JVM+Script (24/24) |
| HTTP | rotas §4 (`POST/GET /devices[:id]`, `GET/POST/DELETE /offers[:id]`, `/health`) + C2 (`POST/GET /shares`, `GET /s/<token>`, `POST /shares/:id/revoke`) | `httpcheck/checkhttp.kf` → `HTTPCHECK-OK` 21/21 nas 3 combinações JVM/Script servidor×cliente |
| Relay | byte-pump ciphertext-only; flip de 1 byte no relay → tag morre, zero bytes gravados | `relaycheck/checkrelay.kf` → `RELAY-OK` JVM+Script |
| CLI | `server`/`offer`/`up`/`down [--relay]`/`fetch`/`serve [--resume --key --secure --salt --once]`/`relay`/`account`/`--check`/`--dry` | `cli/cli.kf --check` → `registry=true persist=true plain=true secure=true CHECK-OK` JVM+Script |
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

**Plano v1 CONCLUÍDO 04/10.** Track A pousada inteira: A1 persistência (`PERSIST-OK`), A2 ponte SSE/Script (§574 no compilador), A3 resume negotiation (`RESUMECHECK-OK`), A4 expiração de ofertas (`REG010`+purge), A5 `cli serve` device-side (`SERVECHECK-OK` dois processos), A6 cola de fluxo `up`/`down` (`USERCHECK-OK` + laço humano medido: up → SHARE-LINK → serve → down → cmp idêntico). Track B votada e executada: C1 Ed25519 (`D-KOF-SIGN`), C2 modelo de shares (`SHARECHECK-OK`), C3 bearer auth (`HTTPCHECK-OK` 28/28 + `RESTART-OK` 6/6). Lado compilador: §583/§588/§590/§591 pousados; suíte completa do `lab` medida 5180/2F/0E/661S com as 2F = races de carga do `InteropTimeoutE2ETest` (0F solo; condição registrada da frente interop).

O que resta no plano original está ADIADO POR VOTO e exige reabertura da mantenedora para ser retomado: (4) seleção automática de caminho local→ICE→relay (D4=A: relay fica manual `--relay` em v1); (5) destinatário no browser (D5=A: cliente CLI é o destinatário em v1; exige `kof.net`/`keyExchange` no JS, hoje recusados por nome `NETN001`/`SECN012`); (6) pastas como coleção lógica (D6=A: só arquivos em v1). Fora de escopo declarado: GUI, multi-process persistence, empacotamento CI além de `kof.toml`.

Sem tarefa pendente nesta lane além da cadência (`D-RELEASE-CADENCE`, lado repo). Se nada for reaberto, o produto está prontos-para-uso em v1 e a lane segue para onde a mantenedora apontar.


---

# English

Ready & measured at this tip: data plane (plain+sealed envelope transfer, tamper-refused), control plane (registry+HTTP, refused-by-name; A1 persistence with corrupt-refusal REG009), C2 share model — full bearer grants (64-hex token, expiresAt, maxUses/--once, readOnly, revocation, REG030–REG041 named refusals) signed with the persisted control Ed25519 key (C1: `D-KOF-SIGN` landed in Kof4j — `crypto.sign`/`verify` JVM+Script, `SECN013` named gap on JS/Native/cross), ciphertext-only relay, full CLI (`--check` → `CHECK-OK` JVM+Script with six legs: `registry persist plain secure share auth`), packaging. Proofs: `SHARECHECK-OK` 22/22 JVM+Script, `HTTPCHECK-OK` 28/28 marker-gated (live `/shares`, `/s/<token>`, revoke, C3 bearer matrix incl. runtime-401 on tampered Authorization), `RESTART-OK` 6/6 (shares+devices+key+accounts+bearer reload from disk; revoked account stays dead after restart). C3 landed same day (vote D3=B, implemented on the runtime's native JWT layer — `auth.secret`/`auth.authenticated`/`auth.claims`, control secret minted by `security.apiKeyGenerate`). A4 registry hygiene landed same day; A5 device-side `cli serve` landed same day (closes the missing operational leg: device serves ONE transfer session plain/sealed, single-session-by-design, SERVE-LISTENING sync line; golden `servecheck/checkserve.kf` → `SERVECHECK-OK` proves plain resume from .part, secure resume, and oversize refusal across TWO REAL PROCESSES). (offer `createdAt` stamped server-side — client wire is the separate `OfferRequest`, `REG010` unstamped refusal, `controlPurgeExpired` drops stale-by-age + dangling-by-device at boot, logged not silent; the plan's 'OfferInfo unchanged' was measured impossible for time-expiry and the deviation is recorded in next-plan). Gaps left vs the original spec: automatic path selection (relay manual by vote D4=A), browser recipient (NETN001/SECN012 pinned, vote D5=A), directories (vote D6=A deferred), resume negotiation (A3 planned). The two compiler bugs found while landing C2 are now CLOSED in Kof4j: §583 fixed 03/10 (root was `json.decode<T>` typing UNKNOWN on the SEM analyzer while the emit knew T — SEM012 was skipped and the JVM died VerifyError at first dispatch; the analyzer now mirrors the emit's json branch, `JsonDecodeLongAssignE2ETest` 3/3 — the product's typed-Long form remains correct and runs green on the rebuilt jar) and §582 fixed the same day (bare packaged-record ctor in imported bodies). Validate with the commands above; see `docs/next-plan.md`.

Compiler-side (Kof4j), 04/10: the §583 `json.decode<T>` analyzer leak is FIXED upstream and its blast radius measured (`NestedMapRecordDecodeE2ETest` modernized to the frozen narrowing law); §588 followed (json arity guard), and §591 closed the last cross-arch false-REDs (qemu-only host gates now take the #714 as+ld+qemu trio and honor `KOF_CROSS_PREFIX`). Kof4j `lab` full suite measured at tip `b211560f1`-lineage: 5180 tests / 2F / 661S — both failures are `InteropTimeoutE2ETest` cancel-task load races, 0F when run solo on an idle host (recorded in §591, interop-front condition, not product-affecting). The product jar was rebuilt from the final tip and the WHOLE golden set re-swept green: CHECK-OK seven legs JVM+Script, REGCHECK/SHARECHECK/PERSIST-OK JVM+Script, RESUMECHECK-OK, E2E+SEC-E2E-OK, RELAY-OK, TAMPER-OK, HTTPCHECK-OK 28/28 (fresh-state flow: boot server → seed → restart → probe), RESTART-OK 6/6, SERVECHECK-OK two-process.

**Next technical step:** plan v1 is COMPLETE (04/10) — Track A landed end-to-end (A1 persistence, A2 Script SSE/WS bridge in the compiler, A3 resume negotiation, A4 offer expiry, A5 device-side `cli serve`, A6 user-flow glue `up`/`down` — `USERCHECK-OK`, human loop measured CLI→grant→digest-verified bytes), Track B voted and landed (C1 Ed25519, C2 share model, C3 bearer auth). Everything left in the original spec is vote-deferred (D4/D5/D6 = A): automatic path selection (local→ICE→relay), browser recipient, folders — reopening any of them needs maintainer sign-off. Declared out of scope: GUI, multi-process persistence, CI packaging. With no task pending, the product is v1-ready and this lane follows the maintainer's next pointer (repo-side release cadence is the only standing item).



