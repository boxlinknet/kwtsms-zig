# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this library, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, email security concerns to: **support@kwtsms.com**

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge your report within 48 hours and provide a timeline for a fix.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.1.x   | Yes       |

## Security Best Practices

When using this library:

- Never hardcode API credentials in source code
- Use environment variables or `.env` files for credentials
- Add `.env` to `.gitignore`
- Use HTTPS only (enforced by this library)
- Mask credentials in logs (handled automatically by this library)
- Implement rate limiting before production deployment
- Use a Transactional Sender ID for OTP messages
