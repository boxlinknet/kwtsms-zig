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
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const result = try client.verify();
    try std.testing.expect(result.ok);
    try std.testing.expect(result.balance != null);
    try std.testing.expect(result.balance.? >= 0);
}

test "integration: verify with wrong credentials" {
    _ = getTestCredentials() orelse return; // skip if no creds at all
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, "zig_wrong_user", "zig_wrong_pass", null, true, "");
    const result = try client.verify();
    try std.testing.expect(!result.ok);
    try std.testing.expect(result.err != null);
}

test "integration: balance returns a number" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const bal = try client.balance();
    try std.testing.expect(bal != null);
    try std.testing.expect(bal.? >= 0);
}

test "integration: send to valid Kuwait number (test mode)" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const resp = try client.sendOne("96598765432", "Test from kwtsms-zig integration test", null);
    // In test mode, API should accept the message
    // It may return OK or an error depending on the sender ID and number
    try std.testing.expect(resp.result.len > 0);
}

test "integration: send rejects email input" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const resp = try client.sendOne("user@example.com", "Test", null);
    try std.testing.expect(resp.isError());
}

test "integration: send rejects too-short number" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const resp = try client.sendOne("123", "Test", null);
    try std.testing.expect(resp.isError());
}

test "integration: send handles + prefix normalization" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const resp = try client.sendOne("+96598765432", "Normalization test", null);
    try std.testing.expect(resp.result.len > 0);
}

test "integration: send handles 00 prefix normalization" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const resp = try client.sendOne("0096598765432", "Normalization test", null);
    try std.testing.expect(resp.result.len > 0);
}

test "integration: senderids returns a response" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const resp = try client.senderids();
    try std.testing.expect(resp.result.len > 0);
}

test "integration: coverage returns a response" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const resp = try client.coverage();
    try std.testing.expect(resp.result.len > 0);
}

test "integration: emoji-only message returns error" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const resp = try client.sendOne("96598765432", "\xF0\x9F\x98\x80\xF0\x9F\x98\x82", null);
    try std.testing.expect(resp.isError());
    try std.testing.expectEqualStrings("ERR009", resp.code.?);
}

test "integration: send handles Arabic-Indic digit phone number" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    // ٩٦٥٩٨٧٦٥٤٣٢ = 96598765432
    const resp = try client.sendOne("\xD9\xA9\xD9\xA6\xD9\xA5\xD9\xA9\xD9\xA8\xD9\xA7\xD9\xA6\xD9\xA5\xD9\xA4\xD9\xA3\xD9\xA2", "Arabic numeral test", null);
    try std.testing.expect(resp.result.len > 0);
}

test "integration: send handles Extended Arabic-Indic (Persian) digit phone number" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    // ۹۶۵۱۲۳۴۵۶۷۸ = 96512345678
    const resp = try client.sendOne("\xDB\xB9\xDB\xB6\xDB\xB5\xDB\xB1\xDB\xB2\xDB\xB3\xDB\xB4\xDB\xB5\xDB\xB6\xDB\xB7\xDB\xB8", "Persian numeral test", null);
    try std.testing.expect(resp.result.len > 0);
}

test "integration: send handles mixed Arabic-Indic and Latin digits" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    // ٩٦٥98765٤٣٢ = 96598765432 (mixed Arabic-Indic and Latin)
    const resp = try client.sendOne("\xD9\xA9\xD9\xA6\xD9\xA598765\xD9\xA4\xD9\xA3\xD9\xA2", "Mixed numeral test", null);
    try std.testing.expect(resp.result.len > 0);
}

test "integration: duplicate numbers deduplicated" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");
    const mobiles = [_][]const u8{ "+96598765432", "0096598765432", "96598765432" };
    const resp = try client.send(&mobiles, "Dedup test", null);
    // All three normalize to the same number, should send only once
    try std.testing.expect(resp.result.len > 0);
    if (resp.numbers) |n| {
        try std.testing.expectEqual(@as(i64, 1), n);
    }
}

// --- Bulk Send Tests (library) ---

test "integration: sendBulk 250 numbers splits into 2 batches with msg-ids" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");

    // Record balance before bulk send
    const bal_before = try client.balance();
    try std.testing.expect(bal_before != null);

    // Generate 250 numbers: 96599220000 - 96599220249
    var number_bufs: [250][12]u8 = undefined;
    var mobiles: [250][]const u8 = undefined;
    var i: usize = 0;
    while (i < 250) : (i += 1) {
        const num: u64 = 96599220000 + @as(u64, i);
        mobiles[i] = std.fmt.bufPrint(&number_bufs[i], "{d}", .{num}) catch unreachable;
    }

    // One call to sendBulk → internally splits into batch 1 (200) + batch 2 (50) with delay
    const result = try client.sendBulk(&mobiles, "Bulk test from kwtsms-zig", null);

    // Verify batching structure
    try std.testing.expectEqualStrings("OK", result.result);
    try std.testing.expect(result.bulk); // was split into multiple batches
    try std.testing.expectEqual(@as(usize, 2), result.batches); // 200 + 50
    try std.testing.expectEqual(@as(usize, 250), result.numbers);

    // Two separate msg-ids (one per batch)
    try std.testing.expectEqual(@as(usize, 2), result.msg_ids.len);
    try std.testing.expect(result.msg_ids[0].len > 0);
    try std.testing.expect(result.msg_ids[1].len > 0);
    // Each batch gets a distinct msg-id
    try std.testing.expect(!std.mem.eql(u8, result.msg_ids[0], result.msg_ids[1]));

    // Balance after is recorded (test mode: credits tentatively held)
    try std.testing.expect(result.balance_after > 0);

    // No batch errors
    try std.testing.expectEqual(@as(usize, 0), result.batch_errors.len);

    // Points charged should be 250 (1 point per number in test mode)
    try std.testing.expectEqual(@as(i64, 250), result.points_charged);

    // Check status of each msg-id
    // Immediately after send: OK/queued. Later: ERR030 (stuck in queue, test mode).
    for (result.msg_ids) |msg_id| {
        const status_resp = try client.status(msg_id);
        try std.testing.expect(status_resp.result.len > 0);
        if (status_resp.isOk()) {
            // Just sent: message accepted and in delivery queue
            try std.testing.expect(status_resp.raw_body != null);
        } else {
            // Checked later: ERR030 = message stuck in queue (normal for test mode)
            try std.testing.expectEqualStrings("ERR030", status_resp.code.?);
        }
    }

    // Balance should reflect tentative deduction (credits held, recoverable from queue)
    const bal_after = result.balance_after;
    try std.testing.expect(bal_after <= bal_before.?);
}

// --- Bulk Send Tests (CLI-style: uses send() as the CLI does) ---

test "integration: send() auto-batches 250 numbers (CLI-style)" {
    const creds = getTestCredentials() orelse return;
    const allocator = std.heap.page_allocator;
    var client = kwtsms.KwtSMS.init(allocator, creds.username, creds.password, null, true, "");

    // Record balance before
    const bal_before = try client.balance();
    try std.testing.expect(bal_before != null);

    // Generate 250 numbers: 96599220250 - 96599220499 (different range to avoid ERR028)
    var number_bufs: [250][12]u8 = undefined;
    var mobiles: [250][]const u8 = undefined;
    var i: usize = 0;
    while (i < 250) : (i += 1) {
        const num: u64 = 96599220250 + @as(u64, i);
        mobiles[i] = std.fmt.bufPrint(&number_bufs[i], "{d}", .{num}) catch unreachable;
    }

    // send() is what the CLI calls — should auto-batch for >200 numbers
    const resp = try client.send(&mobiles, "CLI bulk test from kwtsms-zig", null);

    // Aggregated response should be OK
    try std.testing.expect(resp.isOk());
    try std.testing.expect(resp.numbers != null);
    try std.testing.expectEqual(@as(i64, 250), resp.numbers.?);

    // Points charged aggregated across both batches
    try std.testing.expect(resp.points_charged != null);
    try std.testing.expectEqual(@as(i64, 250), resp.points_charged.?);

    // Balance after from the last batch
    try std.testing.expect(resp.balance_after != null);
    try std.testing.expect(resp.balance_after.? <= bal_before.?);

    // msg_id is from the last batch (aggregated send returns last batch's msg_id)
    try std.testing.expect(resp.msg_id != null);
    try std.testing.expect(resp.msg_id.?.len > 0);

    // Verify the msg-id via status
    // Immediately: OK/queued. Later: ERR030 (stuck in queue, test mode).
    const status_resp = try client.status(resp.msg_id.?);
    try std.testing.expect(status_resp.result.len > 0);
    if (status_resp.isError()) {
        try std.testing.expectEqualStrings("ERR030", status_resp.code.?);
    }
}
