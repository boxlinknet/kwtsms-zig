# Example 00: Raw API Calls

Direct HTTP calls to every kwtSMS endpoint without the client library. Copy-paste any section into your own code.

## What it does

Calls all 7 kwtSMS API endpoints in sequence using `std.http.Client`:

| Step | Endpoint | Purpose |
|------|----------|---------|
| 1 | `POST /API/balance/` | Check account balance |
| 2 | `POST /API/senderid/` | List registered sender IDs |
| 3 | `POST /API/coverage/` | List active country prefixes |
| 4 | `POST /API/validate/` | Validate phone numbers before sending |
| 5 | `POST /API/send/` | Send SMS to a single number |
| 6 | `POST /API/send/` | Send SMS to multiple numbers (comma-separated) |
| 7 | `POST /API/status/` | Check message queue status (uses msg-id from step 5) |
| 8 | `POST /API/dlr/` | Get delivery report (international numbers only) |

## Setup

1. Open `examples/00_raw_api.zig`
2. Replace the credentials at the top of the file:

```zig
const USERNAME = "YOUR_USERNAME";   // your kwtSMS API username
const PASSWORD = "YOUR_PASSWORD";   // your kwtSMS API password
const SENDER_ID = "KWT-SMS";       // your registered sender ID
const TEST_MODE = true;            // true = no delivery, no credits consumed
```

3. Build and run:

```bash
zig build example-00
./zig-out/bin/example-00
```

## How it works

Every request follows the same pattern:

1. **Build a JSON body** with credentials + endpoint-specific fields
2. **POST** to `https://www.kwtsms.com/API/<endpoint>/` with `Content-Type: application/json`
3. **Read the JSON response** and print it

The example uses one small helper function (`apiPost`) for the HTTP call. Everything else is inline — you can see exactly what JSON goes in and what comes back.

## API request format

All endpoints use `POST` with a JSON body. Never use `GET` (credentials leak in server logs).

```
POST https://www.kwtsms.com/API/<endpoint>/
Content-Type: application/json
Accept: application/json

{"username":"...","password":"..."}
```

## Expected output

With valid credentials and `TEST_MODE = true`:

```
=== 1. Balance ===
Request:  POST /API/balance/
Response: {"result":"OK","available":150,"purchased":1000}

=== 2. Sender IDs ===
Request:  POST /API/senderid/
Response: {"result":"OK","senderid":["KWT-SMS"]}

=== 3. Coverage ===
Request:  POST /API/coverage/
Response: {"result":"OK","coverage":["965","966","971",...]}

=== 4. Validate ===
Request:  POST /API/validate/
Numbers:  96598765432, 96512345678, invalid123
Response: {"result":"OK","mobile":{"OK":["96598765432"],"ER":["invalid123"],"NR":[]}}

=== 5. Send SMS ===
Request:  POST /API/send/
To:       96598765432
Message:  Hello from Zig raw API example
Test:     yes (queued, not delivered)
Response: {"result":"OK","msg-id":"abc123...","numbers":1,"points-charged":1,"balance-after":149,"unix-timestamp":1684763355}
Saved msg-id: abc123...

=== 6. Send SMS (multiple numbers) ===
Request:  POST /API/send/
To:       96598765432, 96512345678
Response: {"result":"OK","msg-id":"def456...","numbers":2,"points-charged":2,...}

=== 7. Status ===
Request:  POST /API/status/
msg-id:   abc123...
Response: {"result":"OK","status":"queued","description":"Message accepted and in delivery queue"}

=== 8. Delivery Report (DLR) ===
Request:  POST /API/dlr/
msg-id:   abc123...
Response: {"result":"ERROR","code":"ERR019","description":"No delivery reports found"}

=== Done ===
```

## Response fields reference

### Send success

| Field | Type | Description |
|-------|------|-------------|
| `result` | string | `"OK"` |
| `msg-id` | string | Unique message ID (save this for status/DLR) |
| `numbers` | int | Count of numbers accepted |
| `points-charged` | int | Credits deducted |
| `balance-after` | float | Balance after deduction |
| `unix-timestamp` | int | Server time (GMT+3, not UTC) |

### Error response

| Field | Type | Description |
|-------|------|-------------|
| `result` | string | `"ERROR"` |
| `code` | string | Error code (e.g. `ERR003`) |
| `description` | string | Human-readable error message |

## Key rules

- **Always POST, never GET** — GET leaks credentials in server logs
- **Always set `Content-Type: application/json`** — omitting it returns legacy text/html responses
- **Phone numbers**: digits only, international format (e.g. `96598765432`), max 200 per request
- **Test mode** (`"test":"1"`): messages queued but not delivered, credits tentatively held (recoverable)
- **`unix-timestamp`**: GMT+3 (Asia/Kuwait), not UTC — convert when storing
- **`msg-id`**: save it at send time — you need it for status/DLR and cannot retrieve it later

## Notes

- This example does NOT use the kwtsms client library. It is pure `std.http.Client`.
- For production code, use the client library instead — it handles phone normalization, message cleaning, batching, error enrichment, and logging automatically.
- `KWT-SMS` is a shared test sender ID. Register a private sender ID before going live.
