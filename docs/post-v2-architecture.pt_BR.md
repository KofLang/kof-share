# KofShare — arquitetura pós-v2 (DECIDIDO)

status: REGISTRO DE DECISÃO. O v2 é RELEASE (corte 06/10). Este documento
decide a forma do que vem depois, a partir do código e das provas que já
existem.
substitui: o RASCUNHO 06/10 deste arquivo (cujas D7–D10 eram perguntas de
voto); a diretiva pós-v2 da mantenedora reespecificou-as como decisões — este
é esse registro. As sub-perguntas do rascunho (toolkit da GUI, momento da
extração do core, piso de telemetria) foram absorvidas em D8/D9/D7.
data: 06/10 (decidido). Lane dona: security/connectors `192.150.15.15:9092`.
EN: [post-v2-architecture.md](post-v2-architecture.md)

Disciplina de categorias usada em todo o documento — nada além disso é
permitido:

```text
DECIDIDO   registrado com um status abaixo; pode ser invocado
PROPOSTO   descrito, NÃO é contrato até receber um status
RESERVADO  um slot na arquitetura, deliberadamente vazio
ADIADO     pergunta real com procedimento de decisão registrado
FORA DE ESCOPO  não pode entrar na arquitetura sem mudança de escopo
```

## 1. Contexto pós-v2

O KofShare v2 entregou: compartilhamento de arquivo, de diretório (coleções
lógicas), abstração de recurso (ids lógicos por dispositivo), identidade
Ed25519, auth de contas bearer/JWT, tokens de share com expiração/usos/
readOnly/revogação, persistência do plano com recusa por corrupção, resume
idempotente por offset, ciclo de sessão (claim/advance) coordenado pelo
plano, presença por heartbeat, estratégia de conectividade honesta
(DIRECT→RELAY, NAT reservado), relay ciphertext-only, destinatário no
navegador via cliente local localhost, UX simplificada
(`share`/`receive`/`stop`, Hint+código, lane `--raw`) e integração
ponta-a-ponta em processos reais.

Fatos do release (não se rediscute aqui):

```text
KofShare v2 = RELEASE        tag v2.0.0
compiler_pin = Kof4j f2629e32d
jar_sha256   = 0b1893b4e4de365cacd3d4cdfcdd2bcd066fcd9f8ca2352910077a07107effe0
RC-CHECK-OK steps=23         (prova de release; bateria = rc/runrc.kf)
40/40 arquivos check-clean standalone
compiler_upstream_pending = NONE
candidate 20a3207e1: medido, NÃO repinado (3 load-races de bateria em steps
distintos; todos verdes em isolamento no MESMO jar). Lei: um HEAD novo não é
automaticamente melhor que o jar verificado.
```

A pergunta que este documento responde NÃO é "qual feature depois", e sim:
**"qual é a forma definitiva do KofShare agora que o protocolo e o produto
base estão provados?"** Nenhum código é escrito por esta decisão. Nenhuma
track é criada. A bateria RC permanece a prova do release.

## 2. Estado atual (verdade de solo, arquivo por arquivo)

```text
plano de controle  server/server.kf + control/{app,registry,share,auth}.kf
  um processo, um host; estado = maps em memória + JSON salvo a cada
  mutação (a ÚNICA costura: controlSaveList / controlLoadList em
  registry.kf); identidade (devkeys), contas (bearer), offers, shares,
  sessões, presença, grants. NÃO carrega NENHUM byte — provado
  (SESSIONCHECK, INTEGRATIONCHECK wireNoLayout).
plano de dados     transfer.kf + session.kf + protocol.kf + relay.kf + connect.kf
  fluxo chunked dispositivo↔dispositivo; verificação por digest por
  arquivo; resume idempotente por offset; transporte carimbado pelo dial
  que realmente aconteceu.
dispositivo/biblioteca
                   identity.kf resource.kf directory.kf userflow.kf
  userflow.kf É a biblioteca de orquestração que a CLI dirige — o embrião
  do core já existe como fronteira de arquivo, não como ficção.
superfícies        cli/cli.kf (verbos de usuário + operador + CHECK)
                   app/client.kf (cliente localhost da lane do browser:
                   /api/info, jobs; só-metadados para a página — provado
                   browserSecrets)
```

## 3. D7 — o papel DEFINITIVO do plano de controle

```text
Decisão:   a topologia pós-v2 é plano de controle central + plano de dados
           descentralizado, SEM armazenamento central de conteúdo, nunca.
Status:    ACEITA
Escolhida: D7-A (controle central / dados descentrais) — e ela é a
           descrição do que o v2 JÁ faz, agora registrada como forma
           definitiva em vez de acidente de MVP.
Por quê:   toda prova v2 depende disso: o plano nunca vê bytes
           (wireNoLayout), o relay nunca parseia (tamper RELAY), o conteúdo
           mora só nos discos dos donos (transferências verificadas por
           digest). Mudar isso não evolui o produto — substitui o produto.
Rejeitadas: armazenamento central como modo do produto (ver D7-C);
           "a GUI/browser fala o protocolo diretamente" (ver D8/D9).
Impacto atual: nenhum — isto é ratificação, não mudança.
Impacto futuro: a replicação (D7-B) continua RESERVADA; a ratificação diz ao
           projetista da replicagem QUAIS invariantes devem sobreviver a ela.
Compatibilidade: wire v1/v2 intocado. Segurança: inalterada, agora contratual.
```

### D7-B — múltiplos planos de controle: avaliado, não adotado (RESERVADO)

Inventário honesto (lido do código, não projetado):

| Pergunta | Resposta hoje |
|---|---|
| o que é estado local? | os maps em memória do `server.kf` + arquivos `server-registry.*.json` escritos por `controlSaveList` após cada mutação |
| o que é identidade global? | `deviceId = d-<sha256(pub)[0:16]>` e `resourceId = r-…(device,name,size,digest)` — DERIVADOS, portanto portáveis entre qualquer número de planos por construção |
| o que poderia ser replicado? | os payloads do registro (devices/offers/shares/accounts/devkeys/sessions/presence) — já existem como documentos JSON completos com nomes de campo versionados |
| o que é naturalmente stateless? | verificação de assinatura (só a metade pública), validação de grant assinado, o plano de dados inteiro (o plano não está no caminho dos bytes) |
| onde o modelo assume single-node? | a chave de assinatura do controle (`server-control.ed25519` — um arquivo por host), o segredo de bearer (`server-control.apikey`), o store em JSON (sem atomicidade entre hosts), os contadores `shareTouch` (escritas locais por nó) |
| quais contratos BLOQUEIAM HA futuro? | NENHUM no wire — clientes falam HTTP e nunca fixam geração do plano; os bloqueadores são só de deploy (store compartilhado + distribuição de chave), exatamente por isso replicação é slot RESERVADO e não dívida de protocolo |

Status: **RESERVADO** — replicar é possível sem tocar nenhum contrato
congelado; é escalado quando um segundo nó REAL existir, não antes.

### D7-C — armazenamento central

```text
Decisão:   o plano de controle pode guardar SOMENTE: contas, dispositivos,
           shares, sessões, presença, METADADOS de recurso,
           auditoria/telemetria de metadados. Nunca pode virar arquivo,
           backup ou repositório de conteúdo por deriva de feature.
Status:    ACEITA (como invariante arquitetural, não como preferência)
Rejeitado: qualquer proposta em que o servidor detém conteúdo (incluindo
           relay que bufferiza em disco — isso transforma transporte em
           storage pela porta dos fundos).
Por quê:   a descentralização do conteúdo é uma PROPRIEDADE que os goldens
           medem (wireNoLayout, tamper RELAY, browserSecrets); tornar o
           storage um modo invalidaria as provas do release, não apenas
           adicionaria uma flag.
Piso de telemetria (absorvido do rascunho): os metadados que já existem
           (usos de share, estados de sessão, timestamps de presença) são o
           piso. Auditoria estruturada é adicionável SÓ no mesmo formato dos
           registros do plano — apenas metadados.
```

## 4. D8 — a arquitetura DEFINITIVA do cliente

```text
Decisão:   o próximo cliente principal é uma GUI desktop construída sobre um
           kofshare-core compartilhado; CLI e GUI são duas camadas de
           apresentação sobre um único domínio. Opção C. A extração do core
           em si é ADIADA para o momento do agendamento da GUI e deve ser um
           refactor de comportamento zero, provado pela bateria completa.
Status:    ACEITADA (direção) / ADIADA (movimento de empacotamento)
Escolhida: Opção C — core + CLI-sobre-core + GUI-sobre-core.
Por quê:   só a C mantém a lei "a GUI não é uma segunda implementação do
           protocolo" verdadeira POR CONSTRUÇÃO: um modelo de identidade, um
           modelo de recurso, um motor de transferência, um modelo de
           segurança; automação CLI, UX GUI e clientes futuros dirigem o
           MESMO código. Evidência de que não é ficção: userflow.kf JÁ é a
           biblioteca de orquestração — a CLI atual delega os fluxos; a
           extração formaliza uma fronteira que já mede limpa.
Rejeitadas: Opção A (GUI embrulhando a CLI): raspar stdout não observa
            ciclo de vida (progresso, estados de sessão, recusas nomeadas
            como eventos) e congelaria a saída humana da CLI como contrato
            de IPC — envenena as duas superfícies.
            Opção B (GUI no core, CLI como está): deixa a CLI segurando a
            orquestração que a GUI reimplementaria — deriva garantida entre
            os dois clientes, a falha exata que a D9 existe para proibir.
Impacto atual: NENHUM. Nenhum core é extraído agora. (A própria regra da
            diretiva: primeiro decidir a fronteira; não construir abstração
            sem consumidor. O consumidor — a GUI — ainda não foi escalado.)
Impacto futuro: quando (não se) a GUI for escalada, a unidade de extração é:
            kofshare-core = identity.kf + resource.kf + directory.kf +
            userflow.kf + connect.kf + transfer.kf + session.kf +
            protocol.kf + relay.kf + clientes de controle; a cli.kf fica
            fina; a GUI se liga nos MESMOS pontos de entrada. Gate:
            RC-CHECK-OK no commit da extração com diffs de comportamento
            zero em src/ (o split protocol/session de 03/10 é o precedente e
            o método).
Compatibilidade: cada verbo da CLI, flag, linha `--raw` e recusa nomeada está
            CONGELADO através da extração; a CLI permanece a referência
            funcional e o CI a mantém verde com zero código de GUI.
Segurança:  a GUI não pode deter NENHUM segredo isolado hoje (matriz §7):
            control secret — nunca em qualquer cliente; chave privada do
            device — só no store do dispositivo; bearer — no store de
            sessão; browser — metadados.
```

As oito pré-perguntas da GUI (gate de agendamento, respondidas ANTES de
qualquer janela existir) estão registradas na §9; respondê-las é a decisão,
não codificá-las.

## 5. D9 — a fronteira entre CORE, PLANO DE CONTROLE, CLIENTE, RELAY, BROWSER

```text
Decisão:   esta tabela de posse É a arquitetura; qualquer mudança futura de
           posse é uma nova decisão exigindo a ATUALIZAÇÃO PRIMEIRO deste
           documento (nada de migração código-primeiro).
Status:    ACEITA
```

| Capacidade | Dono | Prova/arquivo hoje |
|---|---|---|
| Identidade do device (par de chaves, derivação) | CORE (lado device) | identity.kf; IDENTITYCHECK |
| Registros de matrícula/revogação | PLANO DE CONTROLE | registry + devkeys; DEV001–005 |
| Autorização de share (mint/touch/validar) | PLANO DE CONTROLE | share.kf REG030–041; rota /s |
| Resolução de recurso (id→caminho) | CORE, SÓ NO DEVICE DONO | binding table resource.kf; RESOURCECHECK |
| Máquina de estados da sessão | PLANO COORDENA; CORES dirigem as pernas | ciclo de sessão; SESSIONCHECK |
| Estratégia de conectividade | CORE (no device que disca) | connect.kf; CONNECTCHECK |
| Motor de transferência (chunks/resume/digest) | CORE | transfer.kf; E2E, RESUMECHECK |
| Criptografia (envelope) | CORE; o plano guarda só suas chaves de assinatura | session.kf; SEC-E2E, TAMPER |
| Transporte de relay | PROCESSO WORKER — stateless, ciphertext-only | relay.kf; RELAY-OK |
| Auth de conta | PLANO DE CONTROLE | auth.kf AUTH001–043 |
| Apresentação CLI | cli.kf (fina; orquestração já está em userflow.kf) | UXCHECK; pernas CHECK |
| Apresentação desktop | GUI ADIADA → só CORE (regras da §8) | — (não construída) |
| UI do browser | PÁGINA + cliente local (API só-metadados) | app/client.kf; BROWSERCHECK, browserSecrets |

A lista NUNCA (qualquer arquitetura que viole uma destas é REJEITADA à
primeira vista, não "revisada"):

```text
o browser dono de chaves ou bearers         (browserSecrets prova a lei)
o relay dono/buffer de conteúdo             (RELAY é bomba; tamper prova)
a GUI duplicando o protocolo                (a opção C da D8 existe p/ impedir)
o plano de controle recebendo bytes         (wireNoLayout)
cada cliente novo reimplementando segurança (um core = um modelo)
a CLI guardando lógica que pertence ao core (deriva conhecida hoje: serveOne,
    startFaceHeartbeat, spawnDetached vivem em cli.kf; a extração os move —
    registrado para o refactor ser migração, não descoberta)
```

## 6. D10 — o futuro do PLANO DE DADOS

```text
Decisão:   a cadeia DIRECT → NAT/ICE → RELAY é a forma permanente.
           session.transport continua o contrato abstrato que é hoje: uma
           string carimbada pelo dial que realmente aconteceu. Valores
           concretos só podem CRESCER aditivamente; TransferSession nunca é
           reescrita.
Status:    ACEITA pelo contrato / RESERVADA para NAT-ICE
Hoje:      DIRECT = REAL · RELAY = REAL · NAT/ICE = RESERVADO (nunca fingido;
           os goldens usam porta-morta+relay como análogo-NAT documentado)
Futuro:    quando o Kof4j entregar primitivas reais de STUN/ICE (coleta de
           candidatos, connectivity checks), novos valores carimbados — ex.
           ICE-DIRECT, ICE-RELAY — são valores ADITIVOS para a linha da
           sessão e para consumidores `--raw`; o wire, o envelope e a
           máquina de estados ficam byte-idênticos. O slot reservado é a
           escada de estratégia de connect.kf, desenhada para ser exatamente
           isto: classifyConnect → (DIRECT | [NAT] | RELAY |
           CONNECTIVITY_FAILED).
Rejeitado: STUN/ICE fake, ICE adivinhado por heurística, relay promovido a
           tier de conteúdo, "transport = direct" quando relayado (lei da
           honestidade — INTEGRATIONCHECK carimba o dial real).
Compatibilidade: os valores já impressos pelo v2 mantêm as strings exatas.
Segurança:   o relay ciphertext-only vale sob qualquer transporte futuro.
```

## 7. Fronteiras de segurança (herdadas do v2, congeladas para o que vem)

```text
chave privada do device → identidade do device → autorização assinada →
capability de share → sessão → plano de dados     (a cadeia inteira, intacta)

control secret ≠ chave privada do device ≠ token de share ≠ bearer de
conta ≠ resource id
```

| Componente | Pode saber | DEVE NUNCA saber |
|---|---|---|
| plano de controle | tokens, ids, estados, presença, metadados | bytes de arquivo, caminhos do dono, chaves privadas |
| relay | nada (frames opacos) | plaintext (sob `--secure`), chaves |
| device publicador | suas chaves + seus arquivos oferecidos | nada novo |
| device recebedor | suas chaves + bytes recebidos | chave privada do publicador |
| browser | metadados do share para a página | control secret, bearer, chave privada, caminhos |
| desktop futuro | o mesmo da CLI: chaves e bearers próprios | control secret |

Qualquer arquitetura pós-v2 que enfraqueça uma destas fronteiras é
**REJEITADA POR ESTE DOCUMENTO** (não "sinalizada", não "revisada" —
rejeitada), porque cada linha é carregada por um golden que a bateria RC
roda antes de qualquer release.

## 8. Regras de compatibilidade

Congeladas por esta decisão (o v2 é RELEASE — isto É o produto):

```text
compatibilidade de wire v1 · recusas nomeadas (REG/SES/DEV/AUTH/ID/…) ·
resource IDs · manifest de diretório (raiz-primeira lexicográfico, digest
só-filhos) · TransferSession · tokens de share · identidade de device ·
semântica de resume · linhas de máquina `--raw` · dupla face JVM+Script no
CHECK
```

Se uma mudança futura quebrar alguma: (1) nomear o contrato quebrado;
(2) justificar contra as provas de release que invalida; (3) versionar;
(4) fornecer a migração; (5) NUNCA esconder a quebra atrás de heurística.
Os passos 1–4 são o procedimento da decisão; uma mudança que não completa o
passo 2 sem enfraquecer a §7 não é problema de compatibilidade — é outro
produto.

## 9. Registro de adiados/reservados

| Item | Categoria | Procedimento de decisão (o que mudaria o status) |
|---|---|---|
| envelope selado (X25519) sobre árvores de DIRETÓRIO | **ADIADO** — decisão de segurança/protocolo, NÃO lacuna de implementação | responder primeiro: um envelope por árvore vs um por arquivo vs composição hierárquica (por-filho já funciona plain); a escolha muda o ramo dir do HELLO e o key schedule, então exige decisão de protocolo NESTE documento antes de qualquer código |
| travessia STUN/ICE real | **RESERVADO** (escada de connect.kf + valores aditivos de session.transport) | o Kof4j entrega as primitivas; uma fatia as mede; o slot se preenche — o desenho da escada já assume isto |
| `web.app().listen()` binda 0.0.0.0 | **CONTRATO DE RUNTIME** (registrado, não escondido) | uma face de bind-address no Kof4j, ou decisão por proxy; hardening é conversa de runtime, não feature do KofShare |
| extração do kofshare-core | **ADIADA** até o agendamento da GUI | as oito pré-perguntas abaixo são respondidas; a extração então pousa como refactor de comportamento zero com gate RC-CHECK-OK |
| a própria GUI desktop | não é FORA DE ESCOPO para sempre — mas **PROPOSTA**; o próximo passo maior depois destas fronteiras; nenhum framework é escolhido, nenhuma interface é inventada agora | decisão de agendamento da mantenedora |
| oito pré-perguntas da GUI (gate de agendamento) | registradas não respondidas, DE PROPÓSITO | (1) superfície da API do core (2) ciclo de vida do cliente (3) onde moram as chaves (4) como a GUI observa TransferSession (5) como controla shares (6) comportamento offline (7) recusas nomeadas como eventos (8) UX de iniciar/pausar transferências |
| replicação do plano / DB externa / multi-tenant | **RESERVADO** (a tabela D7-B nomeia cada costura e cada suposição single-node) | um segundo nó/tenant real existe; então a lista de costuras vira a lista de fatias |
| Android · billing · subscriptions · storage central · STUN fake · ICE fake · relay-vira-storage · reescrita de protocolo | **FORA DE ESCOPO** (lei do prompt; storage adicionalmente REJEITADO como invariante D7-C) | mudança de escopo pela dona do produto, não por conveniência |

## 10. Alternativas rejeitadas (explícitas, para ninguém re-discutir de informal)

```text
GUI embrulhando a CLI (D8-A)                   — stdout-como-IPC; mata as duas
                                                 superfícies
GUI no core, CLI gorda como está (D8-B)        — duas orquestrações derivam
Browser com rede JS direta                     — continua REJEITADO como em
                                                 D-NET-JS-V1; NETN001/SECN012
                                                 fecham na linguagem, nunca por
                                                 hacks externos
Armazenamento central de conteúdo; relay que
 bufferiza                                     — invariante D7-C; invalida as
                                                 provas do release
STUN/ICE fake; claims de NAT por heurística    — lei da honestidade; CONNECTCHECK
                                                 carimba dials reais
Replicação/microserviços/DB externa agora      — nenhum segundo consumidor;
                                                 infra especulativa
Track K/L/M para manter atividade              — a bateria é a prova, não uma
                                                 lista de afazeres
Abstrações sem consumidores                     — interfaces "future-proof"
                                                 são proibidas por este documento
                                                 até a extração da D8 pousar
```

## 11. Resumo das decisões

| # | Decisão | Status |
|---|---|---|
| D7 | plano de controle = coordenador central, plano de dados descentralizado, SEM storage de conteúdo (análise de HA registrada, replicação RESERVADA) | ACEITA |
| D8 | cliente definitivo = CLI + futura GUI desktop sobre um kofshare-core compartilhado (opção C); extração ADIADA ao agendamento da GUI | ACEITADA (direção) / ADIADA (empacotamento) |
| D9 | tabela de posse + lista NUNCA são a lei da fronteira; mudanças exigem procedimento documento-primeiro | ACEITA |
| D10 | DIRECT→(NAT/ICE RESERVADO)→RELAY para sempre; session.transport cresce só aditivamente | ACEITA / RESERVADA (NAT-ICE) |
| — | envelope selado em árvore de diretório | ADIADO (pergunta de protocolo registrada) |
| — | web.listen 0.0.0.0 | CONTRATO DE RUNTIME (registrado) |

## 12. Consequências

- A topologia agora é lei, não padrão: controle-central + dados-descentralizados
  não pode ser trocado "sem querer" por um drive; os goldens são o alarme.
- A GUI está autorizada como a próxima forma maior — e simultaneamente
  constrained: não pode existir antes das oito pré-perguntas respondidas e
  não pode existir senão como consumidora do (futuro) core.
- A extração do `kofshare-core` tem definição de pronto (bateria verde, diff
  de comportamento zero) e um gatilho (agendamento da GUI) — para nunca ser
  pretexto de refactor no meio do caminho.
- NAT/ICE tem um slot nomeado com contrato de valores aditivos; quando o
  Kof4j crescer as primitivas, o produto preenche o slot sem tocar o wire.
- Os gaps conhecidos permanecem exatamente tão honestos quanto estavam no
  corte — este documento registra suas categorias e seus procedimentos de
  decisão, não os quita.
- Nada neste documento muda código. O trabalho real seguinte é: a
  mantenedora responde/escala o gatilho da D8, ou comissiona a decisão de
  protocolo da sealed-tree (a pergunta ADIADA), ou repina o compiler (uma
  re-medição completa da bateria, pela lei do pin). As três são decisões com
  procedimentos já escritos — que é exatamente o que fecha esta etapa.
