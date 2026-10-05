[English](next-plan.md) | [Português](next-plan.pt_BR.md)

# KofShare — o que falta (em fatias)

**Dona:** `192.168.15.15:9092` (lane segurança/conectores; `D-PLAN-ONE-OWNER` se aplica).
**Estado do plano anterior:** `implementation-plan.md` está COMPLETO (as 6 fatias pousaram; `--check` → `CHECK-OK` JVM+Script no tip `b6596ef`). Este arquivo é o sucessor: o que resta, em ordem de dependência, dividido entre (A) trabalho que NÃO precisa de decisão e (B) itens regra-6 que precisam primeiro do voto da mantenedora.
**Lei de escopo:** o produto segue 100% Kof (`D-KOFSHARE-100KOF`) — sem interop, sem shims, sem face inventada do stdlib sem regra-6. Toda afirmação abaixo foi MEDIDA neste tip (03/10), não lembrada.

## 0. Estado medido das bordas que este plano toca

* `crypto` hoje: `sha256`/`sha256Bytes`, HMAC, `keyExchange` (X25519, D-KOF-X25519). **`grep -rli ed25519` em `kof-compiler/src/main/java` = ZERO** — não existe nenhuma face de assinatura (B1 está genuinamente ausente, não escondida).
* `InterpretedCallable` expõe só `invoke()` e `invoke(String×5)` (rotas HTTP). O runtime também reflete `invoke(SseConnection)` (SSE) e handlers de mensagem WS — a ponte Script desses NÃO está feita (A2; a nota de escopo do §574 diz o mesmo).
* As faces de persistência existem e são medidas: `File.readText()`/`File.writeText(s)` nas formas de instância (D-FILE-STATIC mantém os braços estáticos desligados). `json.encode(record)`/`json.decode<T>` funcionam em records empacotados (§573 corrigido; a perna de registro do `--check` usa isso).
* ~~A CLI não tem NEGOCIAÇÃO de resume em meia transferência~~ — RESOLVIDO por A3 03/10: o tamanho do `.part` agora cruza in-band num head HELLO e o servidor o verifica (recusas `RESUME-ERR`); `OfferInfo` deliberadamente não carrega campo de sessão.

## 1. Trilha A — sem decisão necessária (faces Kof já existem)

**Fatia A1 — persistência do registro (não esquece no crash).**
`control/registry.kf` ganha `saveRegistry(path)` / `loadRegistry(path)`: `json.encode` dos mapas de devices+offers (chaves ordenadas mantêm goldens estáveis), escrita quase-atômica via arquivo temporário + rename usando só as faces medidas de `file`/`path`; arquivo corrompido → recusa nomeada `REG009`, nunca vazio silencioso. `server.kf` e `cli.kf server` carregam no boot e salvam após toda mutação bem-sucedida. Prova: golden `checkpersist.kf` (JVM+Script): registra 2 devices + 2 offers → save → load novo → listagens byte-idênticas + asserções `RESOLVE-SAME`; vira 1 byte do arquivo → `REG009`. DoD: `--check` estendido com a perna de persistência (`persist=true`). **POUSADA 03/10:** `persistcheck/checkpersist.kf` → `PERSIST-OK` 9/9 no JVM E no Script (save/reload com listagens byte-idênticas, `REG009` em corrompido, vazio em ausente); servidor + `cli server` carregam no boot e salvam após cada mutação bem-sucedida (`SERVER-READY … devices=N`); sonda de restart medida: processo novo serve os 2 devices do disco. A perna no `--check` é a metade restante do DoD (registrada abaixo).

**Fatia A2 — ponte SSE/WS no Script (residual do §574).**. **POUSADA 03/10** (Kof4j `ScriptSseWsE2ETest` 1/1; o produto ganha paridade de alvo — handlers interpretados recebem conexões SSE; nenhum código do produto é necessário).
Lado Kof4j (lane compiler): `InterpretedCallable` ganha os formatos de handler que o runtime reflete para SSE (`invoke(SseConnection)`) e mensagens WS, delegando ao `invokeLambda` exatamente como os braços HTTP; handlers interpretados recebem o objeto de conexão do mesmo modo que os compilados. Prova: irmã RED-first do `ScriptWebRouteE2ETest` (SSE send-through + eco WS sobre loopback sob `--target script`). DoD: a nota "SSE/WS não coberto" do §574 é aposentada; nenhum código KofShare é necessário (o produto ganha a capacidade por paridade de alvo). **Fronteira:** se o handshake WS sob interpretação esbarrar num gap mais fundo do interpretador, registrar a recusa por nome (R6) em vez de forçar — a divisão HTTP/SSE é uma unidade commitável.

**Fatia A3 — negociação honesta de resume.** POUSADA 03/10 (head HELLO `helloIndex` in-band anuncia o tamanho do `.part` do receptor; `resumeVerify` no SERVIDOR confere contra o tamanho real; recusa viaja como head `resumeErrIndex` e o cliente lança o nome; plain + selado; `resumecheck/checkresume.kf` → `RESUMECHECK-OK`; a nota fora-de-faixa foi aposentada — `OfferInfo` segue sem campo de sessão).
O servidor (caminho `serveFile`) já atende um offset escolhido pelo cliente; tornar explícito: `fetch --resume` envia o tamanho do `.part` local na troca HELLO/meta e o SERVIDOR verifica (≤ tamanho) e serve daquele ponto — um offset errado recusa por nome (`RESUME-ERR: server file shorter than requested offset`) em vez de corromper. `resumeOffsetHint` NÃO entra em `OfferInfo` (a oferta descreve o arquivo, não uma sessão). Prova: golden — arquivo de 5000 B, `.part` de 2000 → `offset=5000/5000` + `cmp` limpo (já medido, agora afirmado pela negociação) + o caso de recusa (hint > size). DoD: a nota de divergência do plano-v1 "peer coopera fora-de-faixa" é aposentada.

**Fatia A5 — `cli serve` do lado do dispositivo (a perna operacional que falta).** POUSADA 03/10. Lacuna medida: `fetch <host> <port>` existe e e2e.kf prova a maquina de estados DENTRO de UM processo (thread com spawn), mas nada no CLI realmente SERVE um arquivo a um fetcher — transferencias entre dois processos reais so eram exercitadas via relay com servidores locais de teste. DoD: `cli serve <path> <port> [--resume <n>] [--key <hex>] [--secure] [--salt <hex>] [--once]` (semantica de sessao unica honesta no help), mais golden JVM de dois processos `servecheck/checkserve.kf` que (1) desanexa um processo serve, espera a linha `SERVE-LISTENING`, (2) fetch plain com resume a partir de um `.part` ATRAVESSANDO a fronteira de processo (negociacao HELLO de A3 provada entre processos REAIS), (3) fetch selado (handshake + envelope) cross-processo, (4) resume maior que o arquivo recusado por nome cross-processo, identidade de bytes assertada; `--check` mantem suas pernas in-processo (spawn threads; Script nao forkar JVM — registrado, o golden carrega a prova multi-processo).

**Fatia A4 — expiração de ofertas + higiene do registro (barato, puro).** POUSADA 03/10. Desvio registrado com honestidade: o plano dizia `OfferInfo` inalterada — impossível para expiração por tempo (não existia carimbo), então `OfferInfo` ganhou `createdAt` e o tipo de WIRE do cliente virou `OfferRequest(id,deviceId,path,size,sha256Hex)` separado (o servidor carimba a frescura ele mesmo; o cliente não pode falsificá-la nem ressuscitar id expirado). `REG010: offer has no registration timestamp` recusa oferta sem carimbo. `controlPurgeExpired(offers, devices, now, ttl)` (puro, chaves ordenadas) descarta ofertas mais velhas que `offerTtlMs()` (24 h) E pendentes-de-dispositivo-inexistente; o servidor chama no boot (purge persistido + linha de log, nunca silencioso). Provas: `REGCHECK-OK` ganhou as linhas `offerNoStamp/purged/purgeKeepsFresh` JVM+Script; `PERSIST-OK`, `HTTPCHECK-OK` 28/28, `RESTART-OK` verdes na nova wire.
`OfferInfo` inalterado; o registro ganha a função pura `purgeExpired(nowMs, ttlMs)` + a listagem `/offers` já ordenada; o servidor chama no boot e após mutações. Prova: linhas puras no golden `check.kf` (JVM+Script). DoD: recusa nomeada `REG010` só onde necessário (nunca comportamento silencioso).

**Fatia A6 — cola de fluxo do usuário (`up`/`down`).** POUSADA 04/10. Lacuna medida: cada verbo do plano existia, mas nenhum comando fechava "instalei o cliente" → "falo com o servidor central" → "recebi um link, baixo": `offer` só imprimia JSON local, `fetch` exigia host/porta passados à mão. `kofshare/userflow.kf`: `upPublish` (POST /devices + /offers na wire `OfferRequest` da A4, com bearer, aceita a gramática `REGISTERED:`/`OFFERED:` do plano) e `downFetch` (GET /s/<token> → decodifica `ShareGrant` → disca o endereço QUE O GRANT CARREGA → resume A3 a partir de qualquer `.part` → verifica o sha256 que a oferta prometeu — `DOWN-ERR: content digest mismatch` por nome, nunca silente). Verbos CLI `up`/`down` finos sobre o módulo; `down --relay <rhost> <rporta>` adicionado no mesmo dia (conclusão D4=A: `fetch` tinha o relay manual, o comando do destinatário não podia carecer dele — overload de 6 args do `downFetch` disca o relay em vez do endereço do grant, A3/tags atravessam o pump de bytes; pernas golden `serveUpRelay`+`downRelay` verdes). `share` já imprimia o `SHARE-LINK http://host:porta/s/<token>` completo. Prova: golden `usercheck/checkuser.kf` → `USERCHECK-OK` (matriz de endereço + boot do plano + publish + mint + `down` cheio + `downResume` + `tamperRefuse`), laço humano real medido ponta a ponta pelos binários CLI (up → SHARED/SHARE-LINK → serve → down → cmp idêntico). Encontrado+corrigido no caminho: `cli server` imprimia `SERVER-READY` ANTES do bind (um READY mentiroso deixava um plano zumbi manter a porta e o bearer novo dar 401 contra o segredo velho — probe de bind + recusa `SERVER-ERR:` agora antecedem o marcador); o golden possui sua faixa de portas deterministicamente via kill-by-pid em `ss -tlnp` depois que `pkill -f` se mostrou não confiável (self-matching em wrappers); `transfer.kf` ganhou o `import kofshare.session` explícito que seu uso de `tagBytes` sempre precisou (21/21→23/23 arquivos check-clean isolados).

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

Pousado: **A1 persistência** (`PERSIST-OK` ×2 + sonda de restart); **C1 face Ed25519** no Kof4j (contrato congelado `D-KOF-SIGN`: `crypto.sign/verify` sobre `Secret`+`Byte[]`, hex da casa, gap nomeado SECN013, `CryptoSignE2ETest` 3/3); **C2 modelo `share.kf` completo** (token = `security.randomHex(32)`, `expiresAt`/`maxUses`/`--once`/`readOnly`/revogação, gate `GET /s/<token>` via `shareTouch` — só `OK` serve metadados — recusas REG030–REG041, expiração A4 dobrada via `sharesPurgeExpired`; goldens `SHARECHECK-OK` 22/22 JVM+Script + `HTTPCHECK-OK` 21/21 ao vivo + `RESTART-OK`; o produto achou + corrigiu o bug de ctor empacotado §582 e registrou o bug vivo §583 — depois CONSERTADO no compilador 03/10 (`json.decode<T>` chegava UNKNOWN ao analisador SEM enquanto o emit conhecia T — SEM012 pulado → VerifyError no dispatch; o analisador agora espelha o emit, `JsonDecodeLongAssignE2ETest` 3/3; a forma typed-Long do produto segue correta de qualquer jeito)). Depois, em ordem: **A2** ponte SSE/WS — POUSADA 03/10 (`ScriptSseWsE2ETest` 1/1: `app.sse` interpretado transmite por socket real; `app.ws` interpretado completa handshake 101 + eco; linha de escopo do §574 aposentada) → **C3** bearer auth — LANDED 03/10 (voto D3=B; implementada na camada JWT nativa do runtime: segredo de controle mintado via `security.apiKeyGenerate` + `auth.secret`, bearer = JWT assinado `{sub,name,roles}`, gate por requisição `auth.authenticated()` + checagem na tabela (AUTH001–AUTH006, AUTH043 arquivo corrompido; Authorization violada recebe o 401 medido do runtime antes do handler); auto-inscrição só com tabela vazia; goldens `HTTPCHECK-OK` 28/28 com marcador gateado + `RESTART-OK` 6/6 com revogação sobrevivendo ao restart) → **A3** resume negotiation. `--check` acumula uma perna por fatia pousada (agora seis: `registry persist plain secure share` todas verdadeiras). B2/B3 ficam votado-A (relay manual, destinatário CLI).
Frente compilador fechada 04/10: o **§591** aposentou os falsos-REDs cross-arch (gate as+ld+qemu + `has()` ciente de `KOF_CROSS_PREFIX`); suíte completa do `lab` medida 5180/2F/661S, as únicas 2F são corridas de cancelamento do `InteropTimeoutE2ETest` sob carga da suíte — 0F sozinhas (condição da frente interop, não do produto). Jar do produto reconstruído do tip final; todos os goldens re-varridos verdes, incl. SERVECHECK-OK dois processos e HTTPCHECK-OK+RESTART-OK com estado limpo do control plane.

## 5. EVOLUÇÃO DE PRODUTO (v2 — prompt da mantenedora 05/10)

KofShare deixa de ser prova de planos e vira O PRODUTO: "um link, um cliente,
uma autorização, uma conexão direta". O baseline v1 é CONTRATO: os goldens
existentes (USERCHECK/SERVECHECK/HTTPCHECK/RESTART/SHARE/RESUME/PERSIST/RELAY
+ as oito pernas CHECK) devem permanecer verdes a cada passo; o que funcionava
e para de funcionar é BUG da implementação NOVA (regra R6 estendida ao
programa v2).

Ordem obrigatória (uma trilha por fatia: implementar → testar → golden →
regressão → documentar → commit; uma limitação do compilador PAROU a feature
e ABRE tarefa explícita no Kof4j — nunca workaround arquitetural silencioso):

```text
1. Identidade/device          POUSADA 05/10 (v2-Track A, IDENTITYCHECK-OK)
2. Abstração de recurso       (FileResource: id/nome/tamanho/hash/tipo — nunca
                               path remoto no wire)
3. Diretórios                 (árvore lógica, integridade por arquivo + digest
                               da coleção; empacotar pode ser interno, NUNCA
                               contrato do protocolo)
4. Sessão/sinalização         (CREATED→OFFERED→CLAIMED→NEGOTIATING→CONNECTED→
                               TRANSFERRING→COMPLETED/FAILED/CANCELLED/
                               EXPIRED; transição inválida = recusa por nome;
                               o plano NUNCA carrega bytes de arquivo)
5. Conectividade automática   (ConnectionStrategy DIRECTA→NAT→TRAVERSAL→RELAY;
                               relay continua ciphertext-only; o --relay manual
                               votado (D4) vira perna de fallback, não caminho
                               do usuário)
6. Destinatário browser       (página kofshare.app/s/<token> dirige o cliente
                               local — EXIGE primeiro as primitivas no Kof4j:
                               kof.net + keyExchange em JS; NETN001/SECN012
                               recusam por NOME hoje e devem ser fechados NA
                               LINGUAGEM, jamais por hack JS externo)
7. UX/simplificação CLI       (`share ./arquivo --expires 24h --once` →
                               SHARE-LINK; nada de portas/host/tokens para o
                               humano; verbos antigos viram aliases internos —
                               Track M: nada removido sem migração documentada
                               + teste de regressão)
8. Integração total           (testes de conectividade com dois processos
                               reais; todos os goldens; flakes de cold-start
                               documentados)
9. Documentação               (README = a história completa do produto:
                               limites honestos — P2P ≠ disponibilidade com o
                               dono offline (DEVICE-OFFLINE), o plano de
                               controle é infraestrutura real, tráfego de
                               relay existe)
10. Release candidate         (critério final de sucesso do prompt)
```

Não-agora, dito pelo prompt: billing, GUI desktop, Android, storage central.
A arquitetura não pode PRECLUÍ-los (Account/Organization/Policy/Usage/
RelayQuota/Audit devem ser adicionáveis sem reescrever o protocolo) — as
tabelas de binding da v2-Track A são exatamente esse tipo de costura.
### v2-Track A — identidade por device (POUSADA 05/10, `IDENTITYCHECK-OK`)

Uma identidade Ed25519 POR INSTALAÇÃO, separada do bearer da conta (a lei do
prompt: "a conta autentica o usuário; a chave identifica o dispositivo").
`kofshare/identity.kf`: boot (gera uma vez, persiste o secret 184-hex
quase-atomicamente, sobrevive a restart — mesma disciplina da chave de
controle; ID005 por nome em arquivo corrompido), deviceId DERIVADO como
`d-<sha256(pub64)[0:16]>` (copiar identidade entre máquinas gera id diferente
— duplicação recusada POR CONSTRUÇÃO; DEV005 ainda guarda contra cliente que
mente o id derivado), strings canônicas com versão (`v1|reg|…`, `v1|offer|…`)
assinadas com a metade privada e verificadas com a pública SOZINHA
(`crypto.verify(secrets.of(pub64),…)` — contrato D-KOF-SIGN; o secret nunca
sai do device). Plano de controle (`registry.kf` + `app.kf`): tabela de
binding deviceId→{pub,status} persistida (`server-registry.devkeys.json`,
REG009 corrompido), rota NOVA POST /devices/register (TOFU — a primeira
inscrição confia na auto-assinatura, toda operação posterior verifica contra a
chave guardada), GET /device-keys/:id, POST /devices/:id/revoke; o gate de
oferta roda ANTES da inserção (medido antes de pousar: a ordem ingênua —
controlOffer insere, depois verifica — meia-inseria uma oferta recusada) e é
CONTEXTUAL (Track I): devices inscritos DEVEM assinar (DEV002 inválida /
DEV004 ausente / DEV003 revogado), devices v1 sem chave passam INTACTOS
(Track M: POST /devices, ids à mão, bodies sem o campo — as pernas v1 estão
verdes nas legs legacyV1/RESTART-OK/HTTPCHECK-OK do golden). A revogação
chega ao CAMINHO DE DADOS: GET /s/<token> recusa DEV003 por nome (autorização
consumida está MORTA, não apenas ausente no futuro). `downFetch` corrigido no
caminho (só checou prefixo "REG"; qualquer body não-`{` é recusa nomeada — um
DEV003 seria decodificado como lixo). userflow `upPublishSigned` (id derivado,
inscrição assinada, oferta assinada); CLI: `up` sem `--id` pega a lane de
identidade (boot `kofshare-device.ed25519`, imprime o id derivado), `--id`
mantém a lane v1; verbo NOVO `device new|enroll|revoke|list`; `--check` ganhou
a perna 8 `identity=` (matriz pura, verde JVM E Script — keyExchange/sign/
verify funcionam no interpretador; SECN012 segue gap só de Native/JS). Golden
`identitycheck/checkidentity.kf` — 14 impressões com processos reais extras
(plano spawn, serve spawn, RESTART do plano sobre devkeys persistidas) e
recusas nomeadas AUTH001/DEV002/DEV003/DEV004/DEV005 em inscrição, oferta,
republicação, grant e sobrevivência a restart; pegou também uma VERDADE de
produto no RED: ids de oferta são content-addressed (o-<digest[0:12]>) — um
segundo device publicando os MESMOS bytes sobrepõe o slot da primeira oferta;
semântica v1, documentada no golden, é a Track 2/3 (identidade de recurso) que
revisita isso. Sem regressão: HTTPCHECK-OK + RESTART-OK (ciclo seed→restart→
verify completo contra server.kf standalone com controlServe de 12 args),
USERCHECK-OK 13 pernas, SHARECHECK-OK, SERVECHECK-OK, RELAY-OK,
RESUMECHECK-OK, PERSIST-OK, CHECK-OK ×8 pernas JVM+Script, 25/25 arquivos
check-clean isolados.
### v2-Track C — sessão & sinalização (POUSADA 05/10, `SESSIONCHECK-OK`)

O plano de controle aprende COORDENAÇÃO sem jamais carregar bytes. Domínio
puro `control/session.kf`: TransferSession{id, shareId, token,
ownerDeviceId, offerId, recipientDevice, recipientAddr, ownerAddr, state,
createdAt, expiresAt, transport}; ciclo CREATED→CLAIMED→NEGOTIATING→
CONNECTED→TRANSFERRING→COMPLETED com FAILED/CANCELLED por aresta e EXPIRED
pelo relógio — UMA função de matriz legal compartilhada por rotas e golden;
transição inválida = SES002 por nome, desconhecida SES001, carimbo do relógio
SES003 no toque (mesma disciplina dos shares), token ruim SES004, recipient
vazio SES006, uma sessão ATIVA por share SES005 (terminal libera o slot),
arquivo corrompido SES041. Rotas (`app.kf`, controlServe de 14 args):
POST /sessions (bearer — destinatário se anuncia com o token do share),
GET /sessions?device=&state= (dono DESCOBRE por pull — sinalização v1
honesto: a face web do runtime ainda não tem push de servidor, documentado
não escondido), GET /sessions/:id (detentor do token OU bearer — destinatário
lê a própria sessão sem conta), POST /sessions/:id/claim (só do dono; CLAIMED
recusa pelo advance genérico — medido antes de pousar: o primeiro guarda
`!holdsToken` deixava o DESTINATÁRIO se auto-claimar quando o POST também
carregava conta — exatamente a confusão de autorização que o prompt proíbe),
POST /sessions/:id/advance (face só-token para os passos do destinatário).
ownerAddr é CARIMBADO do REGISTRO no claim (o plano é a autoridade de endereço
— lei C2; o body não move o encontro). Persistência:
server-registry.sessions.json (quase-atômico; purge no boot MANTÉM sessões
TERMINAIS até o próprio TTL — medido: o purge antigo as descartava na hora e a
perna de sobrevivência-a-restart recusou corretamente). CHECK perna 9
`session=` (escada pura + todas recusas, verde JVM E Script). Golden
`sessioncheck/checksession.kf` (portas 19380-19382, processo de serve REAL +
plano REAL + restart): recusas na porta (AUTH001/SES004/SES006), escada pelo
wire com ownerAddr carimbado verificado no JSON, campo transport (direct)
registrado no CONNECTED, DADOS fluindo enquanto state==TRANSFERRING (bytes do
downFetch idênticos), COMPLETED e regras de terminal, caminho CANCELLED,
reload da tabela de sessões após RESTART do plano. Três bugs de golden
pegados pelo RED (cada um com condição nomeada, não sono): claimPath false
(chaves JSON afirmadas com nomes inventados — o discriminante é `state`, o id
é `id`); restartSurvives false (janela do purge, acima); e o hang do RELAY do
usercheck (três reproduções + thread dumps: a THREAD spawn começa ~200ms após
a instrução — o cliente discava o listener do relay antes de relayServeOn ter
aceito/discado, JVMs disputadas cruzavam um pump meio-construído; correção =
flag-file como PRIMEIRA instrução do spawn, cliente disca só depois de vê-lo —
a linguagem não tem connect-com-timeout e não inventei um; spawnServe do
servecheck confiava em marcador de log STALE — deletar-e-sincronizar + prova
de porta bindável antes de cada spawn, e o usercheck ganhou servePortClear nas
quatro pernas de serve). Sem regressão: USERCHECK-OK (15 impressões),
IDENTITYCHECK-OK, SHARECHECK-OK, SERVECHECK-OK, RESUMECHECK-OK, PERSIST-OK,
RELAY-OK, HTTPCHECK-OK + RESTART-OK (ciclo standalone completo com
controlServe de 14 args), CHECK-OK 9 pernas × JVM+Script, 27/27 arquivos
check-clean isolados.

