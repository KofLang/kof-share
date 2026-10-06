# HTTP-ERR-ESCAPE — `http.get` lets raw `java.net.ConnectException` escape `catch (String e)`

- **Status:** UPSTREAM FIXED — issue KofLang/Kof4j#771 CLOSED/COMPLETED 05/10; ledger
  §608 records it as the SAME root as §598 (the #756 wrap already landed); the
  original report measured a stale jar. THIS FILE REMAINS THE PERMANENT
  REPRODUCTION PACKET.
- **Verified 06/10 (this lane):** rebuilt tip `f2629e32d` runs the repro verbatim
  (`try { http.get(dead) } catch (String e)`) → `HTTPRESULT=caught`.
  The product `net.connect` probe (`healthNow`) STAYS — it is a correct
  liveness probe, not a workaround to remove.
- **Found by:** KofShare v2-Track I (05/10) while probing a dead control plane.

## Symptom

`try { http.get("http://127.0.0.1:<closed>/health") } catch (String e) { ... }`
does NOT catch: the JVM throws `java.net.ConnectException` straight through the
Kof catch clause (which only handles named runtime errors). `net.connect` to
the SAME closed port DOES produce a catchable String error ("Conexão recusada")
— the two modules diverge on the same condition.

## Minimal repro

```kof
void main() {
    var got = "no-throw"
    try {
        got = http.get("http://127.0.0.1:59431/health")
    } catch (String e) {
        got = "caught"
    }
    println("HTTPRESULT=" + got)
}
```

Expected (stdlib contract: runtime failures surface as named errors): prints
`HTTPRESULT=caught`. Actual: process dies with an uncaught Java stack trace.

## Product impact

A KofShare `receive <link>` against a DEAD plane would spray stack traces at
first-time users — the Track I golden therefore probes liveness with
`net.connect` (TCP) instead of `http.get` (measured workaround, documented in
`cli.kf` comments next to `healthNow`).

## Suggested fix face

`KofRuntime.kof_http_request` wrap of `java.io.IOException` → named String
error (`HTTP-CONNECT-FAILED: <reason>`), same class as the net module wrap.
<!-- pt: idem -->
