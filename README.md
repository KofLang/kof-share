# kof-share
## Transfer core (sliced 02/10)

`src/main/kof/kofshare/transfer.kf` — 100% Kof over `kof.net` (D-KOF-NET):
frame `len(4 BE) | index(4 BE) | payload`, offset-idempotent resume
(`serveFile` from `resumeOffset`, `fetchFile` appends the `.part`). The
AES-GCM envelope rides the separate `SECN005` key-exchange decision.
Oracle: `e2e.kf` (200000 bytes TCP loopback + spawn worker + resume@100000)

```
bin/kof run --target script src/main/kof/kofshare/e2e.kf   # E2E-OK
bin/kof run --target jvm    src/main/kof/kofshare/e2e.kf   # E2E-OK
```
