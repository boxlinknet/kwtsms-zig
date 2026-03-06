# Example 04: Error Handling

Handle all API error paths with developer-friendly action messages.

## What it does

1. Demonstrates sending to an invalid phone number
2. Shows how to check `isOk()` and `isError()` on the response
3. Prints the error code, description, and action (fix suggestion)
4. Shows how to look up any error code via `kwtsms.errors.getAction()`

## Run

```bash
zig build example-04
./zig-out/bin/example-04
```

## Notes

- Every API error response includes an `action` field with a developer-friendly fix
- All 28 error codes are mapped to action messages
- Raw API errors should never be shown to end users (see User-facing error mapping in README)
- Use `resp.isError()` to check for errors, not string comparison
