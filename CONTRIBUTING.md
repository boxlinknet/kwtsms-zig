# Contributing to kwtsms-zig

## Development Setup

### Prerequisites

- [Zig 0.13+](https://ziglang.org/download/)

### Build and Test

```bash
# Build the library
zig build

# Run unit tests
zig build test

# Run integration tests (requires credentials)
ZIG_USERNAME=your_user ZIG_PASSWORD=your_pass zig build test-integration
```

## Project Structure

```
src/
  kwtsms.zig      Main client module (public API)
  phone.zig       Phone normalization and validation
  message.zig     Message cleaning (emojis, HTML, control chars)
  errors.zig      API error codes and enrichment
  request.zig     HTTP request layer
  env.zig         .env file loading
  logger.zig      JSONL logging
  integration_test.zig  Live API tests
examples/         Runnable example programs
```

## Code Style

- Follow [Zig style guide](https://ziglang.org/documentation/master/#Style-Guide)
- Use `std.testing.allocator` in tests for leak detection
- All public functions must have doc comments
- Tests are colocated in each source file

## Branch Naming

- `feat/description` for new features
- `fix/description` for bug fixes
- `docs/description` for documentation
- `test/description` for test improvements
- `chore/description` for maintenance

## Commit Style

Use conventional commits:
- `feat: add bulk send support`
- `fix: handle empty phone number`
- `docs: update README examples`
- `test: add coverage endpoint tests`

## Pull Request Process

1. Fork the repository
2. Create a feature branch from `main`
3. Write tests for new functionality
4. Ensure all tests pass: `zig build test`
5. Update documentation if needed
6. Submit a PR with a clear description

## Adding a New API Method

1. Add the method to `KwtSMS` struct in `src/kwtsms.zig`
2. Add request builder in `src/request.zig` if needed
3. Add tests in the source file
4. Add integration test in `src/integration_test.zig`
5. Update README with usage example
6. Update CHANGELOG.md

## Testing

- Unit tests: no network, no credentials, test pure functions
- Integration tests: require `ZIG_USERNAME`/`ZIG_PASSWORD`, always use `test_mode=true`
- Use `std.testing.allocator` to catch memory leaks
