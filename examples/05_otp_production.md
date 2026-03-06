# Example 05: Production OTP

Production-grade OTP service with rate limiting, secure code generation, and verification.

## What it does

1. Generates cryptographically secure OTP codes using `std.crypto.random`
2. Implements per-phone rate limiting (cooldown + hourly limit)
3. Validates phone numbers before sending
4. Sends OTP with app name included (telecom compliance)
5. Verifies OTP codes with attempt tracking and expiry
6. Invalidates codes after successful verification

## Run

```bash
zig build example-05
./zig-out/bin/example-05
```

## Security Checklist

Before deploying to production:

- Use a Transactional Sender ID (not KWT-SMS)
- Add CAPTCHA to your web form (Cloudflare Turnstile, hCaptcha)
- Store OTP hashes in your database (never plain text)
- Set `test_mode` to `false`
- Rate limit per phone number (max 3-5/hour)
- Rate limit per IP address (max 10-20/hour)
- Monitor for abuse patterns
- Set up low-balance alerts
