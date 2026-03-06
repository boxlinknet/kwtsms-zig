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

    // Mask password in request body
    var masked_buf: [4096]u8 = undefined;
    const masked_request = maskPassword(request_body, &masked_buf);

    var writer = file.writer();
    try writer.print("{{\"ts\":\"{s}\",\"endpoint\":\"{s}\",\"request\":{s},\"response\":{s},\"ok\":{},\"error\":{s}}}\n", .{
        ts,
        endpoint,
        masked_request,
        if (response_body.len > 0) response_body else "null",
        ok,
        if (err_msg) |e| e else "null",
    });
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
    var buf: [4096]u8 = undefined;
    const input = "{\"username\":\"user\",\"password\":\"secret123\"}";
    const result = maskPassword(input, &buf);
    try std.testing.expect(std.mem.indexOf(u8, result, "secret123") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "***") != null);
}

test "maskPassword: no password field returns original" {
    var buf: [4096]u8 = undefined;
    const input = "{\"username\":\"user\"}";
    const result = maskPassword(input, &buf);
    try std.testing.expectEqualStrings(input, result);
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
