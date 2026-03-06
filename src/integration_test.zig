const std = @import("std");
const kwtsms = @import("kwtsms");

// Integration tests: hit the live kwtSMS API with test_mode=true.
// Skipped if ZIG_USERNAME / ZIG_PASSWORD are not set.
// Run with: zig build test-integration

fn getTestCredentials() ?struct { username: []const u8, password: []const u8 } {
    const username = std.posix.getenv("ZIG_USERNAME") orelse return null;
    const password = std.posix.getenv("ZIG_PASSWORD") orelse return null;
    if (username.len == 0 or password.len == 0) return null;
    return .{ .username = username, .password = password };
}

test "integration: verify with valid credentials" {
    const creds = getTestCredentials() orelse return; // skip
    const allocator = std.testing.allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const result = try client.verify();
    try std.testing.expect(result.ok);
    try std.testing.expect(result.balance != null);
    try std.testing.expect(result.balance.? >= 0);
}

test "integration: verify with wrong credentials" {
    _ = getTestCredentials() orelse return; // skip if no creds at all
    const allocator = std.testing.allocator;
    var client = kwtsms.KwtSMS.init(allocator, "zig_wrong_user", "zig_wrong_pass", null, true, "");
    const result = try client.verify();
    try std.testing.expect(!result.ok);
    try std.testing.expect(result.err != null);
}

test "integration: balance returns a number" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.testing.allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const bal = try client.balance();
    try std.testing.expect(bal != null);
    try std.testing.expect(bal.? >= 0);
}

test "integration: send to valid Kuwait number (test mode)" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.testing.allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const resp = try client.sendOne("96598765432", "Test from kwtsms-zig integration test", null);
    // In test mode, API should accept the message
    // It may return OK or an error depending on the sender ID and number
    try std.testing.expect(resp.result.len > 0);
}

test "integration: send rejects email input" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.testing.allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const resp = try client.sendOne("user@example.com", "Test", null);
    try std.testing.expect(resp.isError());
}

test "integration: send rejects too-short number" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.testing.allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const resp = try client.sendOne("123", "Test", null);
    try std.testing.expect(resp.isError());
}

test "integration: send handles + prefix normalization" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.testing.allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const resp = try client.sendOne("+96598765432", "Normalization test", null);
    try std.testing.expect(resp.result.len > 0);
}

test "integration: send handles 00 prefix normalization" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.testing.allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const resp = try client.sendOne("0096598765432", "Normalization test", null);
    try std.testing.expect(resp.result.len > 0);
}

test "integration: senderids returns a response" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.testing.allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const resp = try client.senderids();
    try std.testing.expect(resp.result.len > 0);
}

test "integration: coverage returns a response" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.testing.allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const resp = try client.coverage();
    try std.testing.expect(resp.result.len > 0);
}

test "integration: emoji-only message returns error" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.testing.allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const resp = try client.sendOne("96598765432", "\xF0\x9F\x98\x80\xF0\x9F\x98\x82", null);
    try std.testing.expect(resp.isError());
    try std.testing.expectEqualStrings("ERR009", resp.code.?);
}

test "integration: send handles Arabic-Indic digit phone number" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.testing.allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    // ٩٦٥٩٨٧٦٥٤٣٢ = 96598765432
    const resp = try client.sendOne("\xD9\xA9\xD9\xA6\xD9\xA5\xD9\xA9\xD9\xA8\xD9\xA7\xD9\xA6\xD9\xA5\xD9\xA4\xD9\xA3\xD9\xA2", "Arabic numeral test", null);
    try std.testing.expect(resp.result.len > 0);
}

test "integration: send handles Extended Arabic-Indic (Persian) digit phone number" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.testing.allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    // ۹۶۵۱۲۳۴۵۶۷۸ = 96512345678
    const resp = try client.sendOne("\xDB\xB9\xDB\xB6\xDB\xB5\xDB\xB1\xDB\xB2\xDB\xB3\xDB\xB4\xDB\xB5\xDB\xB6\xDB\xB7\xDB\xB8", "Persian numeral test", null);
    try std.testing.expect(resp.result.len > 0);
}

test "integration: send handles mixed Arabic-Indic and Latin digits" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.testing.allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    // ٩٦٥98765٤٣٢ = 96598765432 (mixed Arabic-Indic and Latin)
    const resp = try client.sendOne("\xD9\xA9\xD9\xA6\xD9\xA598765\xD9\xA4\xD9\xA3\xD9\xA2", "Mixed numeral test", null);
    try std.testing.expect(resp.result.len > 0);
}

test "integration: duplicate numbers deduplicated" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.testing.allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const mobiles = [_][]const u8{ "+96598765432", "0096598765432", "96598765432" };
    const resp = try client.send(&mobiles, "Dedup test", null);
    // All three normalize to the same number, should send only once
    try std.testing.expect(resp.result.len > 0);
    if (resp.numbers) |n| {
        try std.testing.expectEqual(@as(i64, 1), n);
    }
}
