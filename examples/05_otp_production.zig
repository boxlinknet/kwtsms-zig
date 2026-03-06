const std = @import("std");
const kwtsms = @import("kwtsms");

/// Production-grade OTP service with rate limiting and secure code generation.
///
/// Before deploying to production:
/// - Use a Transactional Sender ID (not KWT-SMS)
/// - Add CAPTCHA to your web form (Cloudflare Turnstile, hCaptcha, etc.)
/// - Store OTP hashes in your database (never plain text)
/// - Set test_mode to false
///
/// SECURITY CHECKLIST:
/// [ ] Bot protection enabled (CAPTCHA for web, Device Attestation for mobile)
/// [ ] Rate limit per phone number (max 3-5/hour)
/// [ ] Rate limit per IP address (max 10-20/hour)
/// [ ] Rate limit per user/session if authenticated
/// [ ] Monitoring/alerting on abuse patterns
/// [ ] Admin notification on low balance
/// [ ] Test mode OFF (KWTSMS_TEST_MODE=0)
/// [ ] Private Sender ID registered (not KWT-SMS)
/// [ ] Transactional Sender ID for OTP (not promotional)

const OtpConfig = struct {
    app_name: []const u8 = "MyApp",
    otp_length: u8 = 6,
    expiry_seconds: i64 = 300, // 5 minutes
    resend_cooldown_seconds: i64 = 240, // 4 minutes (KNET standard)
    max_attempts_per_phone: u8 = 5,
    max_attempts_per_hour: u8 = 3,
};

const OtpEntry = struct {
    code: [6]u8,
    created_at: i64,
    attempts: u8,
};

/// In-memory OTP store (use a database in production).
var otp_store: std.StringHashMap(OtpEntry) = undefined;
var last_send: std.StringHashMap(i64) = undefined;
var send_count: std.StringHashMap(u8) = undefined;
var initialized = false;

fn initStores(allocator: std.mem.Allocator) void {
    if (!initialized) {
        otp_store = std.StringHashMap(OtpEntry).init(allocator);
        last_send = std.StringHashMap(i64).init(allocator);
        send_count = std.StringHashMap(u8).init(allocator);
        initialized = true;
    }
}

/// Generate a cryptographically secure OTP code.
fn generateOtp(config: OtpConfig) [6]u8 {
    var code: [6]u8 = undefined;
    var seed: [8]u8 = undefined;
    std.crypto.random.bytes(&seed);
    var prng = std.Random.DefaultPrng.init(@bitCast(seed));
    const random = prng.random();
    for (code[0..config.otp_length]) |*c| {
        c.* = '0' + random.intRangeAtMost(u8, 0, 9);
    }
    return code;
}

/// Send OTP with rate limiting and validation.
fn sendOtp(
    allocator: std.mem.Allocator,
    client: *kwtsms.KwtSMS,
    phone: []const u8,
    config: OtpConfig,
) !struct { ok: bool, err: ?[]const u8, msg_id: ?[]const u8 } {
    initStores(allocator);

    // Validate phone number
    const validation = try kwtsms.validatePhoneInput(allocator, phone);
    if (!validation.valid) {
        return .{ .ok = false, .err = validation.err, .msg_id = null };
    }
    defer if (validation.normalized.len > 0) allocator.free(@constCast(validation.normalized));

    // Rate limit: cooldown check
    const now = std.time.timestamp();
    if (last_send.get(validation.normalized)) |last_time| {
        const elapsed = now - last_time;
        if (elapsed < config.resend_cooldown_seconds) {
            return .{ .ok = false, .err = "Please wait before requesting another code", .msg_id = null };
        }
    }

    // Rate limit: hourly limit
    if (send_count.get(validation.normalized)) |count| {
        if (count >= config.max_attempts_per_hour) {
            return .{ .ok = false, .err = "Too many OTP requests. Try again later", .msg_id = null };
        }
    }

    // Generate OTP
    const code = generateOtp(config);

    // Build message with app name (telecom compliance requirement)
    var msg_buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&msg_buf, "Your OTP for {s} is: {s}. Valid for {d} minutes.", .{
        config.app_name,
        code[0..config.otp_length],
        @divTrunc(config.expiry_seconds, 60),
    }) catch return .{ .ok = false, .err = "Failed to format message", .msg_id = null };

    // Send via kwtSMS
    const resp = try client.sendOne(validation.normalized, msg, null);

    if (resp.isOk()) {
        // Store OTP (in production, store a hash, not the plain code)
        try otp_store.put(validation.normalized, OtpEntry{
            .code = code,
            .created_at = now,
            .attempts = 0,
        });

        // Update rate limit tracking
        try last_send.put(validation.normalized, now);
        const current_count = send_count.get(validation.normalized) orelse 0;
        try send_count.put(validation.normalized, current_count + 1);

        return .{ .ok = true, .err = null, .msg_id = resp.msg_id };
    }

    return .{ .ok = false, .err = resp.description, .msg_id = null };
}

/// Verify an OTP code.
fn verifyOtp(
    phone: []const u8,
    code: []const u8,
    config: OtpConfig,
) struct { ok: bool, err: ?[]const u8 } {
    const entry = otp_store.get(phone) orelse {
        return .{ .ok = false, .err = "No OTP was sent to this number" };
    };

    // Check expiry
    const now = std.time.timestamp();
    if (now - entry.created_at > config.expiry_seconds) {
        _ = otp_store.fetchRemove(phone);
        return .{ .ok = false, .err = "OTP has expired. Request a new one" };
    }

    // Check attempts
    if (entry.attempts >= config.max_attempts_per_phone) {
        _ = otp_store.fetchRemove(phone);
        return .{ .ok = false, .err = "Too many failed attempts. Request a new OTP" };
    }

    // Verify code
    if (code.len == config.otp_length and std.mem.eql(u8, code, entry.code[0..config.otp_length])) {
        _ = otp_store.fetchRemove(phone); // Invalidate after successful verification
        return .{ .ok = true, .err = null };
    }

    // Wrong code: increment attempts
    var updated = entry;
    updated.attempts += 1;
    otp_store.put(phone, updated) catch {};
    return .{ .ok = false, .err = "Invalid OTP code" };
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create client (use Transactional Sender ID for OTP)
    var client = kwtsms.KwtSMS.init(
        allocator,
        "your_api_user",
        "your_api_pass",
        "YOUR-TXN-SENDER", // Transactional sender ID
        true, // set to false in production
        null,
    );

    const config = OtpConfig{
        .app_name = "MyApp",
    };

    // Send OTP
    const send_result = try sendOtp(allocator, &client, "+96598765432", config);
    if (send_result.ok) {
        std.debug.print("OTP sent. msg-id: {s}\n", .{send_result.msg_id.?});
    } else {
        std.debug.print("Failed to send OTP: {s}\n", .{send_result.err.?});
    }

    // Verify OTP (in your verification endpoint)
    const verify_result = verifyOtp("96598765432", "123456", config);
    if (verify_result.ok) {
        std.debug.print("OTP verified successfully\n", .{});
    } else {
        std.debug.print("OTP verification failed: {s}\n", .{verify_result.err.?});
    }
}
