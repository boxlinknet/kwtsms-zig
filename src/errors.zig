const std = @import("std");

/// 28 documented kwtSMS API error codes mapped to developer-friendly action messages.
/// ERR014-ERR018 are gaps in the official API documentation and are intentionally omitted.
pub const ApiErrorEntry = struct {
    code: []const u8,
    action: []const u8,
};

pub const api_errors = [_]ApiErrorEntry{
    .{ .code = "ERR001", .action = "API is disabled on this account. Enable it at kwtsms.com -> Account -> API." },
    .{ .code = "ERR002", .action = "A required parameter is missing. Check that username, password, sender, mobile, and message are all provided." },
    .{ .code = "ERR003", .action = "Wrong API username or password. Check KWTSMS_USERNAME and KWTSMS_PASSWORD. These are your API credentials, not your account mobile number." },
    .{ .code = "ERR004", .action = "This account does not have API access. Contact kwtSMS support to enable it." },
    .{ .code = "ERR005", .action = "This account is blocked. Contact kwtSMS support." },
    .{ .code = "ERR006", .action = "No valid phone numbers. Make sure each number includes the country code (e.g., 96598765432 for Kuwait, not 98765432)." },
    .{ .code = "ERR007", .action = "Too many numbers in a single request (maximum 200). Split into smaller batches." },
    .{ .code = "ERR008", .action = "This sender ID is banned. Use a different sender ID registered on your kwtSMS account." },
    .{ .code = "ERR009", .action = "Message is empty. Provide a non-empty message text." },
    .{ .code = "ERR010", .action = "Account balance is zero. Recharge credits at kwtsms.com." },
    .{ .code = "ERR011", .action = "Insufficient balance for this send. Buy more credits at kwtsms.com." },
    .{ .code = "ERR012", .action = "Message is too long (over 6 SMS pages). Shorten your message." },
    .{ .code = "ERR013", .action = "Send queue is full (1000 messages). Wait a moment and try again." },
    .{ .code = "ERR019", .action = "No delivery reports found for this message." },
    .{ .code = "ERR020", .action = "Message ID does not exist. Make sure you saved the msg-id from the send response." },
    .{ .code = "ERR021", .action = "No delivery report available for this message yet." },
    .{ .code = "ERR022", .action = "Delivery reports are not ready yet. Try again after 24 hours." },
    .{ .code = "ERR023", .action = "Unknown delivery report error. Contact kwtSMS support." },
    .{ .code = "ERR024", .action = "Your IP address is not in the API whitelist. Add it at kwtsms.com -> Account -> API -> IP Lockdown, or disable IP lockdown." },
    .{ .code = "ERR025", .action = "Invalid phone number. Make sure the number includes the country code (e.g., 96598765432 for Kuwait, not 98765432)." },
    .{ .code = "ERR026", .action = "This country is not activated on your account. Contact kwtSMS support to enable the destination country." },
    .{ .code = "ERR027", .action = "HTML tags are not allowed in the message. Remove any HTML content and try again." },
    .{ .code = "ERR028", .action = "You must wait at least 15 seconds before sending to the same number again. No credits were consumed." },
    .{ .code = "ERR029", .action = "Message ID does not exist or is incorrect." },
    .{ .code = "ERR030", .action = "Message is stuck in the send queue with an error. Delete it at kwtsms.com -> Queue to recover credits." },
    .{ .code = "ERR031", .action = "Message rejected: bad language detected." },
    .{ .code = "ERR032", .action = "Message rejected: spam detected." },
    .{ .code = "ERR033", .action = "No active coverage found. Contact kwtSMS support." },
};

/// Look up the action message for a given error code.
/// Returns null if the code is not in the known error table.
pub fn getAction(code: []const u8) ?[]const u8 {
    for (api_errors) |entry| {
        if (std.mem.eql(u8, entry.code, code)) {
            return entry.action;
        }
    }
    return null;
}

/// Result type for all API responses.
pub const ApiResponse = struct {
    result: []const u8,
    code: ?[]const u8 = null,
    description: ?[]const u8 = null,
    action: ?[]const u8 = null,
    // Send fields
    msg_id: ?[]const u8 = null,
    numbers: ?i64 = null,
    points_charged: ?i64 = null,
    balance_after: ?f64 = null,
    unix_timestamp: ?i64 = null,
    // Balance fields
    available: ?f64 = null,
    purchased: ?f64 = null,
    // Validate fields (stored as raw JSON strings for flexibility)
    raw_body: ?[]const u8 = null,

    pub fn isOk(self: ApiResponse) bool {
        return std.mem.eql(u8, self.result, "OK");
    }

    pub fn isError(self: ApiResponse) bool {
        return std.mem.eql(u8, self.result, "ERROR");
    }
};

/// Enrich an error response with an action field.
pub fn enrichError(response: *ApiResponse) void {
    if (response.code) |code| {
        if (getAction(code)) |action| {
            response.action = action;
        }
    }
}

/// Create a local error response (for pre-validation failures).
pub fn makeError(code: []const u8, description: []const u8) ApiResponse {
    var resp = ApiResponse{
        .result = "ERROR",
        .code = code,
        .description = description,
    };
    enrichError(&resp);
    return resp;
}

/// Create a network error response.
pub fn networkError(description: []const u8) ApiResponse {
    return ApiResponse{
        .result = "ERROR",
        .code = "NETWORK",
        .description = description,
        .action = "Check your network connection and try again.",
    };
}

// -- Tests --
test "getAction returns action for known codes" {
    const action = getAction("ERR003");
    try std.testing.expect(action != null);
    try std.testing.expect(std.mem.indexOf(u8, action.?, "Wrong API username") != null);
}

test "getAction returns null for unknown codes" {
    const action = getAction("ERR999");
    try std.testing.expect(action == null);
}

test "enrichError adds action to response" {
    var resp = ApiResponse{
        .result = "ERROR",
        .code = "ERR010",
        .description = "Balance is zero",
    };
    enrichError(&resp);
    try std.testing.expect(resp.action != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.action.?, "kwtsms.com") != null);
}

test "enrichError does not crash on unknown code" {
    var resp = ApiResponse{
        .result = "ERROR",
        .code = "ERR999",
        .description = "Unknown error",
    };
    enrichError(&resp);
    try std.testing.expect(resp.action == null);
}

test "makeError creates error with action" {
    const resp = makeError("ERR009", "Message is empty");
    try std.testing.expect(resp.isError());
    try std.testing.expect(resp.action != null);
}

test "networkError creates network error" {
    const resp = networkError("Connection refused");
    try std.testing.expect(resp.isError());
    try std.testing.expect(std.mem.eql(u8, resp.code.?, "NETWORK"));
}

test "all documented error codes have actions" {
    for (api_errors) |entry| {
        try std.testing.expect(entry.action.len > 0);
        try std.testing.expect(entry.code.len > 0);
    }
}
