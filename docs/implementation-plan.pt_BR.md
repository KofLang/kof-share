[English](implementation-plan.md) | [Português](implementation-plan.pt_BR.md)

# KofShare — plano de implementação (o que falta, em fatias)

**Dona:** `192.168.15.15:9092` (lane security/connectors; `D-PLAN-ONE-OWNER` vale para este arquivo também — ele vive no repo do produto, não em `Kof4j/docs/development/`).
**Base:** tip `c7a7946` (transfer core + envelope de sessão, medido `E2E-OK`/`SEC-E2E-OK` JVM+Script, `TAMPER-OK`).
**Lei de escopo:** o produto continua 100% Kof (`D-KOFSHARE-100KOF`) — sem interop, sem shim, sem face inventada do stdlib. Tudo abaixo só pisa em superfícies MEDIDAS do stdlib (âncoras por fatia). O que exigir face nova da linguagem é rule-6 → mantenedora, nunca decisão de agente.

## 0. Pronto vs faltando (medido, não lembrado)

PRONTO (na árvore da base, reverificado com o jar do tip):
* `transfer.kf` — framing `len|index|payload`, resume offset-idempotente, HMAC-SHA256 por chunk sobre AAD hex.
* `handshake.kf` — X25519 efêmero, HELLO (index `1073741822`, pub 64-hex + salt do servidor), chaves direcionais HKDF-SHA256, encrypt-then-MAC sobre o cipher.
* `e2e.kf` — perna plain (resume@100000) + perna segura (resume@123456), 200000 B, nos dois alvos.
* `probe/tamper.kf` — tamper antigo + as 5 asserções de envelope.
* `domain.kf` — records + round-trip JSON.

FALTANDO (o control plane inteiro, CLI, divisão de módulos, relay, empacotamento):
1. `control/` — registro de dispositivos + offers sobre HTTP (`architecture.md` §4). Zero código.
2. `cli.kf` — `server` / `offer` / `fetch` com goldens `--check` / `--dry` (§6).
3. `session.kf` / `protocol.kf` — a máquina de estados hoje mora inline em `transfer.kf`/`handshake.kf`; split por responsabilidade (§10).
4. Relay fallback — LAN direto funciona no e2e; relay-via-control (ciphertext only, posição MVP do §7) não tem handler.
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

**POUSADA 02/10 (`control/app.kf` + `httpcheck/checkhttp.kf`):** 14/14 golden true + `HTTPCHECK-OK` no JVM (health, registro, recusas REG001/REG004 como bodies HTTP, resolve achado/ghost, lista de offers + query `?device=`, revogação, revogação de ghost). Perna Script MEDIDA: o servidor do interpretador binda e aceita, mas cada handler de rota responde `HTTP 500` — causa-raiz confirmada no código (reflexão host `invoke` sobre um closure `KofObj` interpretado, sem método host; `JvmRuntimeWebDispatch.kof_web_invoke` do Kof4j), rastreado como `known-bugs` §574 ABERTO no Kof4j. Forma da prova: o golden vive no produto (`checkhttp.kf`, mesmo padrão do `e2e.kf`) em vez de um clone `ControlPlaneE2ETest` no Kof4j — evidência idêntica, menos repos.

**Fatia 3 — `cli.kf` (entrada do produto).**
`main(args)`: `server` (control+registry + serve offers), `offer <arquivo>`, `fetch <offerId|url> <dest> [--resume]`, `--check` (golden completo: sobe o registro in-process, register/offer/resolve, roda as pernas do envelope e2e via `kof.net` loopback, imprime `CHECK-OK`), `--dry` (imprime o plano resolvido, sem IO). Args via `String[] args`; bodies JSON via `json`. Prova: teste de transcript golden da CLI (mesmo padrão das instruções do `e2e.kf`; saída byte-idêntica JVM+Script onde as faces são reais). DoD: `--check` é o comando único que a mantenedora roda para ver o produto inteiro verde; recusas nomeadas.

**Fatia 4 — extração `session.kf`/`protocol.kf` (sem mudança de comportamento).**
Mover a máquina de estados do envelope (HELLO/chaves/frames) de `transfer.kf`/`handshake.kf` para `protocol.kf` (framing + codec) e `session.kf` (handshake + chaves + send/receive selado), por responsabilidade única (§10); `e2e.kf`/`probe/tamper.kf` ficam com os MESMOS goldens byte a byte — essa é a prova do refactor. DoD: todos os goldens existentes verdes nos dois alvos + diff do refactor sem nenhuma face semântica nova.

**Fatia 5 — relay fallback (LAN direto primeiro, relay ciphertext-only).**
`fetch` tenta `connect(deviceAddr)`; na recusa cai no relay do host de controle: frames opacos encaminhados byte a byte entre as duas conexões TCP dos peers (o controle nunca vê plaintext — o envelope já cifra o transporte). Prova: `RelayE2ETest` — dois peers + relay, os três sockets em loopback com portas distintas, golden igual à saída do caminho direto; tamper-no-relay recusado (relay virando 1 byte = morte pela tag do envelope; reusa as asserções do `probe/tamper.kf` na perna relayeada). DoD: statement honesto de que traversal ≠ hole-punching (STUN/ICE = pós-MVP, arquitetura §7).

**Fatia 6 — empacotamento + docs.**
`kof.toml` (entradas de módulo `server`/`cli`), instruções de execução do `README` atualizadas para a CLI, árvore do §10 da `architecture.md` marcada LANDED por fatia com as recusas medidas, esta linha STATUS por fatia neste plano. DoD: clone novo → `java -jar kof-cli.jar run cli.kf -- --check` verde; paridade EN+PT estilo docs-lang nos docs deste repo.

## 3. Fora de escopo / rule-6 (não implementar sem decisão)

* Identidade & confiança de dispositivo (face Ed25519, certificados, TOFU) — nenhuma face no stdlib; o envelope v1 segue com a limitação documentada.
* Hole-punching / NAT traversal além do relay — §7 pós-MVP.
* Alvos JS/Native do produto — bloqueados por `SECN012`/`NETN001` (faces decididas fora do v1; medição, não suposição).

## 3.1 Continuação do fora de escopo

* Qualquer face nova da linguagem descoberta no meio de uma fatia → PARE + pergunta rule-6 (como `D-INTEROP-ERR-TYPE` foi), nunca contorno local no produto.

## 4. Disciplina de verificação (toda fatia)

RED-first (teste antes do código); goldens JVM+Script para faces reais; recusas nomeadas para todo o resto; `probe/tamper.kf` e as duas pernas do e2e re-rodadas ao fim de cada fatia (piso de regressão); commit por fatia com números medidos; nenhuma afirmação sobre alvo que não foi executado.
