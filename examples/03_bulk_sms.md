# Example 03: Bulk SMS

Send SMS to multiple phone numbers with automatic deduplication.

## What it does

1. Creates a client in test mode
2. Defines a list of phone numbers in various formats (+prefix, 00prefix, plain)
3. Sends a single message to all numbers
4. The library automatically normalizes, deduplicates, and batches (>200 numbers)

## Run

```bash
zig build example-03
./zig-out/bin/example-03
```

## Notes

- Numbers are normalized: `+96598765432`, `0096598765432`, and `96598765432` are the same
- Duplicates after normalization are removed automatically
- Batches of >200 numbers are split with 0.5s delay between batches
- ERR013 (queue full) is retried automatically with exponential backoff
