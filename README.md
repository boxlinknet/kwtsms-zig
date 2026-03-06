# kwtsms-zig

[![CI](https://github.com/boxlinknet/kwtsms-zig/actions/workflows/ci.yml/badge.svg)](https://github.com/boxlinknet/kwtsms-zig/actions/workflows/ci.yml)
[![Release](https://github.com/boxlinknet/kwtsms-zig/actions/workflows/release.yml/badge.svg)](https://github.com/boxlinknet/kwtsms-zig/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.13%2B-orange.svg)](https://ziglang.org/)
[![GitHub release](https://img.shields.io/github/v/release/boxlinknet/kwtsms-zig)](https://github.com/boxlinknet/kwtsms-zig/releases)

Official Zig client for the [kwtSMS](https://www.kwtsms.com) SMS gateway API.

Zero dependencies. Uses only the Zig standard library.

## Install

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .kwtsms = .{
        .url = "https://github.com/boxlinknet/kwtsms-zig/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "...", // Zig prints the expected hash on first build
    },
},
```

Then in your `build.zig`:

```zig
const kwtsms_dep = b.dependency("kwtsms", .{});
exe.root_module.addImport("kwtsms", kwtsms_dep.module("kwtsms"));
```

## Quick Start

```zig
const std = @import("std");
const kwtsms = @import("kwtsms");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Load credentials from environment variables / .env file
    var client = try kwtsms.KwtSMS.fromEnv(allocator, null);

    // Verify credentials
    const verify_result = try client.verify();
    if (verify_result.ok) {
        std.debug.print("Balance: {d:.2}\n", .{verify_result.balance.?});
    }

    // Send SMS
    const resp = try client.sendOne("96598765432", "Hello from Zig!", null);
    if (resp.isOk()) {
        std.debug.print("Sent. msg-id: {s}\n", .{resp.msg_id.?});
    }
}
```

## Setup

### Environment Variables

Create a `.env` file in your project root:

```ini
KWTSMS_USERNAME=zig_username
KWTSMS_PASSWORD=zig_password
KWTSMS_SENDER_ID=YOUR-SENDER
KWTSMS_TEST_MODE=1
KWTSMS_LOG_FILE=kwtsms.log
```

Environment variables take priority over `.env` file values.

### Constructor

```zig
var client = kwtsms.KwtSMS.init(
    allocator,
    "zig_username",
    "zig_password",
    "YOUR-SENDER",  // null defaults to "KWT-SMS"
    true,           // test mode
    "kwtsms.log",   // null defaults to "kwtsms.log", "" disables logging
);
```

## API Methods

### verify()

Test credentials and get balance.

```zig
const result = try client.verify();
if (result.ok) {
    std.debug.print("Balance: {d:.2}\n", .{result.balance.?});
} else {
    std.debug.print("Error: {s}\n", .{result.err.?});
}
```

### balance()

Get current balance. Returns cached value on API failure.

```zig
const bal = try client.balance();
if (bal) |b| {
    std.debug.print("Balance: {d:.2}\n", .{b});
}
```

### sendOne()

Send SMS to a single phone number.

```zig
const resp = try client.sendOne("96598765432", "Your OTP is: 123456", null);
if (resp.isOk()) {
    // Save msg-id for status checks / delivery reports
    std.debug.print("msg-id: {s}\n", .{resp.msg_id.?});
    std.debug.print("balance: {d:.2}\n", .{resp.balance_after.?});
}
```

### send()

Send SMS to multiple phone numbers. Automatically deduplicates normalized numbers.

```zig
const mobiles = [_][]const u8{ "96598765432", "+96512345678", "0096587654321" };
const resp = try client.send(&mobiles, "Bulk message", null);
```

### validate()

Validate phone numbers via the API.

```zig
const phones = [_][]const u8{ "96598765432", "invalid", "+96512345678" };
const resp = try client.validate(&phones);
```

### senderids()

List registered sender IDs.

```zig
const resp = try client.senderids();
```

### coverage()

List active country prefixes.

```zig
const resp = try client.coverage();
```

### status()

Check message delivery status.

```zig
const resp = try client.status("f4c841adee210f31307633ceaebff2ec");
```

### dlr()

Get delivery report (international numbers only).

```zig
const resp = try client.dlr("f4c841adee210f31307633ceaebff2ec");
```

## Utility Functions

### normalizePhone()

Convert Arabic digits to Latin, strip non-digits, strip leading zeros.

```zig
const normalized = try kwtsms.normalizePhone(allocator, "+965 9876-5432");
defer allocator.free(normalized);
// normalized = "96598765432"
```

### validatePhoneInput()

Validate a phone number with detailed error messages.

```zig
const result = try kwtsms.validatePhoneInput(allocator, "user@example.com");
if (!result.valid) {
    std.debug.print("Error: {s}\n", .{result.err.?});
    // "This looks like an email address, not a phone number"
}
```

### cleanMessage()

Remove emojis, HTML tags, control characters. Convert Arabic digits to Latin.

```zig
const cleaned = try kwtsms.cleanMessage(allocator, "Hello \xF0\x9F\x98\x80 <b>bold</b>");
defer allocator.free(cleaned);
// cleaned = "Hello  bold"
```

## Error Handling

Every API response includes `result`, `code`, `description`, and `action` fields:

```zig
const resp = try client.sendOne("96598765432", "Test", null);
if (resp.isError()) {
    std.debug.print("[{s}] {s}\n", .{ resp.code.?, resp.description.? });
    if (resp.action) |action| {
        std.debug.print("Fix: {s}\n", .{action});
    }
}
```

### Error Codes

| Code | Description | Action |
|------|-------------|--------|
| ERR001 | API disabled | Enable at kwtsms.com -> Account -> API |
| ERR003 | Wrong credentials | Check KWTSMS_USERNAME / KWTSMS_PASSWORD |
| ERR006 | No valid numbers | Include country code (e.g., 96598765432) |
| ERR008 | Sender ID banned | Use a different registered sender ID |
| ERR009 | Empty message | Provide non-empty message text |
| ERR010 | Zero balance | Recharge at kwtsms.com |
| ERR013 | Queue full | Wait and retry |
| ERR024 | IP not whitelisted | Add IP at kwtsms.com -> API -> IP Lockdown |
| ERR025 | Invalid number | Include country code |
| ERR026 | Country not active | Contact kwtSMS support |
| ERR028 | Rate limited | Wait 15 seconds before resending to same number |

All 28 error codes are mapped. Use `kwtsms.errors.getAction("ERR003")` to look up any code.

## Credential Management

**Never hardcode credentials.** Use one of these approaches:

### 1. Environment Variables / .env (recommended for servers)

```zig
var client = try kwtsms.KwtSMS.fromEnv(allocator, null);
```

### 2. Constructor Injection (for custom config systems)

```zig
var client = kwtsms.KwtSMS.init(allocator, username, password, sender, false, null);
```

### 3. Remote Config / Secrets Manager (recommended for production)

Load from AWS Secrets Manager, HashiCorp Vault, or your own config API, then pass to the constructor.

## Best Practices

### Always save msg-id and balance-after

```zig
if (resp.isOk()) {
    // Save immediately: you need msg-id for status/DLR, and balance-after
    // eliminates the need to call balance() separately
    db.save(resp.msg_id.?, resp.balance_after.?);
}
```

### Validate before calling the API

```zig
const validation = try kwtsms.validatePhoneInput(allocator, user_input);
if (!validation.valid) {
    // Return error to user without hitting the API
    return validation.err.?;
}
```

### Use Transactional Sender ID for OTP

Promotional sender IDs are blocked by DND (Do Not Disturb) on Zain and Ooredoo. OTP messages silently fail and credits are still deducted. Always use a Transactional sender ID for OTP/authentication messages.

### Server timezone

`unix-timestamp` in API responses is **GMT+3 (Asia/Kuwait)**, not UTC. Convert when storing.

### Sender ID

- `KWT-SMS` is for testing only. Delays, blocked on Virgin Kuwait.
- Sender ID is case-sensitive: `Kuwait` is not the same as `KUWAIT`.
- Register a private sender ID before going live.

## Security Checklist

Before deploying to production:

- [ ] Bot protection enabled (CAPTCHA for web)
- [ ] Rate limit per phone number (max 3-5/hour)
- [ ] Rate limit per IP address (max 10-20/hour)
- [ ] Rate limit per user/session if authenticated
- [ ] Monitoring/alerting on abuse patterns
- [ ] Admin notification on low balance
- [ ] Test mode OFF (`KWTSMS_TEST_MODE=0`)
- [ ] Private Sender ID registered (not `KWT-SMS`)
- [ ] Transactional Sender ID for OTP (not promotional)

## Test Mode

Set `test_mode=true` or `KWTSMS_TEST_MODE=1`. Messages are queued but not delivered. No credits consumed. Delete test messages from the queue at kwtsms.com to release held credits.

## Logging

JSONL format, one line per API call. Password is always masked as `***`.

```json
{"ts":"2026-03-06T12:00:00Z","endpoint":"send","request":{...},"response":{...},"ok":true,"error":null}
```

Set `log_file` to `""` to disable logging.

## Thread Safety

The `KwtSMS` client is thread-safe. Cached balance uses `std.Thread.Mutex` for synchronization. Each thread/goroutine can safely share a single client instance.

## Running Tests

```bash
# Unit tests (no network, no credentials)
zig build test

# Integration tests (requires API credentials)
ZIG_USERNAME=zig_username ZIG_PASSWORD=zig_password zig build test-integration
```

## Help and Support

- [API Documentation (PDF)](https://www.kwtsms.com/doc/KwtSMS.com_API_Documentation_v41.pdf)
- [Implementation Best Practices](https://www.kwtsms.com/articles/sms-api-implementation-best-practices.html)
- [Integration Test Checklist](https://www.kwtsms.com/articles/sms-api-integration-test-checklist.html)
- [Support Center](https://www.kwtsms.com/support.html)
- [WhatsApp Support](https://wa.me/96599220322): +965.9922-0322

## License

[MIT](LICENSE)
