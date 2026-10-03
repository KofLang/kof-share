[English](next-plan.md) | [Português](next-plan.pt_BR.md)

# KofShare — o que falta (em fatias)

**Dona:** `192.168.15.15:9092` (lane segurança/conectores; `D-PLAN-ONE-OWNER` se aplica).
**Estado do plano anterior:** `implementation-plan.md` está COMPLETO (as 6 fatias pousaram; `--check` → `CHECK-OK` JVM+Script no tip `b6596ef`). Este arquivo é o sucessor: o que resta, em ordem de dependência, dividido entre (A) trabalho que NÃO precisa de decisão e (B) itens regra-6 que precisam primeiro do voto da mantenedora.
**Lei de escopo:** o produto segue 100% Kof (`D-KOFSHARE-100KOF`) — sem interop, sem shims, sem face inventada do stdlib sem regra-6. Toda afirmação abaixo foi MEDIDA neste tip (03/10), não lembrada.

## 0. Estado medido das bordas que este plano toca

* `crypto` hoje: `sha256`/`sha256Bytes`, HMAC, `keyExchange` (X25519, D-KOF-X25519). **`grep -rli ed25519` em `kof-compiler/src/main/java` = ZERO** — não existe nenhuma face de assinatura (B1 está genuinamente ausente, não escondida).
* `InterpretedCallable` expõe só `invoke()` e `invoke(String×5)` (rotas HTTP). O runtime também reflete `invoke(SseConnection)` (SSE) e handlers de mensagem WS — a ponte Script desses NÃO está feita (A2; a nota de escopo do §574 diz o mesmo).
* As faces de persistência existem e são medidas: `File.readText()`/`File.writeText(s)` nas formas de instância (D-FILE-STATIC mantém os braços estáticos desligados). `json.encode(record)`/`json.decode<T>` funcionam em records empacotados (§573 corrigido; a perna de registro do `--check` usa isso).
* A CLI não tem NEGOCIAÇÃO de resume em voo: `fetch ... --resume` continua a partir do tamanho do `.part` local e o peer precisa `serveFile` do mesmo offset; `OfferInfo` não tem o campo `resumeOffsetHint` (medido: ausente no tip).

## 1. Trilha A — sem decisão necessária (faces Kof já existem)

**Fatia A1 — persistência do registro (não esquece no crash).**
`control/registry.kf` ganha `saveRegistry(path)` / `loadRegistry(path)`: `json.encode` dos mapas de devices+offers (chaves ordenadas mantêm goldens estáveis), escrita quase-atômica via arquivo temporário + rename usando só as faces medidas de `file`/`path`; arquivo corrompido → recusa nomeada `REG009`, nunca vazio silencioso. `server.kf` e `cli.kf server` carregam no boot e salvam após toda mutação bem-sucedida. Prova: golden `checkpersist.kf` (JVM+Script): registra 2 devices + 2 offers → save → load novo → listagens byte-idênticas + asserções `RESOLVE-SAME`; vira 1 byte do arquivo → `REG009`. DoD: `--check` estendido com a perna de persistência (`persist=true`). **POUSADA 03/10:** `persistcheck/checkpersist.kf` → `PERSIST-OK` 9/9 no JVM E no Script (save/reload com listagens byte-idênticas, `REG009` em corrompido, vazio em ausente); servidor + `cli server` carregam no boot e salvam após cada mutação bem-sucedida (`SERVER-READY … devices=N`); sonda de restart medida: processo novo serve os 2 devices do disco. A perna no `--check` é a metade restante do DoD (registrada abaixo).

**Fatia A2 — ponte SSE/WS no Script (residual do §574).**. **POUSADA 03/10** (Kof4j `ScriptSseWsE2ETest` 1/1; o produto ganha paridade de alvo — handlers interpretados recebem conexões SSE; nenhum código do produto é necessário).
Lado Kof4j (lane compiler): `InterpretedCallable` ganha os formatos de handler que o runtime reflete para SSE (`invoke(SseConnection)`) e mensagens WS, delegando ao `invokeLambda` exatamente como os braços HTTP; handlers interpretados recebem o objeto de conexão do mesmo modo que os compilados. Prova: irmã RED-first do `ScriptWebRouteE2ETest` (SSE send-through + eco WS sobre loopback sob `--target script`). DoD: a nota "SSE/WS não coberto" do §574 é aposentada; nenhum código KofShare é necessário (o produto ganha a capacidade por paridade de alvo). **Fronteira:** se o handshake WS sob interpretação esbarrar num gap mais fundo do interpretador, registrar a recusa por nome (R6) em vez de forçar — a divisão HTTP/SSE é uma unidade commitável.

**Fatia A3 — negociação honesta de resume.**
O servidor (caminho `serveFile`) já atende um offset escolhido pelo cliente; tornar explícito: `fetch --resume` envia o tamanho do `.part` local na troca HELLO/meta e o SERVIDOR verifica (≤ tamanho) e serve daquele ponto — um offset errado recusa por nome (`RESUME-ERR: server file shorter than requested offset`) em vez de corromper. `resumeOffsetHint` NÃO entra em `OfferInfo` (a oferta descreve o arquivo, não uma sessão). Prova: golden — arquivo de 5000 B, `.part` de 2000 → `offset=5000/5000` + `cmp` limpo (já medido, agora afirmado pela negociação) + o caso de recusa (hint > size). DoD: a nota de divergência do plano-v1 "peer coopera fora-de-faixa" é aposentada.

**Fatia A4 — expiração de ofertas + higiene do registro (barato, puro).**
`OfferInfo` inalterado; o registro ganha a função pura `purgeExpired(nowMs, ttlMs)` + a listagem `/offers` já ordenada; o servidor chama no boot e após mutações. Prova: linhas puras no golden `check.kf` (JVM+Script). DoD: recusa nomeada `REG010` só onde necessário (nunca comportamento silencioso).

## 2. Trilha B — mantenedora VOTOU 03/10 (chat): D1=A · D2=A · D3=B · D4=A · D5=A · D6=A

**B1 → C1 — identidade do dispositivo + assinatura de ofertas. VOTADO A — face aprovada.**
O buraco de confiança do v1: qualquer um registra um device e alega qualquer caminho. O stdlib pousado tem troca de chaves X25519 (`D-KOF-X25519`) mas NENHUMA face de assinatura (medido: zero Ed25519 em qualquer lugar). Uma assinatura 100%-Kof exige uma face nova do stdlib (proposta: `crypto.sign`/`crypto.verify` sobre `Byte[]` + tratamento de `KeyPair` em `Secret`, JVM primeiro; recusas honestas JS/Native na família `SECN012`). **Registrado:** o voto virou `D-KOF-SIGN` no Kof4j (DECISIONS EN+PT) — contrato proposto congelado para implementação: `sign(Secret, Byte[]) -> Byte[]`, `verify(Secret, Byte[], Byte[]) -> Bool`, export da pública raw-32-hex, JS/Native com recusa nomeada `SECN013`. A fatia C1 vive na lane compiler do Kof4j (RED-first como toda face).

**B2 — travessia de NAT. VOTADO A — relay continua manual `--relay` no v1; ICE-lite adiado.**
O relay cobre "ambos os peers alcançáveis pelo host de controle"; NÃO cobre dois peers atrás de NATs separados sem portas inbound. O hole-punching puro exige rendezvous UDP + open simultâneo cronometrado + o relay como fallback-do-fallback — todas as faces UDP de `kof.net` EXISTEM e são medidas (fatia 5 do plano de rede). Nenhuma decisão de stdlib é necessária para TENTAR um ICE-lite em Kof, mas a arquitetura chama o hole-punching de pós-MVP (arquitetura §7), então ele aparece aqui como escolha de ESCOPO da mantenedora, não de faces. **Decisão pedida:** agendar uma fatia ICE-lite (Kof puro, sem face nova) ou manter travessia = só relay.

**B3 — alvos JS/Native do produto. VOTADO A — destinatário segue CLI no v1; browser adiado.**
`kof.net` em JS recusado no compile (`NETN001`, emenda `D-KOF-NET`), `keyExchange` JS/Native recusado (`SECN012`); ambas são recusas honestas e pinadas. O produto v1 = servidor JVM + peers Script/JVM. **Decisão pedida:** nenhuma para ficar como está; reabrir só se a mantenedora quiser peers no browser (exige consertar as duas recusas primeiro) ou um appliance Native headless.

## 3. Fora deste plano (explícito)

* Qualquer GUI/desktop (fora do escopo autorizado).
* Persistência multiprocesso (um escritor assumido; a face de file lock existe mas a A1 fica sem lock por design: um processo servidor é dono do arquivo).
* Empacotamento upstream/CI além do `kof.toml` (fatia 6 pousada) — o protocolo de release é do repo, não deste plano.

## 4. Ordem e cadência

Pousado: **A1 persistência** (`PERSIST-OK` ×2 + sonda de restart); **C1 face Ed25519** no Kof4j (contrato congelado `D-KOF-SIGN`: `crypto.sign/verify` sobre `Secret`+`Byte[]`, hex da casa, gap nomeado SECN013, `CryptoSignE2ETest` 3/3); **C2 modelo `share.kf` completo** (token = `security.randomHex(32)`, `expiresAt`/`maxUses`/`--once`/`readOnly`/revogação, gate `GET /s/<token>` via `shareTouch` — só `OK` serve metadados — recusas REG030–REG041, expiração A4 dobrada via `sharesPurgeExpired`; goldens `SHARECHECK-OK` 22/22 JVM+Script + `HTTPCHECK-OK` 21/21 ao vivo + `RESTART-OK`; o produto achou + corrigiu o bug de ctor empacotado §582 e registrou o bug vivo §583 com a forma honesta typed-Long embarcada). Depois, em ordem: **A2** ponte SSE/WS — POUSADA 03/10 (`ScriptSseWsE2ETest` 1/1: `app.sse` interpretado transmite por socket real; `app.ws` interpretado completa handshake 101 + eco; linha de escopo do §574 aposentada) → **C3** bearer auth — LANDED 03/10 (voto D3=B; implementada na camada JWT nativa do runtime: segredo de controle mintado via `security.apiKeyGenerate` + `auth.secret`, bearer = JWT assinado `{sub,name,roles}`, gate por requisição `auth.authenticated()` + checagem na tabela (AUTH001–AUTH006, AUTH043 arquivo corrompido; Authorization violada recebe o 401 medido do runtime antes do handler); auto-inscrição só com tabela vazia; goldens `HTTPCHECK-OK` 28/28 com marcador gateado + `RESTART-OK` 6/6 com revogação sobrevivendo ao restart) → **A3** resume negotiation. `--check` acumula uma perna por fatia pousada (agora seis: `registry persist plain secure share` todas verdadeiras). B2/B3 ficam votado-A (relay manual, destinatário CLI).
