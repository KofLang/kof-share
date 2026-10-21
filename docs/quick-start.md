# KofShare — quick start (v2)

[PT-BR version](quick-start.pt_BR.md)

## You need two things

1. A JVM (17+) and the Kof CLI jar (`kof-cli-0.5.0-beta.jar`).
2. Any machine that can reach the plane you point at. No install, no daemon
   you must babysit: `server --start` detaches, `stop` cleans up.

## First share (owner side)

```bash
J=/path/to/kof-cli.jar
S="java -jar $J run src/main/kof/kofshare/cli/cli.kf"

$S server 18323 --start        # control plane; prints PLANE-READY
$S share ./report.pdf          # prints the link + "Active offer"
$S share ./photos              # directories work the same: "Files: N"
```

Copy the printed `http://host:port/s/<token>` link and send it like any
other share link. Options: `--ttl 2h|30m|days`, `--once` (single-use),
`--to <account>` (restricted: ONLY that authenticated account can open it —
possession of the URL grants nothing), `--raw` (machine lines for scripts).

```bash
$S share ./report.pdf --to bob   # identity-bound link for bob
$S receive http://host:port/s/<token> --bearer file:~/.kofshare-bob.bearer
```

## First receive (recipient side)

```bash
java -jar $J run src/main/kof/kofshare/cli/cli.kf receive http://host:port/s/<token>
```

Destination defaults to `./received`; one arg = file or folder target. The
recipient device enrolls its own identity automatically (TOFU), the plane
resolves the link once, the data plane picks DIRECT and falls back to the
relay only when a relay worker was given. Every file is SHA-256 verified;
interrupted transfers resume per file: re-run the same command.

Browser? Open the same link — the page drives the local client
(`app <plane> <port> <token> <key> <dest>` prints its own localhost URL);
keys and bearers never reach the page.

## End of day

```bash
$S stop        # kills only the helpers THIS device started (face/app/server)
```

## Reading errors (product voice)

```text
Link spent — ask the sender for a new one. (REG010)
The sender is offline right now — ask them to run `share` again. (DEV-OFFLINE)
Nothing reachable — ask the sender to check their connection. (CONNECTIVITY_FAILED)
```

The named code stays (diagnostic contract); the `Hint:` line is the human
layer. `--raw` output keeps the old machine lines byte-compatible.

## Operator lane (v1 verbs, unchanged)

`up`/`down`/`updir`/`downdir`/`serve`/`serve-dir`/`offer`/`fetch`/`relay`/
`device`/`account`/`heartbeat`/`shares`/`revoke`/`authorize` — same flags
that worked in v1 still work (compat is a law; breakage is a bug).

## Troubleshooting

* **Port busy** — `server`/`share` now sweep the port and rebind (v2
  orphan-fix); if a plane is truly elsewhere, pass `--server host:port`.
* **`receive` hangs then fails** — the sender's face died: `share` again.
* **Directory landed flat** — check you used `share <dir>` (collection) not
  a single file; the manifest order is root-first lexicographic.
* **Compiler `COMP002` frame crash** — see `docs/upstream/` (known Kof4j
  bug, workarounds already baked into product paths).
