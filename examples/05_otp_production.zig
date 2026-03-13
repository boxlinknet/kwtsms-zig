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
/// Keys are heap-allocated normalized phone numbers owned by these maps.
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
/// L1 fix: use std.crypto.random directly instead of seeding a PRNG.
/// A PRNG seeded from even a secure seed leaks its full state after one observed output.
fn generateOtp(config: OtpConfig) [6]u8 {
    var code: [6]u8 = undefined;
    for (code[0..config.otp_length]) |*c| {
        c.* = '0' + std.crypto.random.intRangeAtMost(u8, 0, 9);
    }
    return code;
}

/// Send OTP with rate limiting and validation.
/// C2 fix: validation.normalized is NOT defer-freed here. On success it is transferred
/// as a key to the hash maps (which own it for the process lifetime). On failure it is
/// freed explicitly before returning.
fn sendOtp(
    allocator: std.mem.Allocator,
    client: *kwtsms.KwtSMS,
    phone: []const u8,
    config: OtpConfig,
) !struct { ok: bool, err: ?[]const u8, msg_id: ?[]const u8 } {
    initStores(allocator);

    // Validate and normalize phone number
    const validation = try kwtsms.validatePhoneInput(allocator, phone);
    if (!validation.valid) {
        // normalized may be non-empty even on failure (partial normalization)
        if (validation.normalized.len > 0) allocator.free(@constCast(validation.normalized));
        return .{ .ok = false, .err = validation.err, .msg_id = null };
    }
    // From here: validation.normalized is a heap allocation we must manage.
    // On any failure path below, free it. On success, maps own it.
    const normalized = validation.normalized;

    // Rate limit: cooldown check
    const now = std.time.timestamp();
    if (last_send.get(normalized)) |last_time| {
        const elapsed = now - last_time;
        if (elapsed < config.resend_cooldown_seconds) {
            allocator.free(@constCast(normalized));
            return .{ .ok = false, .err = "Please wait before requesting another code", .msg_id = null };
        }
    }

    // Rate limit: hourly limit
    if (send_count.get(normalized)) |count| {
        if (count >= config.max_attempts_per_hour) {
            allocator.free(@constCast(normalized));
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
    }) catch {
        allocator.free(@constCast(normalized));
        return .{ .ok = false, .err = "Failed to format message", .msg_id = null };
    };

    // Send via kwtSMS
    const resp = client.sendOne(normalized, msg, null) catch {
        allocator.free(@constCast(normalized));
        return .{ .ok = false, .err = "Failed to send SMS", .msg_id = null };
    };

    if (resp.isOk()) {
        // Store OTP keyed by normalized phone. Use getOrPut to handle re-sends to the same number:
        // if the key already exists, the map retains its existing allocation and we free ours.
        const gop = try otp_store.getOrPut(normalized);
        const canonical_key: []const u8 = if (gop.found_existing) blk: {
            allocator.free(@constCast(normalized)); // map keeps old allocation
            break :blk gop.key_ptr.*;
        } else normalized; // map now owns normalized

        gop.value_ptr.* = OtpEntry{
            .code = code,
            .created_at = now,
            .attempts = 0,
        };

        // Update rate limit tracking using the canonical key
        try last_send.put(canonical_key, now);
        const current_count = send_count.get(canonical_key) orelse 0;
        try send_count.put(canonical_key, current_count + 1);

        return .{ .ok = true, .err = null, .msg_id = resp.msg_id };
    }

    allocator.free(@constCast(normalized));
    return .{ .ok = false, .err = resp.description, .msg_id = null };
}

/// Verify an OTP code.
/// H1 fix: normalize the phone number before looking it up so the key matches
/// what sendOtp stored (e.g., "+96598765432" and "96598765432" both normalize to
/// "96598765432" and will hit the same map entry).
fn verifyOtp(
    allocator: std.mem.Allocator,
    phone: []const u8,
    code: []const u8,
    config: OtpConfig,
) !struct { ok: bool, err: ?[]const u8 } {
    const validation = try kwtsms.validatePhoneInput(allocator, phone);
    defer if (validation.normalized.len > 0) allocator.free(@constCast(validation.normalized));
    if (!validation.valid) return .{ .ok = false, .err = validation.err };

    const normalized = validation.normalized;

    const entry = otp_store.get(normalized) orelse {
        return .{ .ok = false, .err = "No OTP was sent to this number" };
    };

    // Check expiry
    const now = std.time.timestamp();
    if (now - entry.created_at > config.expiry_seconds) {
        _ = otp_store.fetchRemove(normalized);
        return .{ .ok = false, .err = "OTP has expired. Request a new one" };
    }

    // Check attempts
    if (entry.attempts >= config.max_attempts_per_phone) {
        _ = otp_store.fetchRemove(normalized);
        return .{ .ok = false, .err = "Too many failed attempts. Request a new OTP" };
    }

    // Verify code
    if (code.len == config.otp_length and std.mem.eql(u8, code, entry.code[0..config.otp_length])) {
        _ = otp_store.fetchRemove(normalized); // Invalidate after successful verification
        return .{ .ok = true, .err = null };
    }

    // Wrong code: increment attempts
    var updated = entry;
    updated.attempts += 1;
    otp_store.put(normalized, updated) catch {};
    return .{ .ok = false, .err = "Invalid OTP code" };
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create client (use Transactional Sender ID for OTP)
    var client = kwtsms.KwtSMS.init(
        allocator,
        "zig_username",
        "zig_password",
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

    // Verify OTP: normalize phone before lookup so "+96598765432" matches "96598765432"
    const verify_result = try verifyOtp(allocator, "+96598765432", "123456", config);
    if (verify_result.ok) {
        std.debug.print("OTP verified successfully\n", .{});
    } else {
        std.debug.print("OTP verification failed: {s}\n", .{verify_result.err.?});
    }
}
