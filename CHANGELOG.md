# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-03-06

### Added

- Initial release of kwtsms-zig client library
- KwtSMS client with all API methods: verify, balance, send, validate, senderids, coverage, status, dlr
- Phone number normalization: Arabic/Persian digit conversion, prefix stripping, deduplication
- Phone number validation: email detection, length checks, format validation
- Message cleaning: emoji removal, HTML stripping, control character removal, Arabic digit conversion
- All 28 kwtSMS API error codes mapped with developer-friendly action messages
- Error enrichment: automatic action field on all error responses
- .env file support with environment variable priority
- JSONL logging with password masking
- Thread-safe cached balance tracking
- Number deduplication before API calls
- Comprehensive unit tests (70+ test cases)
- Integration tests with test_mode support
- 5 runnable examples including production OTP flow
- CI/CD with GitHub Actions
- CodeQL security scanning
- Zero external dependencies (Zig stdlib only)
