# KofShare — Local API v1 Contract & Event Stream Specification

**Status:** IMPLEMENTED (Gate 1 SAFE SUBSET + privileged lane over §DP DECIDED
OPTION A, 09/10) — proven by `DESKTOP-API-OK legs=22` + `DESKTOP-PRIV-OK
legs=14` with real processes on loopback. Binding stays `0.0.0.0` at pin
`f2629e32d` (runtime contract); the boundary is token (0600) + Host policing
+ Origin allow-list, RED-before-GREEN proven including a raw-socket
forged-Host leg. `listen(host,port)` remains the named upstream request.
**Scope:** Local daemon control interface (`/api/v1/*`), zero remote protocol changes, zero central file storage.
**Audience:** Desktop shell page, CLI automation, and local orchestration.

---

## 1. Security Architecture & Threat Model

### 1.1 Network Binding & Exposure
* **Current Runtime Reality:** At pin `f2629e32d`, `web.app().listen(port)` binds to `0.0.0.0` (all network interfaces).
* **Threat 1: LAN Attackers:** Untrusted hosts on the same local network sending requests to the daemon port.
  * **Mitigation:** Strict `X-Kof-Token` authentication on every `/api/v1/*` endpoint. The token is generated via `security.randomHex(16)` on boot and stored in `kofshare-desktop.token` with POSIX permissions `0600` (user-only). Mismatch immediately yields named code `DESKTOP-LOCAL-AUTH` (HTTP 401/403 equiv).
* **Threat 2: Web Browsers / DNS Rebinding / Cross-Origin Attacks:** Malicious web pages running JavaScript in the user's browser attempting to pivot into `http://localhost:<port>`.
  * **Mitigations:**
    1. **Strict Host Header Check:** The daemon must reject requests where `header("host")` does not match `127.0.0.1:<port>` or `localhost:<port>`. DNS rebinding attacks rely on spoofed Host headers (e.g., `attacker.com:<port>`).
    2. **Custom Header Requirement (`X-Kof-Token`):** Standard web browsers block JavaScript from attaching custom headers across origins unless permitted by CORS preflight. The daemon **never** emits permissive CORS headers (`Access-Control-Allow-Origin: *`).
    3. **Content-Type Enforcement:** All mutating endpoints (`POST`, `DELETE`) require `Content-Type: application/json`.
* **Threat 3: Credential Leakage:** Exposure of control plane bearer tokens or device Ed25519 private keys.
  * **Mitigation (Inviolable Law):** Responses from `/api/v1/*` contain **only metadata view models**. Private keys (`kofshare-device.ed25519`) and the control plane bearer (`server-control.bearer`) are **never** echoed or surfaced.

---

## 2. API Contract Matrix (`/api/v1/*`)

All payloads are JSON. Error bodies use the standard format:
`{"error": "<NAMED_CODE>", "message": "<HUMAN_DESCRIPTION>"}`

| Method | Route | Auth | Purpose | Input Payload | Output Payload | Errors / Named Refusals | Persistent Effects |
|---|---|---|---|---|---|---|---|
| `GET` | `/api/v1/health` | `X-Kof-Token` | Liveness & local readiness probe | None | `HEALTH-OK` (plain) | `DESKTOP-LOCAL-AUTH` (missing/bad token), `DESKTOP-LOCAL-ORIGIN` (forged Host/Origin) | None |
| `GET` | `/api/v1/state` | `X-Kof-Token` | Daemon lifecycle, ports, plane status | None | `{"phase": "READY", "plane": "ok"\|"unreachable", ...}` — metadata only, never bearer/keys | `DESKTOP-LOCAL-AUTH`, `DESKTOP-LOCAL-ORIGIN` | None |
| `GET` | `/api/v1/events` | `X-Kof-Token` | Event stream (polling) | Query `?since=<seq>` | JSON array of event envelopes; `since=<lastSeq>` → `[]` | `DESKTOP-LOCAL-AUTH` | None (ring buffer, resets on restart) |
| `POST` | `/api/v1/login` | `X-Kof-Token` | Bind an account credential to the daemon | `{"bearer": "<plane-bearer>"}` — file:` lane preferred, value never echoed | `{"sub":"<account>"}` | `DESKTOP-LOCAL-AUTH`, `DESKTOP-LOGIN-REFUSED: <plane-refusal>` | Credential stored 0600 (`kofshare-desktop.credential`) |
| `POST` | `/api/v1/logout` | `X-Kof-Token` | Drop the bound credential | None | `DESKTOP-LOGOUT-OK` | `DESKTOP-LOCAL-AUTH` | Credential file deleted; mutations refuse `DESKTOP-NO-CREDENTIAL` |
| `GET` | `/api/v1/accounts` | `X-Kof-Token` + login | Who is currently bound | None | `{"sub":"<account>"}` | `DESKTOP-LOCAL-AUTH`, `DESKTOP-NO-CREDENTIAL` | None |
| `GET` | `/api/v1/device` | `X-Kof-Token` + login | Local device identity + enrollment | None | `{"deviceId":"<d-…>","pubkey":"<hex>","enrolled":<bool>}` (pub half only) | `DESKTOP-LOCAL-AUTH`, `DESKTOP-NO-CREDENTIAL` | None (enrollment happens on share via the plane) |
| `POST` | `/api/v1/shares` | `X-Kof-Token` + login | Create a share (file or folder), async job | `{"path":"<local>","to":"<account>"\|"", "ttl":"24h"\|"", "once":<bool>, "readOnly":<bool>}` | `{"job":"<jb-…>","state":"QUEUED"}` — poll `GET /api/v1/shares`; `DONE` rows carry the minted link | `DESKTOP-NO-CREDENTIAL`, `PATH-NOT-FOUND`, `DESKTOP-BAD-REQUEST`, plane refusals (`REG*`/`AUTH*`) surface in the job row | Job row + plane offer/share/grant; worker spawned with bearer as `file:` reference (never argv) |
| `GET` | `/api/v1/shares` | `X-Kof-Token` | List share jobs (queue + history) | None | Job rows with `state` (`QUEUED`/`RUNNING`/`DONE`/`FAILED`) and link on `DONE` | `DESKTOP-LOCAL-AUTH` | Reads local job table |
| `POST` | `/api/v1/shares/:id/revoke` | `X-Kof-Token` + login | Revoke a minted share (owner law on the plane) | None (`:id` = job id) | `{"status":"REVOKED","id":"<plane-share-id>"}` | `DESKTOP-NO-CREDENTIAL`, `TRANSFER-NOT-FOUND`, `DESKTOP-REVOKE-PENDING` (not minted yet), `AUTH005` (non-owner, from the plane) | Plane share/grant revoked; job row `REVOKED` |
| `POST` | `/api/v1/transfers` | `X-Kof-Token` + login | Receive a link, async job | `{"link":"http://…/s/<tok>","dest":"<relative-path>"}` (absolute/`..` → `DEST-INVALID`) | `{"job":"<jb-…>","state":"QUEUED","dest":"<…>"}` | `DESKTOP-NO-CREDENTIAL`, `DESKTOP-BAD-REQUEST`, `DEST-INVALID`; `REG035` (wrong identity — zero bytes) surfaces in the job row | Job row + received bytes under the daemon cwd; `.part` resume |
| `GET` | `/api/v1/transfers` | `X-Kof-Token` | List transfer jobs | None | Job rows with `state` and per-row detail reference | `DESKTOP-LOCAL-AUTH` | Reads local job table |
| `GET` | `/api/v1/transfers/:id`| `X-Kof-Token`| Transfer detail (honest counters) | None | `{"id":…, "state":…, "dest":…, "bytesDone":<on-disk-size>}` | `TRANSFER-NOT-FOUND` | None (bytesDone read from the file on disk) |
| `POST` | `/api/v1/transfers/:id/cancel`| `X-Kof-Token`| Cancel a queued/running transfer | None | `{"status":"CANCELLED","id":…}` | `TRANSFER-NOT-FOUND`, `TRANSFER-NOT-CANCELLABLE: <state>` | Worker stopped; `.part` kept for resume |

---

## 3. Event Catalog & Interface Synchronization

### 3.1 Event Envelope
Every event emitted on `/api/v1/events` conforms to:
```json
{
  "seq": 1042,
  "type": "TRANSFER_PROGRESS",
  "timestamp": 1728400000000,
  "opId": "xfer-7b89a",
  "payload": {
    "state": "TRANSFERRING",
    "bytesDone": 5242880,
    "bytesTotal": 10485760,
    "transport": "DIRECT"
  }
}
```

### 3.2 Event Types (emitted — `DESKTOP-PRIV-OK` asserts the catalog)
1. `DAEMON_STATE`: phase transitions (`READY` at boot).
2. `PLANE_PRESENCE`: control plane connection state (`ONLINE`, `OFFLINE`, `UNREACHABLE`, from the daemon poller).
3. `IDENTITY_LOGIN` / `IDENTITY_LOGOUT`: credential bind/drop with `sub`.
4. `SHARE_DONE` / `SHARE_FAILED`: job outcome; `DONE` rows carry the minted link.
5. `SHARE_REVOKED`: owner-law revocation confirmed by the plane.
6. `TRANSFER_DONE` / `TRANSFER_FAILED` / `TRANSFER_CANCELLED`: job outcomes;
   `FAILED` rows carry the named refusal (`REG035`, `CONNECTIVITY_FAILED`…).
7. `TRANSFER_PROGRESS` (per-byte) is deliberately NOT emitted — progress is
   read honestly from `GET /api/v1/transfers/:id` (`bytesDone` = on-disk size);
   emitting unobserved transitions would invent state (§4 event law).

### 3.3 Recovery & Disconnection Strategy
* **State Recovery by Query:** Clients that disconnect or miss events **do not rely on unbounded replay buffers**. The UI queries `GET /api/v1/transfers` and `GET /api/v1/state` upon reconnection to re-establish ground truth.
* **Cursor Polling Fallback:** In environments where streaming sockets are interrupted, `GET /api/v1/events?since=<seq>` returns buffered events since `<seq>` (ring buffer of last 64 events).

---

## 3.4 Implementation status (Gate 1 SAFE SUBSET + privileged lane)

**Implemented + proven** (`desktopapi/apicheck.kf` → DESKTOP-API-OK legs=22):
`/api/v1/health`, `/api/v1/state`, `/api/v1/events?since=<seq>` all guarded by
Host + Origin + token. Events are the OBSERVABLE subset — `DAEMON_STATE`
(boot) and `PLANE_PRESENCE` (real transitions recorded by the daemon's
presence poller). The file-backed ring buffer resets on daemon restart;
recovery after a disconnected consumer is by re-querying `/api/v1/state` and
re-subscribing `/api/v1/events?since=<lastSeq>` (documented; no fake replay).

**Implemented + proven** (`desktoppriv/privcheck.kf` → DESKTOP-PRIV-OK
legs=14, three account identities, real P2P through the daemon): `POST
/api/v1/login|logout`, `GET /api/v1/accounts|device`, `POST|GET
/api/v1/shares`, `POST /api/v1/shares/:id/revoke`, `POST|GET
/api/v1/transfers`, `GET /api/v1/transfers/:id`, `POST
/api/v1/transfers/:id/cancel` — every line rides the token+Host+Origin
boundary with named refusals; the account bearer travels only as a `file:`
reference into workers (never argv, never responses, never events —
secret-hygiene scan leg); identity authorization is imposed by the PLANE
(stranger links fail `REG035` with zero bytes; non-owner revoke fails
`AUTH005`).

## 4. Decided: §DP OPTION A (no longer pending)

Recorded in `docs/desktop/phase0-matrix.md §DP`, decided 09/10: keep HTTP on
`0.0.0.0` + token (0600) + Host policing (DNS-rebinding) + Origin allow-list
(CSRF/malicious-page), all RED-before-GREEN proven. The privileged surface
above is UNLOCKED under these conditions. Option B (`listen(host,port)`
upstream face) remains the named request for the day a pin candidate carries
it; Option C (Unix socket via FFI) stays rejected (second IPC stack, breaks
the served-page shell).
