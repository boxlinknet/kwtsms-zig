const std = @import("std");

/// Write a JSONL log entry. Never crashes the main flow.
/// Fields: ts (UTC ISO-8601), endpoint, request (password masked), response, ok, error.
pub fn writeLog(
    log_file: ?[]const u8,
    endpoint: []const u8,
    request_body: []const u8,
    response_body: []const u8,
    ok: bool,
    err_msg: ?[]const u8,
) void {
    const path = log_file orelse return;
    if (path.len == 0) return;

    writeLogInner(path, endpoint, request_body, response_body, ok, err_msg) catch {
        // Logging must never crash the main flow
    };
}

fn writeLogInner(
    path: []const u8,
    endpoint: []const u8,
    request_body: []const u8,
    response_body: []const u8,
    ok: bool,
    err_msg: ?[]const u8,
) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = false });
    defer file.close();
    try file.seekFromEnd(0);

    var buf: [64]u8 = undefined;
    const ts = getUtcTimestamp(&buf);

    // H2 fix: 8192-byte buffer covers the largest realistic request body
    // (200x 15-digit numbers + 918-char message + 64-char creds = ~4316 bytes).
    // A 4096-byte buffer could overflow and expose the password in plaintext.
    var masked_buf: [8192]u8 = undefined;
    const masked_request = maskPassword(request_body, &masked_buf);

    var writer = file.writer();
    try writer.print("{{\"ts\":\"{s}\",\"endpoint\":\"{s}\",\"request\":{s},\"response\":{s},\"ok\":{},\"error\":", .{
        ts,
        endpoint,
        masked_request,
        if (response_body.len > 0) response_body else "null",
        ok,
    });

    // M1 fix: properly JSON-quote the error string so the output is valid JSONL.
    // Previously written as bare text, breaking any downstream JSONL parser.
    if (err_msg) |e| {
        try writer.writeByte('"');
        try writeJsonEscaped(writer, e);
        try writer.writeByte('"');
    } else {
        try writer.writeAll("null");
    }

    try writer.writeAll("}\n");
}

/// Write s as a JSON string value (no surrounding quotes). Escapes special chars.
fn writeJsonEscaped(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x00...0x08, 0x0B...0x0C, 0x0E...0x1F => try writer.print("\\u{X:0>4}", .{@as(u32, c)}),
            else => try writer.writeByte(c),
        }
    }
}

fn getUtcTimestamp(buf: []u8) []const u8 {
    const epoch = std.time.timestamp();
    const es = std.time.epoch.EpochSeconds{ .secs = @intCast(epoch) };
    const day = es.getEpochDay();
    const yd = day.calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();

    const result = std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        yd.year,
        @as(u32, @intFromEnum(md.month)) + 1,
        @as(u32, md.day_index) + 1,
        ds.getHoursIntoDay(),
        ds.getMinutesIntoHour(),
        ds.getSecondsIntoMinute(),
    }) catch return "1970-01-01T00:00:00Z";

    return result;
}

fn maskPassword(input: []const u8, buf: []u8) []const u8 {
    // Simple approach: replace password value with ***
    const needle = "\"password\":\"";
    const idx = std.mem.indexOf(u8, input, needle) orelse return input;

    const value_start = idx + needle.len;
    const value_end = std.mem.indexOfPos(u8, input, value_start, "\"") orelse return input;

    const before = input[0..value_start];
    const after = input[value_end..];
    const masked = "***";

    if (before.len + masked.len + after.len > buf.len) return input;

    @memcpy(buf[0..before.len], before);
    @memcpy(buf[before.len .. before.len + masked.len], masked);
    @memcpy(buf[before.len + masked.len .. before.len + masked.len + after.len], after);

    return buf[0 .. before.len + masked.len + after.len];
}

// -- Tests --
test "maskPassword: masks password in JSON" {
    var buf: [8192]u8 = undefined;
    const input = "{\"username\":\"user\",\"password\":\"secret123\"}";
    const result = maskPassword(input, &buf);
    try std.testing.expect(std.mem.indexOf(u8, result, "secret123") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "***") != null);
}

test "maskPassword: no password field returns original" {
    var buf: [8192]u8 = undefined;
    const input = "{\"username\":\"user\"}";
    const result = maskPassword(input, &buf);
    try std.testing.expectEqualStrings(input, result);
}

test "maskPassword: large body is masked not passed through" {
    // H2 fix verification: a body near the old 4096-byte limit must still be masked.
    // Construct a body that would overflow the old 4096-byte buffer but fits in 8192.
    var body_buf: [5000]u8 = undefined;
    // Fill with a long mobile list prefix, then add credentials
    const prefix = "{\"username\":\"user\",\"password\":\"supersecretpassword\",\"mobile\":\"";
    @memcpy(body_buf[0..prefix.len], prefix);
    // Pad with digits to push past 4096 bytes
    var i: usize = prefix.len;
    while (i < 4200) : (i += 1) {
        body_buf[i] = '9';
    }
    body_buf[i] = '"';
    body_buf[i + 1] = '}';
    const input = body_buf[0 .. i + 2];

    var mask_buf: [8192]u8 = undefined;
    const result = maskPassword(input, &mask_buf);
    // Must be masked (not the original)
    try std.testing.expect(std.mem.indexOf(u8, result, "supersecretpassword") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "***") != null);
}

test "getUtcTimestamp: returns valid format" {
    var buf: [64]u8 = undefined;
    const ts = getUtcTimestamp(&buf);
    try std.testing.expect(ts.len > 0);
    try std.testing.expect(ts[ts.len - 1] == 'Z');
    try std.testing.expect(ts[4] == '-');
}

test "writeLog: does not crash with null path" {
    writeLog(null, "send", "{}", "{}", true, null);
}

test "writeLog: does not crash with empty path" {
    writeLog("", "send", "{}", "{}", true, null);
}

test "writeLog: error field is valid JSON (quoted string)" {
    // M1 fix verification: error messages must be JSON-quoted, not bare text.
    const tmp_path = "/tmp/kwtsms_test_logger_jsonl";
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    writeLog(tmp_path, "send", "{}", "{}", false, "Authentication error, check credentials");

    // Read the log and verify it contains a properly quoted error field
    const allocator = std.testing.allocator;
    const content = try std.fs.cwd().readFileAlloc(allocator, tmp_path, 4096);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "\"error\":\"Authentication error") != null);
    // Must NOT be bare text (old bug: "error":Authentication error...)
    try std.testing.expect(std.mem.indexOf(u8, content, "\"error\":Authentication") == null);
}

test "writeLog: error field with special chars is properly escaped" {
    // M1 fix: error messages containing quotes must be escaped
    const tmp_path = "/tmp/kwtsms_test_logger_escape";
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    writeLog(tmp_path, "send", "{}", "{}", false, "Error: \"invalid\" response");

    const allocator = std.testing.allocator;
    const content = try std.fs.cwd().readFileAlloc(allocator, tmp_path, 4096);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "\\\"invalid\\\"") != null);
}

test "writeLog: null error field writes null" {
    const tmp_path = "/tmp/kwtsms_test_logger_null_err";
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    writeLog(tmp_path, "balance", "{}", "{}", true, null);

    const allocator = std.testing.allocator;
    const content = try std.fs.cwd().readFileAlloc(allocator, tmp_path, 4096);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "\"error\":null") != null);
}
