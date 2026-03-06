# Example 01: Basic Usage

Verify credentials, send a single SMS, and check balance.

## What it does

1. Creates a client with test mode enabled
2. Verifies credentials and prints the balance
3. Sends an SMS to a Kuwait number
4. Prints the message ID and remaining balance

## Run

```bash
zig build example-01
./zig-out/bin/example-01
```

## Notes

- Uses test mode: messages are queued but not delivered, no credits consumed
- Replace `zig_username` / `zig_password` with your API credentials
- Replace `YOUR-SENDER` with your registered Sender ID
