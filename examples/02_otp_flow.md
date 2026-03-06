# Example 02: OTP Flow

Generate and send a one-time password (OTP) via SMS.

## What it does

1. Creates a client with a Transactional Sender ID
2. Generates a 6-digit OTP code
3. Formats the OTP message with app name (telecom compliance)
4. Sends the OTP to a single phone number
5. Prints the message ID for status tracking

## Run

```bash
zig build example-02
./zig-out/bin/example-02
```

## Notes

- Always include the app name in OTP messages (telecom requirement)
- Use a Transactional Sender ID for OTP (not Promotional, not KWT-SMS)
- In production, use `std.crypto.random` instead of timestamp-seeded PRNG
- Store the OTP hash (not plain text) in your database
- Set a 3-5 minute expiry on OTP codes
