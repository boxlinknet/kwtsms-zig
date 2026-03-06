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

    // Read response body
    const body = req.reader().readAllAlloc(allocator, 1024 * 1024) catch {
        logger.writeLog(log_file, endpoint, json_body, "", false, "Failed to read response body");
        return errors.networkError("Failed to read response body");
    };
    defer allocator.free(body);

    // Parse JSON response
    return parseResponse(body, log_file, endpoint, json_body);
}

/// Parse a JSON response body into an ApiResponse.
pub fn parseResponse(
    body: []const u8,
    log_file: ?[]const u8,
    endpoint: []const u8,
    request_body: []const u8,
) errors.ApiResponse {
    const parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, body, .{}) catch {
        logger.writeLog(log_file, endpoint, request_body, body, false, "Invalid JSON response");
        return errors.networkError("Invalid JSON response from API");
    };
    _ = parsed; // We use the raw body approach below for simplicity

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
    // Search for "key":"value" pattern
    var search_buf: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&search_buf, "\"{s}\":\"", .{key}) catch return null;

    const idx = std.mem.indexOf(u8, json, needle) orelse return null;
    const value_start = idx + needle.len;
    const value_end = std.mem.indexOfPos(u8, json, value_start, "\"") orelse return null;

    return json[value_start..value_end];
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

/// Build a JSON request body for sending to the API.
pub fn buildSendBody(
    buf: []u8,
    username: []const u8,
    password: []const u8,
    sender: []const u8,
    mobile: []const u8,
    message: []const u8,
    test_mode: bool,
) ?[]const u8 {
    const result = std.fmt.bufPrint(buf, "{{\"username\":\"{s}\",\"password\":\"{s}\",\"sender\":\"{s}\",\"mobile\":\"{s}\",\"message\":\"{s}\",\"test\":\"{s}\"}}", .{
        username,
        password,
        sender,
        mobile,
        message,
        if (test_mode) "1" else "0",
    }) catch return null;
    return result;
}

/// Build a JSON request body for auth-only endpoints (balance, senderid, coverage).
pub fn buildAuthBody(
    buf: []u8,
    username: []const u8,
    password: []const u8,
) ?[]const u8 {
    const result = std.fmt.bufPrint(buf, "{{\"username\":\"{s}\",\"password\":\"{s}\"}}", .{
        username,
        password,
    }) catch return null;
    return result;
}

/// Build a JSON request body for validate endpoint.
pub fn buildValidateBody(
    buf: []u8,
    username: []const u8,
    password: []const u8,
    mobile: []const u8,
) ?[]const u8 {
    const result = std.fmt.bufPrint(buf, "{{\"username\":\"{s}\",\"password\":\"{s}\",\"mobile\":\"{s}\"}}", .{
        username,
        password,
        mobile,
    }) catch return null;
    return result;
}

/// Build a JSON request body for status/dlr endpoint.
pub fn buildMsgIdBody(
    buf: []u8,
    username: []const u8,
    password: []const u8,
    msg_id: []const u8,
) ?[]const u8 {
    const result = std.fmt.bufPrint(buf, "{{\"username\":\"{s}\",\"password\":\"{s}\",\"msgid\":\"{s}\"}}", .{
        username,
        password,
        msg_id,
    }) catch return null;
    return result;
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
