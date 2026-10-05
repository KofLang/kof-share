# HTTP-ERR-ESCAPE — `http.get` lets raw `java.net.ConnectException` escape `catch (String e)`

- **Status:** UPSTREAM FILED — HTTP-ERR-ESCAPE -> KofLang/Kof4j#771 FILED 05/10 (this file remains the permanent reproduction packet) (same dirty-tree note as COMP002 packet).
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
