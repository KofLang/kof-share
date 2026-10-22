# KofShare — Server central: implantação (PT/EN)

## 1. O que é o plano de controle / What the control plane is

O servidor central **autoriza identidades e coordena sessões**. Ele nunca
recebe, armazena ou transporta bytes de arquivo em operação normal — os bytes
seguem pelo data plane P2P (direct) ou por um relay que só vê ciphertext.
The central server authorizes identities and coordinates sessions. It never
receives, stores or transports file bytes in normal operation; bytes move
peer-to-peer, or through a ciphertext-only relay.

## 2. Configuração / Configuration

A face `kof.config` do runtime lê, em precedência: arquivo apontado por
`KOF_CONFIG` > variáveis de ambiente `KOF_<KEY>` > `kof.config` no diretório
de trabalho. Chaves do plano:

| chave | default | efeito |
|---|---|---|
| `kofshare.dir` | `.` (cwd) | diretório de TODO o estado do plano: 7 `server-registry.*.json`, `server-control.ed25519`, `server-control.apikey`, `server-control.bearer` |
| `kofshare.port` | argv ou 9090/18322 por verb | porta de escuta (valores inválidos → `SERVER-CONF-ERR`, boot recusado por nome) |
| `kofshare.publicurl` | vazio | localizador exibido nos links (`https://share.example.com/s/<tok>`); o probe de saúde e as chamadas ao plano continuam no host:port real — DNS público não é dependência do plano |
| `kofshare.maxBody` | 65536 | cap de payload nos endpoints sensíveis (`REG042`) |
| `kofshare.maxShares/maxGrants/maxDevices` | 20000/20000/10000 | caps de tabela contra abuso (`REG043/GRANT042/REG044`) |

Exemplo (`/etc/kofshare/plane.conf`):

```ini
kofshare.dir=/var/lib/kofshare
kofshare.port=9443
kofshare.publicurl=https://share.example.com
```

Executar: `KOF_CONFIG=/etc/kofshare/plane.conf java -jar kof-cli.jar run
src/main/kof/kofshare/cli/cli.kf server --start` (detached + readiness por
observável, marker `SERVER-READY`). Parar: verb `stop` (varre apenas as portas
possuídas pelos pidfiles desta instalação).

## 3. Bootstrap administrativo

No primeiro boot o plano cria a conta `admin` (label `owner`) e grava o bearer
em `<dir>/server-control.bearer` (0600, dono apenas). A porta de inscrição de
usuários (`POST /accounts`) **nunca** concede privilégios administrativos: com
a tabela não-vazia, exige o bearer admin. A conta `admin` é a lane de
recuperação/operador — sub distinto de qualquer conta de usuário (provado em
`ACCOUNTISOLATIONCHECK`). O segredo de controle (`server-control.apikey`) e a
chave Ed25519 do plano (`server-control.ed25519`) são material criptográfico
do plano, separados das credenciais de usuário; nunca trafegam para o browser
nem aparecem em links, logs ou respostas.

## 4. TLS e proxy reverso (obrigatório na Internet)

O runtime `web.listen` **não** oferece TLS nativo, e o plano não implementa
TLS caseiro (lei do prompt). Em produção, termine TLS num proxy reverso e
aponte `kofshare.publicurl` para a face pública:

```nginx
server {
  listen 443 ssl;
  server_name share.example.com;
  ssl_certificate     /etc/letsencrypt/live/share.example.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/share.example.com/privkey.pem;
  client_max_body_size 64k;            # alinhado a kofshare.maxBody
  location / {
    proxy_pass http://127.0.0.1:9443;  # plano escuta só no loopback atrás do proxy
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 60s;
  }
}
```

Sem TLS terminado, bearer tokens e JWTs trafegam em claro — o produto recusa
por design chamadas que exijam credencial, mas a confidencialidade do transporte
é do proxy. Tráfego de produção **não** deve ser chamado de seguro sem isso.

## 5. Persistência, backup e restauração

- Todo o estado é texto JSON determinístico + chaves em arquivos próprios do
  diretório `kofshare.dir`. **Backup** = parar o plano (`stop`) e copiar o
  diretório. **Restauração** = apontar `kofshare.dir` para a cópia e iniciar.
  Provado com processo real em `DEPLOYMENTCHECK` (ciclo boot→mint→restart→
  cp -r→boot na cópia→`WHOAMI` idêntico).
- **Fail-closed**: registro de grants corrompido/partial** impede o boot com
  recusa nomeada (`GRANT040/041`) — um plano jamais sobe em modo
  possession-only sobre grants de identidade existentes. Mesma lei para
  shares (`REG041`), contas (`AUTH043`), sessões (`SES041`), presenças.
- Ausência do arquivo de grants em diretório NOVO é legítima (zero grants —
  comportamento v2 exato). Corrupção ≠ ausência.

## 6. Revogação e recuperação

- Conta: `POST /accounts/:id/revoke` (admin) — bearer morre na gate; grants de
  identidade da conta viram opacos `REG035` para todos, inclusive o próprio.
- Dispositivo: `POST /devices/:id/revoke` — grants ativos no dispositivo
  recusam `DEV003/DEV004` nomeados; proprietários derivados (owner binding
  TOFU) fecham mint/revoke de terceiros (`AUTH004/005`).
- Share/grant: `POST /shares/:id/revoke` (duo: gate de dono) ou
  `POST /grants/:id/revoke`; a revogação propaga share↔grant e sobrevive a
  restart do plano (provado em `REVOKECHECK`). Bytes **já entregues** não são
 recalláveis — o produto distingue revogação de acesso futuro (nova
  autorização/nova sessão/retomada) de controle sobre conteúdo entregue;
  resume pós-revogação é recusado por nome (`DEPLOYMENT/REVOKE` legs).
- Recuperação de conta perdida: lane admin cria nova conta e o usuário
  re-registra dispositivo com sua chave pública local (TOFU). Dispositivo
  perdido: revogue o antigo (matando grants vivos) e registre o novo.

## 7. Limites honestos / honest limits

- NAT traversal real (STUN/ICE) não existe no runtime — a estratégia DIRECT→
  NAT→RELAY mantém a lacuna reservada e nomeada; relay é manual por voto
  (`--relay host:port`), ciphertext-only, provado (`RELAY-OK`).
- Bind `0.0.0.0` é contrato do runtime (`web.listen(Int)`) — a superfície local
  privilegiada do desktop vive atrás de token 0600 + Host/Origin policing
  (decisão §DP Opção A registrada em `docs/desktop/phase0-matrix.md`); a face
  `listen(host, port)` segue como pedido upstream nomeado.
- Envelope selado X25519 cobre arquivos individuais; para árvores de
  diretórios permanece como lacuna documentada (sem downgrade silencioso).

## 8. Validação reproduzível

```sh
# golden de deploy (processos reais, portas próprias 19456):
java -jar <pin> run src/main/kof/kofshare/deploycheck/checkdeploy.kf   # DEPLOYMENTCHECK-OK legs=10
# bateria completa (34 steps):
java -jar <pin> run src/main/kof/kofshare/rc/runrc.kf                  # RC-CHECK-OK steps=34
```
