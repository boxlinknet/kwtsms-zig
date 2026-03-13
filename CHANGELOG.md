# Changelog

All notable changes to kwtsms-zig are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [0.4.0] - 2026-03-13

### Changed
- Version bump. All security fixes and `ValidateResult` changes from this development cycle are now stable.

---

## [0.3.0] - 2026-03-13

### Added
- `ValidateResult` struct: `validate()` now returns locally-rejected numbers in a `rejected: []InvalidEntry` slice instead of silently discarding them. Call `result.deinit(allocator)` to free.
- `BulkSendResult.deinit(allocator)`: frees all heap-allocated batch data (`msg_ids`, `batch_errors`, `invalid`).
- `KwtSMS.deinit()`: frees strings loaded from a `.env` file when using `fromEnv()`.
- `EnvConfig.deinit(allocator)`: frees owned `.env` string copies via `_owned_*` flags.

### Security
- **H1** Phone validation lookup now uses the normalized (country-code-prefixed) number, preventing silent OTP misdelivery.
- **H2** Logger password-masking buffer widened from 4096 to 8192 bytes; large bodies are now masked instead of passed through in plaintext.
- **H3** JSONL error field is now properly JSON-quoted; bare text broke downstream parsers.
- **H4** `parsed.deinit()` called after JSON response parsing; `_ = parsed` leaked parse tree memory.
- **M1** All four request body builders rewritten to use `FixedBufferStream` + `writeJsonEscaped`, eliminating JSON injection via username/password/message.
- **M2** OOM window in `prepareNumbers` resolved: `valid_numbers.append` now precedes `seen.put`; failure rolls back and frees the allocation.
- **M3** `status()` and `dlr()` request buffers widened from 512 to 1024 bytes to fit long message IDs.
- **M4** `BulkSendResult` msg_ids were previously leaked; `deinit()` now frees them.
- **C1** `fromEnv()` strings (username, password, sender_id, log_file) are heap-duped and freed via `KwtSMS.deinit()`.
- **L1** OTP examples use `std.crypto.random.intRangeAtMost` (OS CSPRNG); removed timestamp-seeded PRNG.
- **L2** `EnvConfig` partial-alloc failure now cleaned up via `errdefer config.deinit(allocator)`.
- **L3** `validate()` returns rejected numbers instead of silently dropping them.

### Fixed
- `errors.zig` doc comment corrected: 28 documented error codes (not 33); ERR014-ERR018 are intentional gaps.

---

## [0.2.0] - 2026-03-07

### Added
- Country-specific phone number validation via `PhoneRule` lookup table (60+ countries, GCC through Oceania).
- `findCountryCode()`: longest-match country prefix extraction (3-digit, 2-digit, 1-digit).
- `validatePhoneFormat()`: per-country length and mobile-prefix validation.
- Saudi Arabia trunk prefix stripping (`0` prefix removal after country code detection).
- Full test suite for phone validation edge cases.

### Changed
- `std.ComptimeStringMap` replaced by `std.StaticStringMap(PhoneRule).initComptime(...)` for Zig 0.13 compatibility.

---

## [0.1.0] - 2026-03-06

### Added
- Initial release of the kwtSMS Zig client library.
- `KwtSMS.init()` and `KwtSMS.fromEnv()` client constructors.
- `send()`, `sendOne()`, `sendBulk()`, `validate()`, `balance()`, `purchased()`, `senderids()`, `coverage()`, `status()`, `dlr()` API methods.
- `cachedBalance()` and `cachedPurchased()` thread-safe cached accessors.
- `normalizePhone()` and `validatePhoneInput()` phone utilities.
- `cleanMessage()` message sanitizer (strips non-GSM characters, trims whitespace).
- JSONL request/response logger with password masking.
- 28 documented kwtSMS API error codes with human-readable descriptions and recommended actions.
- Error enrichment: automatic action field on all error responses.
- `.env` file support with environment variable priority.
- Thread-safe cached balance tracking.
- Number deduplication before API calls.
- Comprehensive unit tests (100+ test cases).
- Integration tests with `test_mode` support.
- CLI tool (`src/main.zig`) with all API commands.
- Six runnable examples (`examples/00` through `examples/05`).
- GitHub Actions: CI tests, format check, weekly cron, cross-platform release binaries.
- Zero external dependencies (Zig stdlib only).
