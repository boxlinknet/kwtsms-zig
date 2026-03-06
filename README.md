# kwtSMS Zig Client

[![CI](https://github.com/boxlinknet/kwtsms-zig/actions/workflows/ci.yml/badge.svg)](https://github.com/boxlinknet/kwtsms-zig/actions/workflows/ci.yml)
[![Release](https://github.com/boxlinknet/kwtsms-zig/actions/workflows/release.yml/badge.svg)](https://github.com/boxlinknet/kwtsms-zig/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.13%2B-orange.svg)](https://ziglang.org/)
[![GitHub release](https://img.shields.io/github/v/release/boxlinknet/kwtsms-zig)](https://github.com/boxlinknet/kwtsms-zig/releases)

Zig client for the [kwtSMS API](https://www.kwtsms.com). Send SMS, check balance, validate numbers, list sender IDs, check coverage, get delivery reports.

## About kwtSMS

kwtSMS is a Kuwaiti SMS gateway trusted by top businesses to deliver messages anywhere in the world, with private Sender ID, free API testing, non-expiring credits, and competitive flat-rate pricing. Secure, simple to integrate, built to last. Open a free account in under 1 minute, no paperwork or payment required. [Click here to get started](https://www.kwtsms.com/signup/)

## Prerequisites

You need **Zig 0.13+** to compile and run. Zero runtime dependencies.

### Step 1: Check if Zig is installed

```bash
zig version
```

If you see a version number, you're ready. If not, install Zig:

- **All platforms (recommended):** Download from [ziglang.org/download](https://ziglang.org/download/)
- **macOS:** `brew install zig`
- **Ubuntu/Debian:** Download the tarball from [ziglang.org](https://ziglang.org/download/) and add to PATH
- **Windows:** Download the zip from [ziglang.org](https://ziglang.org/download/) and add to PATH

### Step 2: Install kwtsms-zig

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

## Setup / Configuration

Create a `.env` file or set these environment variables:

```ini
KWTSMS_USERNAME=zig_username
KWTSMS_PASSWORD=zig_password
KWTSMS_SENDER_ID=YOUR-SENDER
KWTSMS_TEST_MODE=1
KWTSMS_LOG_FILE=kwtsms.log
```

Or pass credentials directly:

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

`KwtSMS.fromEnv()` reads environment variables first, falls back to `.env` file.

## Credential Management

**Never hardcode credentials.** Use one of these approaches:

1. **Environment variables / .env file** (default): `KwtSMS.fromEnv(allocator, null)` loads from env vars, then `.env` file. The file is `.gitignore`d and editable without redeployment.

2. **Constructor injection**: `KwtSMS.init(allocator, username, password, ...)` for custom config systems or remote config.

3. **Secrets manager**: Load from AWS Secrets Manager, HashiCorp Vault, Google Secret Manager, or your own config API, then pass to the constructor.

4. **Admin settings UI** (for web apps): Store credentials in your database with a settings page. Include a "Test Connection" button that calls `verify()`.

## All Methods

### Verify Credentials

```zig
const result = try client.verify();
if (result.ok) {
    std.debug.print("Balance: {d:.2}\n", .{result.balance.?});
} else {
    std.debug.print("Error: {s}\n", .{result.err.?});
}
```

### Send SMS

```zig
// Single number
const resp = try client.sendOne("96598765432", "Hello!", null);

// Multiple numbers
const mobiles = [_][]const u8{ "96598765432", "+96512345678", "0096587654321" };
const resp = try client.send(&mobiles, "Bulk message", null);

// Custom sender ID
const resp = try client.sendOne("96598765432", "Hello!", "MY-SENDER");

resp.result;        // "OK" or "ERROR"
resp.msg_id;        // message ID (save this!)
resp.numbers;       // count of numbers sent
resp.points_charged; // credits deducted
resp.balance_after; // balance after send (save this!)
resp.code;          // error code (e.g., "ERR003")
resp.description;   // error description
resp.action;        // developer-friendly action message
```

### Check Balance

```zig
const bal = try client.balance();
if (bal) |b| {
    std.debug.print("Balance: {d:.2}\n", .{b});
}
```

### Validate Numbers

```zig
const phones = [_][]const u8{ "96598765432", "invalid", "+96512345678" };
const resp = try client.validate(&phones);
```

### Sender IDs

```zig
const resp = try client.senderids();
```

### Coverage

```zig
const resp = try client.coverage();
```

### Message Status

```zig
const resp = try client.status("f4c841adee210f31307633ceaebff2ec");
```

### Delivery Report (international only)

```zig
const resp = try client.dlr("f4c841adee210f31307633ceaebff2ec");
```

## Utility Functions

```zig
const kwtsms = @import("kwtsms");

// Normalize phone number
const normalized = try kwtsms.normalizePhone(allocator, "+965 9876-5432");
defer allocator.free(normalized);
// normalized = "96598765432"

// Validate phone input
const result = try kwtsms.validatePhoneInput(allocator, "user@example.com");
// result.valid = false, result.err = "This looks like an email address, not a phone number"

// Clean message text
const cleaned = try kwtsms.cleanMessage(allocator, "Hello \xF0\x9F\x98\x80 <b>bold</b>");
defer allocator.free(cleaned);
// cleaned = "Hello  bold"
```

## Input Sanitization

`cleanMessage()` is called automatically by `send()` before every API call. It prevents the #1 cause of "message sent but not received" support tickets:

| Content | Effect without cleaning | What cleanMessage() does |
|---------|------------------------|--------------------------|
| Emojis | Stuck in queue, credits wasted, no error | Stripped |
| Hidden control characters (BOM, zero-width space, soft hyphen) | Spam filter rejection or queue stuck | Stripped |
| Arabic/Hindi numerals in body | OTP codes render inconsistently | Converted to Latin digits |
| HTML tags | ERR027, message rejected | Stripped |
| Directional marks (LTR, RTL) | May cause display issues | Stripped |

Arabic letters and Arabic text are fully supported and never stripped.

## Error Handling

Every ERROR response includes an `action` field with a developer-friendly fix:

```zig
const resp = try client.sendOne("96598765432", "Test", null);
if (resp.isError()) {
    std.debug.print("[{s}] {s}\n", .{ resp.code.?, resp.description.? });
    if (resp.action) |action| {
        std.debug.print("Fix: {s}\n", .{action});
    }
}
```

### User-facing error mapping

Raw API errors should never be shown to end users. Map them:

| Situation | API error | Show to user |
|-----------|----------|--------------|
| Invalid phone number | ERR006, ERR025 | "Please enter a valid phone number in international format (e.g., +965 9876 5432)." |
| Wrong credentials | ERR003 | "SMS service is temporarily unavailable. Please try again later." (log + alert admin) |
| No balance | ERR010, ERR011 | "SMS service is temporarily unavailable. Please try again later." (alert admin) |
| Country not supported | ERR026 | "SMS delivery to this country is not available." |
| Rate limited | ERR028 | "Please wait a moment before requesting another code." |
| Message rejected | ERR031, ERR032 | "Your message could not be sent. Please try again with different content." |
| Queue full | ERR013 | "SMS service is busy. Please try again in a few minutes." (library retries automatically) |
| Network error | Connection timeout | "Could not connect to SMS service." |

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

## Phone Number Formats

All formats are accepted and normalized automatically:

| Input | Normalized | Valid? |
|-------|-----------|--------|
| `96598765432` | `96598765432` | Yes |
| `+96598765432` | `96598765432` | Yes |
| `0096598765432` | `96598765432` | Yes |
| `965 9876 5432` | `96598765432` | Yes |
| `965-9876-5432` | `96598765432` | Yes |
| `(965) 98765432` | `96598765432` | Yes |
| `٩٦٥٩٨٧٦٥٤٣٢` | `96598765432` | Yes |
| `۹۶۵۹۸۷۶۵۴۳۲` | `96598765432` | Yes |
| `+٩٦٥٩٨٧٦٥٤٣٢` | `96598765432` | Yes |
| `٠٠٩٦٥٩٨٧٦٥٤٣٢` | `96598765432` | Yes |
| `٩٦٥ ٩٨٧٦ ٥٤٣٢` | `96598765432` | Yes |
| `٩٦٥-٩٨٧٦-٥٤٣٢` | `96598765432` | Yes |
| `965٩٨٧٦٥٤٣٢` | `96598765432` | Yes |
| `123456` (too short) | rejected | No |
| `user@gmail.com` | rejected | No |

### Test Numerals

Use these for copy-paste testing of Arabic/Persian digit normalization:

| Script | Digits | Example Phone |
|--------|--------|---------------|
| Latin | `0123456789` | `96598765432` |
| Arabic-Indic | `٠١٢٣٤٥٦٧٨٩` | `٩٦٥٩٨٧٦٥٤٣٢` |
| Extended Arabic-Indic (Persian/Urdu) | `۰۱۲۳۴۵۶۷۸۹` | `۹۶۵۱۲۳۴۵۶۷۸` |
| Mixed (Arabic-Indic + Latin) | | `٩٦٥98765٤٣٢` |

All variants normalize to Latin digits before sending.

## Test Mode

**Test mode** (`KWTSMS_TEST_MODE=1`) sends your message to the kwtSMS queue but does NOT deliver it to the handset. No SMS credits are consumed. Use this during development.

**Live mode** (`KWTSMS_TEST_MODE=0`) delivers the message for real and deducts credits. Always develop in test mode and switch to live only when ready for production.

## Sender ID

A **Sender ID** is the name that appears as the sender on the recipient's phone (e.g., "MY-APP" instead of a random number).

| | Promotional | Transactional |
|--|-------------|---------------|
| **Use for** | Bulk SMS, marketing, offers | OTP, alerts, notifications |
| **Delivery to DND numbers** | Blocked/filtered, credits lost | Bypasses DND (whitelisted) |
| **Speed** | May have delays | Priority delivery |
| **Cost** | 10 KD one-time | 15 KD one-time |

`KWT-SMS` is a shared test sender. It causes delivery delays, is blocked on Virgin Kuwait, and should never be used in production. Register your own private Sender ID through your kwtSMS account. For OTP/authentication messages, you need a **Transactional** Sender ID to bypass DND (Do Not Disturb) filtering. Sender ID is **case sensitive**.

## Best Practices

### Always save msg-id and balance-after

```zig
if (resp.isOk()) {
    // Save immediately: you need msg-id for status/DLR, and balance-after
    // eliminates the need to call balance() separately
    db.save(resp.msg_id.?, resp.balance_after.?);
}
```

### Validate locally before calling the API

```zig
const validation = try kwtsms.validatePhoneInput(allocator, user_input);
if (!validation.valid) {
    // Return error to user without hitting the API
    return validation.err.?;
}
```

### OTP requirements

- Always include app/company name: `"Your OTP for APPNAME is: 123456"`
- Resend timer: minimum 3-4 minutes (KNET standard is 4 minutes)
- OTP expiry: 3-5 minutes
- New code on resend: always generate a fresh code, invalidate previous
- Use Transactional Sender ID for OTP (not Promotional, not KWT-SMS)
- One number per OTP request: never batch OTP sends

### Thread safety

The `KwtSMS` client is thread-safe. Cached balance uses `std.Thread.Mutex` for synchronization. Create one instance and share it across threads.

## Timestamps

`unix-timestamp` values in API responses are in **GMT+3 (Asia/Kuwait)** server time, not UTC. Convert when storing or displaying.

## Security Checklist

Before going live:

- [ ] Bot protection enabled (CAPTCHA for web)
- [ ] Rate limit per phone number (max 3-5/hour)
- [ ] Rate limit per IP address (max 10-20/hour)
- [ ] Rate limit per user/session if authenticated
- [ ] Monitoring/alerting on abuse patterns
- [ ] Admin notification on low balance
- [ ] Test mode OFF (`KWTSMS_TEST_MODE=0`)
- [ ] Private Sender ID registered (not `KWT-SMS`)
- [ ] Transactional Sender ID for OTP (not promotional)

## What's Handled Automatically

- **Phone normalization**: `+`, `00`, spaces, dashes, dots, parentheses stripped. Arabic-Indic digits converted. Leading zeros removed.
- **Duplicate phone removal**: If the same number appears multiple times (in different formats), it is sent only once.
- **Message cleaning**: Emojis removed (codepoint-safe). Hidden control characters (BOM, zero-width spaces, directional marks) removed. HTML tags stripped. Arabic-Indic digits in message body converted to Latin.
- **Batch splitting**: More than 200 numbers are automatically split into batches of 200 with 0.5s delay between batches.
- **ERR013 retry**: Queue-full errors are automatically retried up to 3 times with exponential backoff (30s / 60s / 120s).
- **Error enrichment**: Every API error response includes an `action` field with a developer-friendly fix hint.
- **Credential masking**: Passwords are always masked as `***` in log files. Never exposed.
- **Balance caching**: Balance is cached from every `verify()` and `send()` response. `balance()` falls back to the cached value on API failure.

## Examples

See the [`examples/`](examples/) directory:

| Example | Description |
|---------|-------------|
| [01_basic_usage](examples/01_basic_usage.zig) | Verify credentials, send SMS, check balance |
| [02_otp_flow](examples/02_otp_flow.zig) | Validate phone, send OTP with best practices |
| [03_bulk_sms](examples/03_bulk_sms.zig) | Bulk send with >200 number batching |
| [04_error_handling](examples/04_error_handling.zig) | All error paths, user-facing message mapping |
| [05_otp_production](examples/05_otp_production.zig) | Production OTP: rate limiting, expiry, secure code generation |

Build and run an example: `zig build example-01`

## Testing

```bash
# Unit tests (no credentials needed)
zig build test

# Integration tests (real API, test mode, no credits consumed)
ZIG_USERNAME=zig_username ZIG_PASSWORD=zig_password zig build test-integration
```

## Logging

JSONL format, one line per API call. Password is always masked as `***`.

```json
{"ts":"2026-03-06T12:00:00Z","endpoint":"send","request":{...},"response":{...},"ok":true,"error":null}
```

Set `log_file` to `""` to disable logging.

## FAQ

**1. My message was sent successfully (result: OK) but the recipient didn't receive it. What happened?**

Check the **Sending Queue** at [kwtsms.com](https://www.kwtsms.com/login/). If your message is stuck there, it was accepted by the API but not dispatched. Common causes are emoji in the message, hidden characters from copy-pasting, or spam filter triggers. Delete it from the queue to recover your credits. Also verify that `test` mode is off (`KWTSMS_TEST_MODE=0`). Test messages are queued but never delivered.

**2. What is the difference between Test mode and Live mode?**

**Test mode** (`KWTSMS_TEST_MODE=1`) sends your message to the kwtSMS queue but does NOT deliver it to the handset. No SMS credits are consumed. Use this during development. **Live mode** (`KWTSMS_TEST_MODE=0`) delivers the message for real and deducts credits. Always develop in test mode and switch to live only when ready for production.

**3. What is a Sender ID and why should I not use "KWT-SMS" in production?**

A **Sender ID** is the name that appears as the sender on the recipient's phone (e.g., "MY-APP" instead of a random number). `KWT-SMS` is a shared test sender. It causes delivery delays, is blocked on Virgin Kuwait, and should never be used in production. Register your own private Sender ID through your kwtSMS account. For OTP/authentication messages, you need a **Transactional** Sender ID to bypass DND (Do Not Disturb) filtering.

**4. I'm getting ERR003 "Authentication error". What's wrong?**

You are using the wrong credentials. The API requires your **API username and API password**, NOT your account mobile number. Log in to [kwtsms.com](https://www.kwtsms.com/login/), go to Account, and check your API credentials. Also make sure you are using POST (not GET) and `Content-Type: application/json`.

**5. Can I send to international numbers (outside Kuwait)?**

International sending is **disabled by default** on kwtSMS accounts. Contact kwtSMS support to request activation for specific country prefixes. Use `coverage()` to check which countries are currently active on your account. Be aware that activating international coverage increases exposure to automated abuse. Implement rate limiting and CAPTCHA before enabling.

## Help & Support

- **[kwtSMS FAQ](https://www.kwtsms.com/faq/)**: Answers to common questions about credits, sender IDs, OTP, and delivery
- **[kwtSMS Support](https://www.kwtsms.com/support.html)**: Open a support ticket or browse help articles
- **[Contact kwtSMS](https://www.kwtsms.com/#contact)**: Reach the kwtSMS team directly for Sender ID registration and account issues
- **[API Documentation (PDF)](https://www.kwtsms.com/doc/KwtSMS.com_API_Documentation_v41.pdf)**: kwtSMS REST API v4.1 full reference
- **[Best Practices](https://www.kwtsms.com/articles/sms-api-implementation-best-practices.html)**: SMS API implementation best practices
- **[Integration Test Checklist](https://www.kwtsms.com/articles/sms-api-integration-test-checklist.html)**: Pre-launch testing checklist
- **[Sender ID Help](https://www.kwtsms.com/sender-id-help.html)**: How to register, whitelist, and troubleshoot sender IDs
- **[kwtSMS Dashboard](https://www.kwtsms.com/login/)**: Recharge credits, buy Sender IDs, view message logs, manage coverage
- **[Other Integrations](https://www.kwtsms.com/integrations.html)**: Plugins and integrations for other platforms and languages

## License

[MIT](LICENSE)
