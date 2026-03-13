const std = @import("std");
const errors = @import("errors.zig");
const logger = @import("logger.zig");

const BASE_URL = "https://www.kwtsms.com/API/";

/// Make a POST request to the kwtSMS API.
/// Returns the parsed ApiResponse. Never panics.
pub fn apiRequest(
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    json_body: []const u8,
    log_file: ?[]const u8,
) !errors.ApiResponse {
    // Build full URL
    var url_buf: [256]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buf, "{s}{s}/", .{ BASE_URL, endpoint }) catch {
        return errors.networkError("URL too long");
    };

    // Parse URI
    const uri = std.Uri.parse(url) catch {
        return errors.networkError("Invalid URL");
    };

    // Create HTTP client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Open request
    var header_buf: [4096]u8 = undefined;
    var req = client.open(.POST, uri, .{
        .server_header_buffer = &header_buf,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "Accept", .value = "application/json" },
        },
    }) catch {
        const err_msg = "Network error: could not connect to API";
        logger.writeLog(log_file, endpoint, json_body, "", false, err_msg);
        return errors.networkError(err_msg);
    };
    defer req.deinit();

    // Send body
    req.transfer_encoding = .{ .content_length = json_body.len };
    req.send() catch {
        logger.writeLog(log_file, endpoint, json_body, "", false, "Failed to send request");
        return errors.networkError("Failed to send request");
    };
    req.writer().writeAll(json_body) catch {
        logger.writeLog(log_file, endpoint, json_body, "", false, "Failed to write request body");
        return errors.networkError("Failed to write request body");
    };
    req.finish() catch {
        logger.writeLog(log_file, endpoint, json_body, "", false, "Failed to finish request");
        return errors.networkError("Failed to finish request");
    };

    // Wait for response
    req.wait() catch {
        logger.writeLog(log_file, endpoint, json_body, "", false, "Request timed out or failed");
        return errors.networkError("Request timed out or failed");
    };

    // Read response body (owned by the returned ApiResponse via raw_body)
    const body = req.reader().readAllAlloc(allocator, 1024 * 1024) catch {
        logger.writeLog(log_file, endpoint, json_body, "", false, "Failed to read response body");
        return errors.networkError("Failed to read response body");
    };

    // Note: body is NOT freed here. It is stored in ApiResponse.raw_body and all
    // parsed string fields (result, code, description, msg_id) point into it.
    return parseResponse(body, log_file, endpoint, json_body);
}

/// Parse a JSON response body into an ApiResponse.
pub fn parseResponse(
    body: []const u8,
    log_file: ?[]const u8,
    endpoint: []const u8,
    request_body: []const u8,
) errors.ApiResponse {
    // Validate JSON structure before manual parsing.
    // H4 fix: call deinit() to free the parsed tree instead of discarding it.
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, body, .{}) catch {
        logger.writeLog(log_file, endpoint, request_body, body, false, "Invalid JSON response");
        return errors.networkError("Invalid JSON response from API");
    };
    parsed.deinit();

    var resp = errors.ApiResponse{
        .result = "ERROR",
        .raw_body = body,
    };

    // Extract "result" field
    if (jsonGetString(body, "result")) |result_val| {
        resp.result = result_val;
    }

    // Extract common fields
    resp.code = jsonGetString(body, "code");
    resp.description = jsonGetString(body, "description");
    resp.msg_id = jsonGetString(body, "msg-id");

    // Extract numeric fields
    resp.numbers = jsonGetInt(body, "numbers");
    resp.points_charged = jsonGetInt(body, "points-charged");
    resp.balance_after = jsonGetFloat(body, "balance-after");
    resp.unix_timestamp = jsonGetInt(body, "unix-timestamp");
    resp.available = jsonGetFloat(body, "available");
    resp.purchased = jsonGetFloat(body, "purchased");

    // Enrich errors with action
    errors.enrichError(&resp);

    const ok = resp.isOk();
    logger.writeLog(log_file, endpoint, request_body, body, ok, if (!ok) resp.description else null);

    return resp;
}

// Simple JSON field extraction helpers (avoid full parsing overhead for known fields)

fn jsonGetString(json: []const u8, key: []const u8) ?[]const u8 {
    // Search for "key":"value" or "key": "value" (handles optional whitespace)
    var search_buf: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&search_buf, "\"{s}\":", .{key}) catch return null;

    const idx = std.mem.indexOf(u8, json, needle) orelse return null;
    var start = idx + needle.len;

    // Skip whitespace after colon
    while (start < json.len and (json[start] == ' ' or json[start] == '\t')) : (start += 1) {}

    // Expect opening quote
    if (start >= json.len or json[start] != '"') return null;
    start += 1;

    const value_end = std.mem.indexOfPos(u8, json, start, "\"") orelse return null;
    return json[start..value_end];
}

fn jsonGetInt(json: []const u8, key: []const u8) ?i64 {
    var search_buf: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&search_buf, "\"{s}\":", .{key}) catch return null;

    const idx = std.mem.indexOf(u8, json, needle) orelse return null;
    var start = idx + needle.len;

    // Skip whitespace
    while (start < json.len and (json[start] == ' ' or json[start] == '\t')) : (start += 1) {}
    if (start >= json.len or json[start] == '"') return null; // It's a string, not a number

    // Find end of number
    var end = start;
    while (end < json.len and (json[end] >= '0' and json[end] <= '9' or json[end] == '-')) : (end += 1) {}

    return std.fmt.parseInt(i64, json[start..end], 10) catch null;
}

fn jsonGetFloat(json: []const u8, key: []const u8) ?f64 {
    var search_buf: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&search_buf, "\"{s}\":", .{key}) catch return null;

    const idx = std.mem.indexOf(u8, json, needle) orelse return null;
    var start = idx + needle.len;

    // Skip whitespace
    while (start < json.len and (json[start] == ' ' or json[start] == '\t')) : (start += 1) {}
    if (start >= json.len or json[start] == '"') return null;

    // Find end of number
    var end = start;
    while (end < json.len and (json[end] >= '0' and json[end] <= '9' or json[end] == '-' or json[end] == '.')) : (end += 1) {}

    return std.fmt.parseFloat(f64, json[start..end]) catch null;
}

/// Write s as a JSON string value (no surrounding quotes). Escapes special chars.
/// H3 fix: prevents JSON injection via user-controlled credential/message fields.
fn writeJsonEscaped(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            // Other control chars not already matched above
            0x00...0x08, 0x0B...0x0C, 0x0E...0x1F => try writer.print("\\u{X:0>4}", .{@as(u32, c)}),
            else => try writer.writeByte(c),
        }
    }
}

/// Build a JSON request body for sending to the API.
/// H3 fix: all user-supplied strings are JSON-escaped to prevent injection.
pub fn buildSendBody(
    buf: []u8,
    username: []const u8,
    password: []const u8,
    sender: []const u8,
    mobile: []const u8,
    message: []const u8,
    test_mode: bool,
) ?[]const u8 {
    var fbs = std.io.fixedBufferStream(buf);
    const w = fbs.writer();
    w.writeAll("{\"username\":\"") catch return null;
    writeJsonEscaped(w, username) catch return null;
    w.writeAll("\",\"password\":\"") catch return null;
    writeJsonEscaped(w, password) catch return null;
    w.writeAll("\",\"sender\":\"") catch return null;
    writeJsonEscaped(w, sender) catch return null;
    w.writeAll("\",\"mobile\":\"") catch return null;
    writeJsonEscaped(w, mobile) catch return null;
    w.writeAll("\",\"message\":\"") catch return null;
    writeJsonEscaped(w, message) catch return null;
    w.writeAll("\",\"test\":\"") catch return null;
    w.writeAll(if (test_mode) "1" else "0") catch return null;
    w.writeAll("\"}") catch return null;
    return fbs.getWritten();
}

/// Build a JSON request body for auth-only endpoints (balance, senderid, coverage).
/// H3 fix: credentials are JSON-escaped.
pub fn buildAuthBody(
    buf: []u8,
    username: []const u8,
    password: []const u8,
) ?[]const u8 {
    var fbs = std.io.fixedBufferStream(buf);
    const w = fbs.writer();
    w.writeAll("{\"username\":\"") catch return null;
    writeJsonEscaped(w, username) catch return null;
    w.writeAll("\",\"password\":\"") catch return null;
    writeJsonEscaped(w, password) catch return null;
    w.writeAll("\"}") catch return null;
    return fbs.getWritten();
}

/// Build a JSON request body for validate endpoint.
/// H3 fix: credentials are JSON-escaped.
pub fn buildValidateBody(
    buf: []u8,
    username: []const u8,
    password: []const u8,
    mobile: []const u8,
) ?[]const u8 {
    var fbs = std.io.fixedBufferStream(buf);
    const w = fbs.writer();
    w.writeAll("{\"username\":\"") catch return null;
    writeJsonEscaped(w, username) catch return null;
    w.writeAll("\",\"password\":\"") catch return null;
    writeJsonEscaped(w, password) catch return null;
    w.writeAll("\",\"mobile\":\"") catch return null;
    writeJsonEscaped(w, mobile) catch return null;
    w.writeAll("\"}") catch return null;
    return fbs.getWritten();
}

/// Build a JSON request body for status/dlr endpoint.
/// H3 fix: credentials are JSON-escaped.
pub fn buildMsgIdBody(
    buf: []u8,
    username: []const u8,
    password: []const u8,
    msg_id: []const u8,
) ?[]const u8 {
    var fbs = std.io.fixedBufferStream(buf);
    const w = fbs.writer();
    w.writeAll("{\"username\":\"") catch return null;
    writeJsonEscaped(w, username) catch return null;
    w.writeAll("\",\"password\":\"") catch return null;
    writeJsonEscaped(w, password) catch return null;
    w.writeAll("\",\"msgid\":\"") catch return null;
    writeJsonEscaped(w, msg_id) catch return null;
    w.writeAll("\"}") catch return null;
    return fbs.getWritten();
}

// -- Tests --
test "jsonGetString: extracts string value" {
    const json = "{\"result\":\"OK\",\"msg-id\":\"abc123\"}";
    try std.testing.expectEqualStrings("OK", jsonGetString(json, "result").?);
    try std.testing.expectEqualStrings("abc123", jsonGetString(json, "msg-id").?);
}

test "jsonGetString: returns null for missing key" {
    const json = "{\"result\":\"OK\"}";
    try std.testing.expect(jsonGetString(json, "missing") == null);
}

test "jsonGetInt: extracts integer value" {
    const json = "{\"numbers\":5,\"points-charged\":3}";
    try std.testing.expectEqual(@as(i64, 5), jsonGetInt(json, "numbers").?);
    try std.testing.expectEqual(@as(i64, 3), jsonGetInt(json, "points-charged").?);
}

test "jsonGetFloat: extracts float value" {
    const json = "{\"balance-after\":150.5,\"available\":200.0}";
    try std.testing.expectApproxEqAbs(@as(f64, 150.5), jsonGetFloat(json, "balance-after").?, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 200.0), jsonGetFloat(json, "available").?, 0.01);
}

test "buildAuthBody: creates valid JSON" {
    var buf: [512]u8 = undefined;
    const body = buildAuthBody(&buf, "user", "pass").?;
    try std.testing.expect(std.mem.indexOf(u8, body, "\"username\":\"user\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"password\":\"pass\"") != null);
}

test "buildAuthBody: JSON-escapes quotes in credentials" {
    var buf: [512]u8 = undefined;
    // A credential containing a double quote must be escaped, not break JSON structure
    const body = buildAuthBody(&buf, "user\"name", "pa\\ss").?;
    try std.testing.expect(std.mem.indexOf(u8, body, "\\\"") != null); // escaped quote present
    try std.testing.expect(std.mem.indexOf(u8, body, "user\"name") == null); // raw quote absent
    try std.testing.expect(std.mem.indexOf(u8, body, "\\\\") != null); // escaped backslash present
}

test "buildSendBody: creates valid JSON" {
    var buf: [4096]u8 = undefined;
    const body = buildSendBody(&buf, "user", "pass", "KWT-SMS", "96598765432", "Hello", false).?;
    try std.testing.expect(std.mem.indexOf(u8, body, "\"test\":\"0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"mobile\":\"96598765432\"") != null);
}

test "buildSendBody: test mode sets test=1" {
    var buf: [4096]u8 = undefined;
    const body = buildSendBody(&buf, "user", "pass", "KWT-SMS", "96598765432", "Hello", true).?;
    try std.testing.expect(std.mem.indexOf(u8, body, "\"test\":\"1\"") != null);
}

test "buildSendBody: JSON-escapes message content" {
    var buf: [4096]u8 = undefined;
    // A message with a double quote must be escaped
    const body = buildSendBody(&buf, "u", "p", "S", "96598765432", "Hello \"World\"", false).?;
    try std.testing.expect(std.mem.indexOf(u8, body, "Hello \\\"World\\\"") != null);
    // Raw unescaped quotes must not appear inside the message value
    try std.testing.expect(std.mem.indexOf(u8, body, "Hello \"World\"") == null);
}

test "buildSendBody: returns null when buffer too small" {
    var buf: [10]u8 = undefined;
    const body = buildSendBody(&buf, "user", "pass", "KWT-SMS", "96598765432", "Hello", false);
    try std.testing.expect(body == null);
}

test "parseResponse: parses OK send response" {
    const body = "{\"result\":\"OK\",\"msg-id\":\"abc123\",\"numbers\":1,\"points-charged\":1,\"balance-after\":150,\"unix-timestamp\":1684763355}";
    const resp = parseResponse(body, null, "send", "{}");
    try std.testing.expect(resp.isOk());
    try std.testing.expectEqualStrings("abc123", resp.msg_id.?);
    try std.testing.expectEqual(@as(i64, 1), resp.numbers.?);
}

test "parseResponse: parses ERROR response with enrichment" {
    const body = "{\"result\":\"ERROR\",\"code\":\"ERR003\",\"description\":\"Authentication error\"}";
    const resp = parseResponse(body, null, "send", "{}");
    try std.testing.expect(resp.isError());
    try std.testing.expect(resp.action != null);
}

test "parseResponse: unknown error code has no action" {
    const body = "{\"result\":\"ERROR\",\"code\":\"ERR999\",\"description\":\"Unknown\"}";
    const resp = parseResponse(body, null, "send", "{}");
    try std.testing.expect(resp.isError());
    try std.testing.expect(resp.action == null);
}

test "writeJsonEscaped: escapes double quote" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try writeJsonEscaped(fbs.writer(), "say \"hi\"");
    try std.testing.expectEqualStrings("say \\\"hi\\\"", fbs.getWritten());
}

test "writeJsonEscaped: escapes backslash" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try writeJsonEscaped(fbs.writer(), "C:\\path");
    try std.testing.expectEqualStrings("C:\\\\path", fbs.getWritten());
}

test "writeJsonEscaped: escapes newline" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try writeJsonEscaped(fbs.writer(), "line1\nline2");
    try std.testing.expectEqualStrings("line1\\nline2", fbs.getWritten());
}

test "writeJsonEscaped: passes through safe characters" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try writeJsonEscaped(fbs.writer(), "hello world 123");
    try std.testing.expectEqualStrings("hello world 123", fbs.getWritten());
}
