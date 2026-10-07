# KofShare — decisão arquitetural pós-v2 (RASCUNHO — aguardando voto da mantenedora)

status: DOCUMENTO DE DECISÃO (sem implementação). O v2 é RELEASE (ver
STATUS.md); este arquivo decide a FORMA do que vem depois, a partir do
código que já existe.
data: 06/10. Lane dona: security/connectors `192.150.15.15:9092`.
EN: [post-v2-architecture.md](post-v2-architecture.md)

## 0. Verdade de solo (o que o v2 já é, arquivo por arquivo)

```
plano de controle  server/server.kf + control/{app,registry,share,auth}.kf
  - um processo, um host; estado = maps em memória + save a cada mutação
    (controlSaveList/controlLoadList) — persistência provada por RESTART-OK
  - identidade (devkeys Ed25519), contas (bearer JWT), offers, shares,
    sessões (claim/advance), presença (heartbeat+TTL), grants (/s/<token>)
  - NÃO carrega NENHUM byte de arquivo (provado: SESSIONCHECK, INTEGRATIONCHECK)
plano de dados     transfer.kf + session.kf + protocol.kf + relay.kf + connect.kf
  - fluxo chunked dispositivo↔dispositivo; verificado por digest; resume
    idempotente por offset
  - transporte escolhido com honestidade: DIRECT → (NAT/ICE RESERVADO, nunca
    fingido) → RELAY (bomba opaca de ciphertext, processo worker separado)
dispositivo        identity.kf + resource.kf + directory.kf + userflow.kf
  - um par de chaves por instalação; recursos são ids LÓGICOS por dispositivo;
    a tabela caminho↔recurso nunca sai do dispositivo dono
superfícies        cli/cli.kf (verbos de usuário + operador + pernas CHECK)
                   app/client.kf (cliente localhost da lane do browser)
```

## 1. Plano de controle — o servidor central definitivo

Responsabilidades que ele DEVE manter (todas implementadas, não mover):
matrícula/revogação de identidade · auth de contas · registro de
offers/shares · mint+validação+touch de grants · sinalização de sessões ·
presença · ganchos de política.

Responsabilidades que ele NUNCA deve ganhar: conteúdo de arquivo, ciphertext
de chunk, layout do filesystem do destinatário (três leis já provadas por
golden; qualquer proposta futura que as viole é rejeitada na revisão, não no
código).

Telemetria (pergunta aberta D10): o mínimo que já existe como sinais
simples (estados de sessão, contadores de uso, timestamps de presença). Um
servidor definitivo pode adicionar auditoria estruturada — mas SÓ
metadados, no mesmo formato das entradas do registro. Nenhuma superfície
nova de rastreamento sem voto.

## 2. Plano de dados — permanece descentralizado e honesto

```
dispositivo A ⇄ DIRECT ⇄ dispositivo B        (LAN/sempre que discável)
dispositivo A ⇄ RELAY(ciphertext) ⇄ B          (fallback, processo worker hoje)
NAT/ICE: RESERVADO — fecha somente quando o Kof4j oferecer primitivas reais
```

O worker de relay é uma bomba de bytes sem parse (RELAY-OK + prova de
tamper). Múltiplos NÓS de relay são adicionáveis sem nenhuma mudança de
protocolo: o grant já carrega o endereço do relay como tupla de par; a
sessão carimba o transporte real. O que NÃO é adicionável sem voto: relays
que armazenam, transformam ou persistem bytes (storage pela porta dos fundos).

## 3. Cliente desktop — decisão de camadas (D7/D8), não reescrita

Separação-alvo:

```
kofshare-core    ← a lógica v2 COMO BIBLIOTECA: userflow, connect, transfer,
                   clientes de controle, identity, resources, directories
                   (por construção de arquivos já tem zero dependência de CLI)
kofshare-cli     ← driver fino sobre o core (o cli.kf de hoje menos a orquestração)
kofshare-desktop ← GUI sobre o core — MESMAS chamadas de orquestração, nunca
                   um cliente de protocolo novo; não faz nada que a CLI não faça
```

Leis da GUI quando (não se) for escalada:
- a CLI permanece a referência funcional; o CI mantém `--check`+goldens
  verdes com CÓDIGO ZERO de GUI — um bug de GUI nunca derruba o produto;
- a GUI não pode deter SEGREDOS que o dispositivo guarda: o control secret
  nunca cruza para qualquer cliente; a chave privada fica no equivalente a
  `kofshare-device.ed25519`; o bearer fica no store de sessão; a lane do
  navegador mantém o contrato só-metadados (`browserSecrets` do INTEGRATIONCHECK);
- face gráfica: D-GRAPHICS-WINDOW-FORM + SDL3 do Kof4j (pousados 05/10) são a
  única rota de janela sancionada; nada de Electron/webview-remotizando-o-plano.

A separação é uma mudança de empacotamento com gate rígido: a extração do
`kofshare-core` acontece SOMENTE como refactor sem mudança de comportamento,
provado pela bateria RC inteira (a mesma disciplina do split protocol/session
de 03/10).

## 4. Deploy do servidor — costuras primeiro, escala depois

Hoje: plano de controle single-node + estado em arquivo. Costuras já existentes:

| Necessidade futura | Costura que existe hoje | Ainda preso ao single-node |
|---|---|---|
| DB externa (trocar os JSON) | choke points `controlSaveList/controlLoadList` | os maps em memória + save por mutação |
| plano de controle replicado | o contrato HTTP é stateless por request | o segredo de bearer + devkeys + stores |
| múltiplos nós de relay | relay = processo separado + tupla no grant | nada (já é separável) |
| contas multi-tenant | record `Account(id,label,status)` | a autorização é global do plano hoje |
| orgs/políticas/cotas | records adicionáveis (lei "not-now" do v1) | — |

DECISÃO: manter single-node até existir um segundo tenant real; NÃO construir
infra multi-nó genérica por especulação (a antirregra do próprio prompt).
Quando a troca de DB for escalada, a unidade de persistência são os loaders
de `control/{registry,share,auth}` — um corte contido e testável, com
`PERSIST-OK`/`RESTART-OK` como rede de regressão.

## 5. Storage — o não-objetivo, como invariante

O servidor central armazena: metadados, identidades, grants, sessões, estado
de conta, presença, auditoria mínima. Ele NÃO armazena conteúdo
compartilhado. O relay NÃO bufferiza conteúdo em disco. Isso não é
preferência de política — é o que o código faz de forma mensurável hoje
(goldens HTTPCHECK/RELAY/INTEGRATION). Qualquer proposta de "virar drive" é
OUT OF SCOPE por definição do produto, não por descuido.

## 6. Fronteiras de segurança — matriz componente × conhecimento

```
                      controle  relay  publicador  recebedor  browser  desktop
 control secret          SIM      no      no         no          no     NUNCA
 chave priv do device     no      no    a própria    a própria   no      no
 bearer de conta         minte     no   próprio     próprio*     NÃO   próprio
 token de share           SIM      no    dono      apresentado   página  via core
 resourceId               SIM      no   tbl local   tbl local  metadado  n/a
 bytes em plaintext       NO      NO   só disco     só disco     NO     só disco
 ciphertext no fio        NO     passa    —            —          NO      —
```
(`*` bearer do recebedor só na CLI/desktop; o browser NUNCA vê.)
A coluna desktop é um CONTRATO para D7/D8, não uma observação. A GUI não
pode concentrar segredos que hoje estão isolados — a matriz é o gate.

## 7. O que este documento deliberadamente NÃO faz

Sem Track K. Sem código de GUI. Sem Android/billing/subscriptions/storage
central. Sem STUN/ICE fake. Sem mudança de protocolo. Sem named refusal
nova. Sem reescrever contrato v2. Sem abstração sem consumidor. Ele fixa a
FORMA para que o PRIMEIRO código pós-v2 seja decisão com plano de prova,
não demo.

## 8. Decisões abertas para a mantenedora (formato de voto, como D1–D6)

- **D7** forma da GUI: janela SDL3 + UI desenhada em Kof (recomendado, casa
  com as faces gráficas pousadas) vs webview sobre o cliente local vs adiar.
- **D8** momento da extração do core: agora como refactor sem comportamento
  com bateria (recomendado) vs quando a GUI for escalada.
- **D9** alvo de deploy: single-node continua a referência até 2º tenant
  (recomendado) vs planejar DB/replicação primeiro.
- **D10** piso de telemetria: tabela de auditoria só-metadados
  (recomendado) vs nenhuma.

Quando o voto pousar, a seção de roadmap de `docs/next-plan.md` ganha a fatia
correspondente — implementar→testar→golden→regressão→documentar→commit, a
mesma cadência; limitação de compilador PARA a feature (nunca contorno silencioso).
