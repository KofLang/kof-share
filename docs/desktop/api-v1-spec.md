# KofShare — Local API v1 Contract & Event Stream Specification

**Status:** PREPARATORY SPECIFICATION for FASE 2 (Gate §2 & §DP Pending Decision)  
**Scope:** Local daemon control interface (`/api/v1/*`), zero remote protocol changes, zero central file storage.  
**Audience:** Future Desktop Shell, CLI automation, and local orchestration.

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
| `GET` | `/api/v1/health` | `X-Kof-Token` | Liveness & local readiness probe | None | `{"status": "HEALTH-OK", "uptime": <ms>}` | `DESKTOP-LOCAL-AUTH` | None |
| `GET` | `/api/v1/state` | `X-Kof-Token` | Daemon lifecycle, ports, plane status | None | `{"phase": "READY", "plane": "ok"\|"unreachable", "planeAddr": "<url>", "localPort": <int>, "pid": "<pid>"}` | `DESKTOP-LOCAL-AUTH` | None |
| `GET` | `/api/v1/device` | `X-Kof-Token` | Local device cryptographic identity | None | `{"deviceId": "<id>", "pubkey": "<hex>", "enrolled": <bool>}` | `DESKTOP-LOCAL-AUTH`, `DEV-NOT-INITIALIZED` | None |
| `GET` | `/api/v1/shares` | `X-Kof-Token` | List active outbound shares created locally | None | `{"shares": [{"id": "<id>", "path": "<path>", "token": "<tok>", "kind": "file"\|"dir", "created": <ts>, "status": "active"\|"revoked"\|"expired"}]}` | `DESKTOP-LOCAL-AUTH` | Reads local resource/share state |
| `POST` | `/api/v1/shares` | `X-Kof-Token` | Create a new share (file or folder) | `{"path": "<local_path>", "ttl": "<ttl>", "once": <bool>, "readOnly": <bool>}` | `{"id": "<id>", "token": "<tok>", "link": "<full_link>", "manifestCount": <int>}` | `DESKTOP-LOCAL-AUTH`, `PATH-NOT-FOUND`, `REG013`, `REG015`, `UP-ERR` | Writes resource binding & registers offer/share on plane |
| `DELETE`| `/api/v1/shares/:id`| `X-Kof-Token` | Revoke an active share | None | `{"status": "REVOKED", "id": "<id>"}` | `DESKTOP-LOCAL-AUTH`, `REG034`, `SHARE-NOT-FOUND` | Marks share revoked on plane & local table |
| `POST` | `/api/v1/transfers` | `X-Kof-Token` | Initiate receive/download of a link | `{"link": "<token_or_url>", "destDir": "<local_dest>"}` | `{"transferId": "<id>", "state": "STARTING", "resourceId": "<id>"}` | `DESKTOP-LOCAL-AUTH`, `REG038`, `CONNECTIVITY_FAILED`, `DEST-INVALID` | Enqueues transfer worker; creates `.part` file |
| `GET` | `/api/v1/transfers` | `X-Kof-Token` | List active & recent transfers | None | `{"transfers": [{"id": "<id>", "state": "<state>", "bytesDone": <int>, "bytesTotal": <int>, "transport": "DIRECT"\|"RELAY"}]}` | `DESKTOP-LOCAL-AUTH` | Reads transfer table |
| `GET` | `/api/v1/transfers/:id`| `X-Kof-Token`| Get detailed progress & state | None | `{"id": "<id>", "state": "<state>", "bytesDone": <int>, "bytesTotal": <int>, "speedBps": <int>, "digest": "<hex>", "transport": "<t>"}` | `DESKTOP-LOCAL-AUTH`, `TRANSFER-NOT-FOUND` | None |
| `POST` | `/api/v1/transfers/:id/cancel`| `X-Kof-Token`| Cancel or pause a transfer | None | `{"status": "CANCELLED", "id": "<id>"}` | `DESKTOP-LOCAL-AUTH`, `TRANSFER-NOT-FOUND` | Signals worker abort; preserves `.part` for resume |
| `GET` | `/api/v1/events` | `X-Kof-Token` | Event stream (SSE or long-polling) | Query: `?cursor=<id>` | SSE stream or delta event array | `DESKTOP-LOCAL-AUTH` | Tracks cursor position |

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

### 3.2 Event Types
1. `DAEMON_STATE`: Phase transitions (`READY`, `BUSY`, `STOPPING`, `ERROR`).
2. `PLANE_PRESENCE`: Control plane connection state (`ONLINE`, `OFFLINE`, `UNREACHABLE`).
3. `SHARE_CREATED`: Outbound share minted.
4. `SHARE_REVOKED`: Outbound share invalidated.
5. `TRANSFER_STARTED`: Handshake established, path classified (`DIRECT` or `RELAY`).
6. `TRANSFER_PROGRESS`: Incremental byte progress derived from real socket counter.
7. `TRANSFER_COMPLETED`: File written, SHA-256 digest verified.
8. `TRANSFER_FAILED`: Named error code surfaced (`CONNECTIVITY_FAILED`, `DIGEST_MISMATCH`, `REMOTE_REVOKED`).

### 3.3 Recovery & Disconnection Strategy
* **State Recovery by Query:** Clients that disconnect or miss events **do not rely on unbounded replay buffers**. The UI queries `GET /api/v1/transfers` and `GET /api/v1/state` upon reconnection to re-establish ground truth.
* **Cursor Polling Fallback:** In environments where streaming sockets are interrupted, `GET /api/v1/events?since=<seq>` returns buffered events since `<seq>` (ring buffer of last 64 events).

---

## 4. Pending Architectural Decisions (§DP Gate)

1. **Gate Decision 1: Upstream Bind-Address Face vs. Loopback Token Defense**
   - **Option A (Current / Implemented):** Keep HTTP listener over `0.0.0.0` with strict `X-Kof-Token` (0600 file), `Host` header policing, and no CORS headers. Zero compiler modifications required.
   - **Option B (Upstream Core Face Request):** Request `web.app().listen(host, port)` in Kof4j. Requires compiler pin bump, upstream compiler patch, and complete RC regression battery.
   - **Option C (IPC Unix Domain Socket):** Implement Unix Domain Socket listener via FFI (`kof.ext`). Adds native platform dependency and a secondary IPC stack.
   - **Recommendation:** Proceed with **Option A** for Phase 2 implementation while keeping **Option B** as a formal upstream feature request for Kof4j, maintaining 100% Kof code purity and preserving the verified release pin `f2629e32d`.
