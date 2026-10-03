[English](implementation-plan.md) | [Português](implementation-plan.pt_BR.md)

# KofShare — plano de implementação (o que falta, em fatias)

**Dona:** `192.168.15.15:9092` (lane security/connectors; `D-PLAN-ONE-OWNER` vale para este arquivo também — ele vive no repo do produto, não em `Kof4j/docs/development/`).
**Base:** tip `c7a7946` (transfer core + envelope de sessão, medido `E2E-OK`/`SEC-E2E-OK` JVM+Script, `TAMPER-OK`).
**Lei de escopo:** o produto continua 100% Kof (`D-KOFSHARE-100KOF`) — sem interop, sem shim, sem face inventada do stdlib. Tudo abaixo só pisa em superfícies MEDIDAS do stdlib (âncoras por fatia). O que exigir face nova da linguagem é rule-6 → mantenedora, nunca decisão de agente.

## 0. Pronto vs faltando (medido, não lembrado)

PRONTO (na árvore da base, reverificado com o jar do tip):
* `transfer.kf` — framing `len|index|payload`, resume offset-idempotente, HMAC-SHA256 por chunk sobre AAD hex.
* `protocol.kf` — framing + codec (`headFrame`/`be32`/`recvRaw`/`hexOf`/`tagHex` + codec ASCII/hex); `session.kf` — X25519 efêmero, HELLO (index `1073741822`, pub 64-hex + salt do servidor), chaves direcionais HKDF-SHA256, encrypt-then-MAC sobre o cipher (separado de `handshake.kf` em 03/10).
* `e2e.kf` — perna plain (resume@100000) + perna segura (resume@123456), 200000 B, nos dois alvos.
* `probe/tamper.kf` — tamper antigo + as 5 asserções de envelope.
* `domain.kf` — records + round-trip JSON.

FALTANDO (o control plane inteiro, CLI, divisão de módulos, relay, empacotamento):
1. `control/` — registro de dispositivos + offers sobre HTTP (`architecture.md` §4). Zero código.
2. `cli.kf` — `server` / `offer` / `fetch` com goldens `--check` / `--dry` (§6).
3. ~~`session.kf` / `protocol.kf` — a máquina de estados hoje mora inline em `transfer.kf`/`handshake.kf`; split por responsabilidade (§10).~~ **FEITO 03/10** (ver Fatia 4 POUSADA).
4. ~~Relay fallback — LAN direto funciona no e2e; relay-via-control (ciphertext only, posição MVP do §7) não tem handler.~~ **FEITO 03/10** (ver Fatia 5 POUSADA; `relay.kf` + `relaycheck/checkrelay.kf`).
5. Empacotamento — sem `kof.toml`, sem árvore de produto, sem script de execução.
6. Identidade/confiança de dispositivo — assinatura Ed25519 NÃO é face Kof (só orientação interop-over-JDK) → **rule-6, fora do v1**, registrado como limitação honesta (MITM passivo está morto; MITM ATIVO da troca de chaves não é recusado — posição do envelope v1, dita com todas as letras).

## 1. Âncoras medidas do stdlib (o plano não pode assumir nada além disso)

* `web.app()` → `app.get("/p") { ... }`, `app.post(...)`, `param("id")`, `body()`, `status(code, texto)`, `app.listen(port)` — servidor subprocess + cliente `http` via loopback VERDES em `KofHttpE2ETest` (JVM; servidor compilado e forkado como subprocesso, cliente in-process).
* `http.get/post/put/delete/patch/options/status(url, headers...) -> String` — estável JVM + JS (byte-parity, `learn/stdlib/http.md`); Native parcial (`HTTP002` nas peças ausentes). **Perna Script: AINDA NÃO MEDIDA — a fatia 2 prova ou recusa primeiro.**
* `json.encode` / `json.decode<T>` — golden-provado em `domain.kf` (JVM+Script).
* TCP `kof.net` (`listen/accept/connect/send/receive/close`) — real em JVM, Native x86-64, riscv64/aarch64, JS-host, Script (D-KOF-NET fatias 1–5 + 4b).
* `random.hex(n)`, `crypto.*`, `keyExchange.*` — pousados (base do envelope).
* Recusas honestas já no typer: `NETN001` (net em JS), `SECN012` (keyExchange em JS/Native), `INTEROP009/010` (faces/falhas estrangeiras).

## 2. Fatias (ordem de dependência; cada uma é uma unidade commitável, RED-first)

**Fatia 1 — `control/registry.kf` (domínio puro, zero IO).**
Modelo do registro: dispositivos (`id → {name, addresses, lastSeen}`), offers (`id → {device, path, size, sha256Hex, dicaResume}`), `register/resolve/listOffers/revoke` como funções puras sobre mapas em memória + encoders JSON. Prova: `RegistryE2ETest` — mesma fonte, JVM + Script, golden (registrar 2 dispositivos, criar offer, resolver, revogar, JSON malformado recusado por nome via `catch`). DoD: verde nos dois alvos, zero face inventada, invariantes do `json.decode<T>` testadas.

**Fatia 2 — `control/app.kf` (superfície HTTP sobre o registro).**
`web.app()` com as rotas do contrato §4: `POST /devices` (registro, body — v1 é LAN-trust), `GET /devices/:id`, `GET /offers?device=`, `POST /offers`, `DELETE /offers/:id`, `GET /health`. Handlers mutam SÓ o registro em memória (processo único; persistência = fatia 5 keystore ou recusa honesta). Prova: `ControlPlaneE2ETest` copiando o harness do `KofHttpE2ETest` (subprocesso servidor + cliente `http.get/post` via loopback, JVM) **mais a primeira medição de `http`+`web` sob `--target script`** — se o Script recusar, a recusa fica registrada aqui por nome e a perna Script cai honesta (R6: medido, não assumido). DoD: golden register→offer→resolve→fetch-metadata; 404/400 recusados por nome.

**POUSADA 02/10 (`control/app.kf` + `server/server.kf` + `httpcheck/checkhttp.kf`):** 14/14 golden true + `HTTPCHECK-OK` nas TRÊS combinações — servidor JVM+cliente JVM, servidor SCRIPT+cliente JVM, servidor JVM+cliente SCRIPT. A primeira medição Script falhou (`HTTP 500` em cada handler interpretado — a fatia o pinou honestamente como §574 no Kof4j por ~1h) e no mesmo dia o fix pousou: ponte `InterpretedCallable` no interpretador (`ScriptWebRouteE2ETest` RED-first) — é por isso que as pernas Script estão verdes agora. Notas de design registradas: servidor = processo próprio (`listen` bloqueia; parar = ciclo de vida do processo) depois que o experimento `/shutdown` esbarrou no **§575 ABERTO** do Kof4j (um closure que captura o handle fantasma do `web.app()` materializa `Lkof/web/App;` como campo do lambda → `NoClassDefFoundError` no LOAD do JVM; as rotas daqui capturam só os mapas do registro). Forma da prova: o golden vive no produto (`checkhttp.kf`, mesmo padrão do `e2e.kf`) em vez de um clone `ControlPlaneE2ETest` no Kof4j — evidência idêntica, menos repos.

**Fatia 3 — `cli.kf` (entrada do produto).**
`main(args)`: `server` (control+registry + serve offers), `offer <arquivo>`, `fetch <offerId|url> <dest> [--resume]`, `--check` (golden completo: sobe o registro in-process, register/offer/resolve, roda as pernas do envelope e2e via `kof.net` loopback, imprime `CHECK-OK`), `--dry` (imprime o plano resolvido, sem IO). Args via `String[] args`; bodies JSON via `json`. Prova: teste de transcript golden da CLI (mesmo padrão das instruções do `e2e.kf`; saída byte-idêntica JVM+Script onde as faces são reais). DoD: `--check` é o comando único que a mantenedora roda para ver o produto inteiro verde; recusas nomeadas.

**POUSADA 03/10 (`cli/cli.kf`, pacote `kofshare.cli`):** a entrada do produto é real em JVM+Script. `--check` imprime `registry=true plain=true secure=true` e então `CHECK-OK` nos DOIS alvos (perna do registro puro + perna de transferência simples resume@100000 + perna do envelope seguro X25519/HKDF resume@123456, loopback `kof.net` real). `offer <arquivo>` imprime o JSON `OfferInfo` com digest de CONTEÚDO real (`crypto.sha256Bytes` sobre os bytes do arquivo — `ba7816…` para `abc`, provado JVM==Script); `fetch <host> <porta> <dest> [--resume] [--key <hex>]` puxa via `kof.net` e foi medido byte a byte idêntico (5000 B) direto E retomando de um `.part` de 2000 B (`offset=5000/5000`, `cmp` limpo); `--dry` imprime o plano sem IO. As recusas são nomeadas (`OFFER-ERR`, `FETCH-ERR`, `DRY-ERR`, `CHECK-FAIL`) e `main` lança em falha (exit ≠ 0), já que `Int main()` foi removido (Kof `SEM044`). **Divergências honestas registradas:** (a) o `resumeOffsetHint` do §2 NÃO está no `OfferInfo` pousado (`id/deviceId/path/size/sha256Hex`); o offset de retomada é coordenado fora de banda, então um `--resume` puro continua do tamanho do `.part` existente e o PEER precisa `serveFile` do mesmo offset — uma negociação de offset em pleno transfer NÃO está implementada (escopo do relay, fatia 5; documentado, não silencioso). (b) o módulo impõe UM `main()` por pacote, então a entrada mora no subpacote próprio `kofshare.cli` (um `kofshare/cli.kf` na raiz colide `PKG002` com o `main` do `e2e.kf`). (c) `File.size()` é método, não propriedade (`SEM102`).

**Fatia 4 — extração `session.kf`/`protocol.kf` (sem mudança de comportamento).**
Mover a máquina de estados do envelope (HELLO/chaves/frames) de `transfer.kf`/`handshake.kf` para `protocol.kf` (framing + codec) e `session.kf` (handshake + chaves + send/receive selado), por responsabilidade única (§10); `e2e.kf`/`probe/tamper.kf` ficam com os MESMOS goldens byte a byte — essa é a prova do refactor. DoD: todos os goldens existentes verdes nos dois alvos + diff do refactor sem nenhuma face semântica nova.

**POUSADA 03/10 (`protocol.kf` + `session.kf`; `handshake.kf` removido).** O `protocol.kf` agora é dono dos helpers puros de wire (`metaIndex`/`chunkSize`/`tagLen`, `headFrame`/`be32`/`concatBytes`/`recvRaw`, `hexOf`/`tagHex`, `helloIndex` + o codec ASCII/hex), e o `session.kf` é dono da máquina de estados selada (`helloFrame`/`helloBody`/`sessionKeys`/`wrapChunk`/`unwrapChunk`/`readHello`/`serveFileSecure`/`fetchHandshake`/`serveLoopEncrypted`/`fetchFileSecure`). O `transfer.kf` agora é só a máquina de estados simples (`serveFile`/`fetchFile`) mais os helpers de oracle de bytes. Arestas de import atualizadas (`e2e.kf`/`cli.kf` → `session`, `probe/tamper.kf` → `protocol`+`session`). **Prova (byte a byte idêntica ao baseline pré-refactor):** `e2e.kf` JVM **e** Script → `SEC-E2E-OK` + `E2E-OK` com o mesmo `len=200000/200000 sum=25499232/25499232 mismatch=-1 done=true offset=200000/200000`; `probe/tamper.kf` JVM → `TAMPER-OK` (todas as recusas do envelope true); `cli --check` JVM **e** Script → `registry=true plain=true secure=true` + `CHECK-OK`. Nenhuma face semântica nova; a única mudança de forma é a comparação de tag agora `asciiOf(tag) != tagHex(...)` (equivalente ao laço byte a byte antigo, provado pelo golden do tamper).

**Fatia 5 — relay fallback (LAN direto primeiro, relay ciphertext-only).**
`fetch` tenta `connect(deviceAddr)`; na recusa cai no relay do host de controle: frames opacos encaminhados byte a byte entre as duas conexões TCP dos peers (o controle nunca vê plaintext — o envelope já cifra o transporte). Prova: `RelayE2ETest` — dois peers + relay, os três sockets em loopback com portas distintas, golden igual à saída do caminho direto; tamper-no-relay recusado (relay virando 1 byte = morte pela tag do envelope; reusa as asserções do `probe/tamper.kf` na perna relayeada). DoD: statement honesto de que traversal ≠ hole-punching (STUN/ICE = pós-MVP, arquitetura §7).

**POUSADA 03/10 (`relay.kf` + `relaycheck/checkrelay.kf`).** O relay é um pump de bytes agnóstico de framing (`relayPump`/`relayPumpTamper` + `relayServeOn`/`relayServeTamperOn`/`relayServe`): encaminha bytes opacos entre o cliente e o peer e nunca parseia cabeçalhos do `protocol.kf`, então não pode inspecionar nem reescrever payload. Fecha o destino no EOF da origem (propaga o half-close) e trata leitura/envio num socket já fechado pela direção irmã como fim-de-stream, então o relay não morre quando um lado desliga. Prova (`checkrelay.kf`, JVM **e** Script → `RELAY-OK`): `direct=true` (baseline seguro), `relayed=true` (cliente → relay → peer, byte a byte idêntico 200000 B com resume@100000), `tamperRefused=true` (o relay vira o byte de ciphertext no offset absoluto 300 → a tag do envelope recusa e **nada é anexado**, `out.size == resume`). Ligação na CLI: `fetch ... [--secure] [--relay <rhost> <rport>]` e um comando `relay <port> <peerHost> <peerPort> [--tamper]`; medido ponta-a-ponta pela CLI (`fetch --relay --secure` → `FETCH-OK offset=5000/5000`, relay loga `RELAY-READY`). **Divergência honesta:** a CLI não auto-detecta recusa de conexão direta e cai automaticamente — o operador escolhe `--relay` explicitamente (o "tenta direto e cai" do plano existe como `relay`/`--relay`; um catch-and-retry automático exigiria distinguir recusa de connect de falha em meio handshake, adiado com o trabalho de STUN/ICE). Traversal ≠ hole-punching: sem STUN/ICE, sem promessa de NAT punching (arquitetura §7).

**Fatia 6 — empacotamento + docs.**
`kof.toml` (entradas de módulo `server`/`cli`), instruções de execução do `README` atualizadas para a CLI, árvore do §10 da `architecture.md` marcada LANDED por fatia com as recusas medidas, esta linha STATUS por fatia neste plano. DoD: clone novo → `java -jar kof-cli.jar run cli.kf -- --check` verde; paridade EN+PT estilo docs-lang nos docs deste repo.

**POUSADA 03/10 (`kof.toml` + docs).** O `kof.toml` declara `[project] name = "kof-share"`, `[backend] target = "jvm"` e `[sources] app = "src/main/kof"` — o manifesto que o `ProjectLocator` da CLI lê; o `--target` explícito na linha de comando ainda sobrepõe o backend target, e o `--check` segue verde em JVM e Script com o manifesto presente. A `architecture.md` §10 agora mostra a árvore real pousada (uma responsabilidade por arquivo; a nota `PKG002` de um-`main()`-por-pacote), e §3/§5/§7 carregam o relay da fatia 5. As instruções de execução do README cobrem a CLI, o relay e o manifesto.

**STATUS por fatia:** 1 registro POUSADA · 2 control plane POUSADA · 3 CLI POUSADA · 4 split protocol/session POUSADA · 5 relay POUSADA · 6 empacotamento POUSADA. Todas as seis fatias do plano KofShare autorizado estão pousadas; os itens rule-6 restantes estão no §3 (identidade/Ed25519, hole-punching, alvos de produto JS/Native).

## 3. Fora de escopo / rule-6 (não implementar sem decisão)

* Identidade & confiança de dispositivo (face Ed25519, certificados, TOFU) — nenhuma face no stdlib; o envelope v1 segue com a limitação documentada.
* Hole-punching / NAT traversal além do relay — §7 pós-MVP.
* Alvos JS/Native do produto — bloqueados por `SECN012`/`NETN001` (faces decididas fora do v1; medição, não suposição).

## 3.1 Continuação do fora de escopo

* Qualquer face nova da linguagem descoberta no meio de uma fatia → PARE + pergunta rule-6 (como `D-INTEROP-ERR-TYPE` foi), nunca contorno local no produto.

## 4. Disciplina de verificação (toda fatia)

RED-first (teste antes do código); goldens JVM+Script para faces reais; recusas nomeadas para todo o resto; `probe/tamper.kf` e as duas pernas do e2e re-rodadas ao fim de cada fatia (piso de regressão); commit por fatia com números medidos; nenhuma afirmação sobre alvo que não foi executado.
