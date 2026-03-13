# kwtsms-zig Examples

Runnable examples demonstrating how to use the kwtSMS Zig client library.

## Examples

| # | File | Description |
|---|------|-------------|
| 0 | [00_raw_api.zig](00_raw_api.zig) | Raw HTTP calls to every API endpoint (no library, copy-paste ready) |
| 1 | [01_basic_usage.zig](01_basic_usage.zig) | Connect, verify credentials, send a single SMS |
| 2 | [02_otp_flow.zig](02_otp_flow.zig) | Generate and send an OTP code |
| 3 | [03_bulk_sms.zig](03_bulk_sms.zig) | Send to multiple numbers with deduplication |
| 4 | [04_error_handling.zig](04_error_handling.zig) | Input validation, message cleaning, error codes |
| 5 | [05_otp_production.zig](05_otp_production.zig) | Production OTP: rate limiting, secure generation, verification |

## Setup

1. Create a `.env` file in the project root:

```ini
KWTSMS_USERNAME=zig_username
KWTSMS_PASSWORD=zig_password
KWTSMS_SENDER_ID=YOUR-SENDER
KWTSMS_TEST_MODE=1
```

2. Build and run a specific example:

```bash
zig build example-01
./zig-out/bin/example-01
```

Replace `01` with the example number you want to run (`00` through `05`).

## Notes

- All examples use `test_mode=true` by default. Set to `false` for production.
- `KWT-SMS` is a shared test sender. Register a private sender ID before going live.
- For OTP, use a **Transactional** sender ID (not Promotional) to bypass DND filters.
- `example-05` (production OTP) uses `std.crypto.random` directly. Do not substitute a timestamp-seeded PRNG.
- Call `client.deinit()` after `KwtSMS.fromEnv()` to free .env-loaded strings.
- `sendBulk()` returns a `BulkSendResult`; call `result.deinit(allocator)` to free all batch data.
