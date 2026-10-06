# COMP002 — JVM backend frame crash: `T?` value read through compound `&&` guards or threaded through branches

- **Status:** UPSTREAM FIXED — issue KofLang/Kof4j#770 CLOSED/COMPLETED; ledger
  §609 (std-namespace arg unwrap, `NullableNarrowingStdCallE2ETest` 4/4),
  §610 (residual `if`-expression + call-boundary faces, `NullableGuardFrameE2ETest`
  13/13) and §612 (native face, issue #772) close the family. The proposed
  numbers §605/§606 were consumed by other entries while the tree merged; the
  registry owner's numbering stands. THIS FILE REMAINS THE PERMANENT
  REPRODUCTION PACKET.
- **A/B verified 06/10 (this lane):** jar filed (05/10 build, kept at
  `/tmp` during the check) → both reproducers crash with the exact
  `frame crash`; rebuilt tip `f2629e32d` → `comp002-r2` prints `r=42`,
  `comp002-r1` prints `{"a":"5","b":"5"}` + `{"a":"parent","b":"x"}` — the §609
  golden verbatim. Full KofShare battery re-run on the fixed jar:
  `RC-CHECK-OK steps=23` (`/tmp` log 06/10) — RC VERIFIED on both jars.
- **Found by:** KofShare v2-Track G/H (05/10), three independent crash sites.
- **Compiler:** kof-cli 0.5.0-beta (reported 05/10 at the 05/10 tip; FIXED verified 06/10 at `f2629e32d`). Owner lane: security/connectors
  `192.150.15.15:9092` (same lane that landed §603 — related phase, DIFFERENT root shape:
  §603 was the SAM `invoke` descriptor; this one fires WITHOUT any function types).
- **Product impact:** NONE today — every site has a proven workaround (coalesce the
  nullable to a fresh local BEFORE any branch/call-argument use). The product must NOT
  depend on undefined compiler behavior; this packet makes the repro permanent (§21).

## Symptom

`kof check` dies with:

```text
Internal compiler error: frame crash in Default/Main.<fn> (super=java/lang/Object)
  phase: JVM backend / ASM COMPUTE_FRAMES (visitMaxs)
  ASM error: ArrayIndexOutOfBoundsException: Index -1 out of bounds for length 0
```

## Minimal reproducers (measured 05/10 on the shipped jar)

R1 — nullable PARAMETER read through branches (the Track G grant selector):

```kof
record G(String a, String b)
String encodeIt(String? q) {
    if (q == null) {
        return json.encode(G("parent", "x"))
    }
    var ci = math.parseInt(q)
    if (ci < 0) {
        return "neg"
    }
    return json.encode(G(q, "" + ci))
}
void main() {
    println(encodeIt("5"))
    println(encodeIt(null))
}
```

R2 — nullable read through a COMPOUND `&&` guard (the Track I pidfile helper):

```kof
Int takeIt(String? q) {
    if (q != null && q.length() > 0) {
        var n = math.parseInt(q)
        return n
    }
    return 0
}
void main() {
    println("r=" + takeIt("42"))
}
```

The last emitted ASM (both crashes end in the same pattern — an `ICONST_0`/
`IF_ICMPNE` pair whose operand was produced by a call that never pushed a
value on the NARROWED path):

```text
    GOTO L5
    L4
    ICONST_1
    L5
    GOTO L6
    L3
    ICONST_0
    L6
    ICONST_0
    IF_ICMPNE L7
    GOTO L8
    L7
    ISTORE 1
    ILOAD 1
    IRETURN
    L8
    ICONST_0
    IRETURN
```

## Expected behavior

Compiles; `takeIt("42")` prints `42`.

## Actual behavior

COMP002 frame crash above. `check` fails; `run` never starts.

## What compiles (narrowing the search surface)

- Same code WITHOUT the `&&` (split into `if (q != null) { if (q.length() > 0) ... }`)
  — R2 crashes, R1-style single-condition guards followed by a rebind do not.
- Same code where the narrowed value is COALESCED first:
  `var q2 = ""; if (q != null) { q2 = q }` then using `q2` — COMPILES (the shape
  KofShare ships in production: `dirGrantBody(o, childQuery-or-"" , ...)` and
  `stopHelper`'s rebind).
- Top-level functions AND route lambdas crash identically → not lambda-specific.
- Script target: NOT measured for these exact files (the crash is in the JVM
  backend phase; Script runs a different pipeline).

## IR facts

`KofLoadLocal[NullableType[String]]` followed by `KofCall[<length>]` and the
compound-condition label ladder; the `IF_ICMPNE` consumer sees a stack of
length 0 at frame merge → ASM `getStackSize()-1` = −1.

## Suggested regression test (for `JvmFrameDiagnosticsTest` / new E2E)

Both files above run as `test` programs with exit-code PASS: R2 prints `r=42`,
R1 prints the two encoded strings. RED-first proof: both are RED at the
current jar with the exact `frame crash` text.

## Known workarounds (product-side)

1. Coalesce nullable→non-null into a fresh local BEFORE any branch (`if (x !=
   null) { y = x }` then use `y`).
2. Never pass a narrowed nullable PARAMETER into a call argument inside a
   later branch; rebind first.

<!-- Keep in sync with STATUS.md "upstream: FIXED/verified" -->
