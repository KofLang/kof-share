# KofShare — início rápido (v2)

[Versão em inglês](quick-start.md)

## Você precisa de duas coisas

1. Uma JVM (17+) e o jar do Kof CLI (`kof-cli-0.5.0-beta.jar`).
2. Qualquer máquina que alcance o plano indicado. Sem instalação e sem
   daemon para cuidar: `server --start` destaca, `stop` limpa.

## Primeiro compartilhamento (lado do dono)

```bash
J=/path/to/kof-cli.jar
S="java -jar $J run src/main/kof/kofshare/cli/cli.kf"

$S server 18323 --start        # plano de controle; imprime PLANE-READY
$S share ./report.pdf          # imprime o link + "Active offer"
$S share ./photos              # pastas funcionam igual: "Files: N"
```

Copie o link `http://host:port/s/<token>` impresso e envie como qualquer
link de compartilhamento. Opções: `--ttl 2h|30m|days`, `--once` (uso único),
`--password` (porta no plano), `--raw` (linhas de máquina para scripts).

## Primeiro recebimento (lado do destinatário)

```bash
java -jar $J run src/main/kof/kofshare/cli/cli.kf receive http://host:port/s/<token>
```

O destino padrão é `./received`; um argumento = arquivo ou pasta. O
dispositivo destinatário matricula a própria identidade automaticamente
(TOFU), o plano resolve o link uma vez, e o plano de dados escolhe DIRECT,
caindo para o relay apenas quando um worker de relay foi informado. Todo
arquivo é verificado por SHA-256; transferências interrompidas retomam por
arquivo: rode o mesmo comando de novo.

Navegador? Abra o mesmo link — a página dirige o cliente local
(`app <plano> <porta> <token> <chave> <destino>` imprime sua própria URL
localhost); chaves e bearer nunca chegam à página.

## Fim do dia

```bash
$S stop        # mata apenas os helpers QUE ESTE dispositivo iniciou (face/app/server)
```

## Lendo erros (voz do produto)

```text
Link esgotado — peça um novo link ao remetente. (REG010)
O remetente está offline agora — peça para rodar `share` de novo. (DEV-OFFLINE)
Nada alcançável — peça ao remetente para checar a conexão. (CONNECTIVITY_FAILED)
```

O código nomeado permanece (contrato de diagnóstico); a linha `Hint:` é a
camada humana. A saída `--raw` mantém as linhas antigas byte-compatíveis.

## Lane do operador (verbos v1, inalterados)

`up`/`down`/`updir`/`downdir`/`serve`/`serve-dir`/`offer`/`fetch`/`relay`/
`device`/`account`/`heartbeat`/`shares`/`revoke`/`authorize` — as mesmas
flags que funcionavam na v1 continuam funcionando (compatibilidade é lei;
quebra é bug).

## Solução de problemas

* **Porta ocupada** — `server`/`share` agora varrem a porta e re-bindam
  (correção de órfãos v2); se o plano está em outro host, use
  `--server host:port`.
* **`receive` trava e falha** — a face do remetente caiu: rode `share` de novo.
* **Pasta chegou achatada** — confira se usou `share <pasta>` (coleção) e
  não um arquivo único; a ordem do manifest é raiz-primeira, lexicográfica.
* **Compilador `COMP002` frame crash** — veja `docs/upstream/` (bug conhecido
  do Kof4j; os contornos já estão embutidos nos caminhos do produto).
