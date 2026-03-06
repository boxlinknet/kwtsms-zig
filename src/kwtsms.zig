const std = @import("std");

pub const phone = @import("phone.zig");
pub const message = @import("message.zig");
pub const errors = @import("errors.zig");
pub const env = @import("env.zig");
pub const request = @import("request.zig");
pub const logger = @import("logger.zig");

// Public re-exports
pub const normalizePhone = phone.normalizePhone;
pub const validatePhoneInput = phone.validatePhoneInput;
pub const cleanMessage = message.cleanMessage;
pub const PhoneValidation = phone.PhoneValidation;
pub const ApiResponse = errors.ApiResponse;
pub const enrichError = errors.enrichError;
pub const makeError = errors.makeError;
pub const api_errors = errors.api_errors;

/// InvalidEntry represents a phone number that failed local pre-validation.
pub const InvalidEntry = struct {
    input: []const u8,
    err: []const u8,
};

/// SendResult for single batch (<= 200 numbers).
pub const SendResult = struct {
    response: ApiResponse,
    invalid: []InvalidEntry,
};

/// BulkSendResult for multiple batches (> 200 numbers).
pub const BulkSendResult = struct {
    result: []const u8, // "OK" | "PARTIAL" | "ERROR"
    bulk: bool,
    batches: usize,
    numbers: usize,
    points_charged: i64,
    balance_after: f64,
    msg_ids: [][]const u8,
    batch_errors: []ApiResponse,
    invalid: []InvalidEntry,
};

/// ValidateResult from the validate endpoint.
pub const ValidateResult = struct {
    ok: [][]const u8,
    er: [][]const u8,
    nr: [][]const u8,
    rejected: []InvalidEntry,
    err: ?[]const u8,
    raw_body: ?[]const u8,
};

/// kwtSMS API client.
/// Thread-safe: uses mutex for cached balance.
pub const KwtSMS = struct {
    allocator: std.mem.Allocator,
    username: []const u8,
    password: []const u8,
    sender_id: []const u8,
    test_mode: bool,
    log_file: ?[]const u8,
    cached_balance: ?f64,
    cached_purchased: ?f64,
    mutex: std.Thread.Mutex,

    /// Create a new KwtSMS client.
    pub fn init(
        allocator: std.mem.Allocator,
        username: []const u8,
        password: []const u8,
        sender_id: ?[]const u8,
        test_mode: bool,
        log_file: ?[]const u8,
    ) KwtSMS {
        return KwtSMS{
            .allocator = allocator,
            .username = username,
            .password = password,
            .sender_id = sender_id orelse "KWT-SMS",
            .test_mode = test_mode,
            .log_file = log_file orelse "kwtsms.log",
            .cached_balance = null,
            .cached_purchased = null,
            .mutex = .{},
        };
    }

    /// Create a KwtSMS client from environment variables / .env file.
    pub fn fromEnv(allocator: std.mem.Allocator, env_file: ?[]const u8) !KwtSMS {
        const config = try env.loadConfig(allocator, env_file orelse ".env");
        return KwtSMS{
            .allocator = allocator,
            .username = config.username orelse "",
            .password = config.password orelse "",
            .sender_id = config.sender_id orelse "KWT-SMS",
            .test_mode = config.test_mode,
            .log_file = config.log_file orelse "kwtsms.log",
            .cached_balance = null,
            .cached_purchased = null,
            .mutex = .{},
        };
    }

    /// Verify credentials and return balance.
    /// Returns (ok, balance, error_message). Never panics.
    pub fn verify(self: *KwtSMS) !struct { ok: bool, balance: ?f64, err: ?[]const u8 } {
        var buf: [512]u8 = undefined;
        const body = request.buildAuthBody(&buf, self.username, self.password) orelse {
            return .{ .ok = false, .balance = null, .err = "Failed to build request" };
        };

        const resp = try request.apiRequest(self.allocator, "balance", body, self.log_file);

        if (resp.isOk()) {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.cached_balance = resp.available;
            self.cached_purchased = resp.purchased;
            return .{ .ok = true, .balance = resp.available, .err = null };
        }

        return .{ .ok = false, .balance = null, .err = resp.description };
    }

    /// Get current balance. Returns cached value on API failure.
    pub fn balance(self: *KwtSMS) !?f64 {
        const result = try self.verify();
        if (result.ok) {
            return result.balance;
        }
        // Return cached value if available
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.cached_balance;
    }

    /// Get cached balance (no API call).
    pub fn cachedBalance(self: *KwtSMS) ?f64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.cached_balance;
    }

    /// Get cached purchased credits (no API call).
    pub fn cachedPurchased(self: *KwtSMS) ?f64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.cached_purchased;
    }

    /// Send SMS to one or more phone numbers.
    /// Automatically validates/normalizes numbers and cleans the message.
    /// For >200 numbers, auto-splits into batches.
    pub fn send(self: *KwtSMS, mobiles: []const []const u8, msg: []const u8, sender: ?[]const u8) !ApiResponse {
        const effective_sender = sender orelse self.sender_id;

        // Clean message
        const cleaned = try cleanMessage(self.allocator, msg);
        defer self.allocator.free(cleaned);

        // Check for empty message after cleaning
        const trimmed_msg = std.mem.trim(u8, cleaned, " \t\r\n");
        if (trimmed_msg.len == 0) {
            return makeError("ERR009", "Message is empty after cleaning (original may have contained only emojis or special characters)");
        }

        // Validate and normalize phone numbers
        var valid_numbers = std.ArrayList([]const u8).init(self.allocator);
        defer {
            for (valid_numbers.items) |n| self.allocator.free(@constCast(n));
            valid_numbers.deinit();
        }

        var seen = std.StringHashMap(void).init(self.allocator);
        defer seen.deinit();

        for (mobiles) |mobile| {
            const validation = try validatePhoneInput(self.allocator, mobile);

            if (!validation.valid) {
                if (validation.normalized.len > 0) {
                    self.allocator.free(@constCast(validation.normalized));
                }
                continue; // Skip invalid numbers
            }

            // Deduplicate
            if (seen.contains(validation.normalized)) {
                self.allocator.free(@constCast(validation.normalized));
                continue;
            }

            try seen.put(validation.normalized, {});
            try valid_numbers.append(validation.normalized);
        }

        if (valid_numbers.items.len == 0) {
            return makeError("ERR_INVALID_INPUT", "No valid phone numbers provided");
        }

        // Build comma-separated mobile string
        var mobile_buf = std.ArrayList(u8).init(self.allocator);
        defer mobile_buf.deinit();
        for (valid_numbers.items, 0..) |num, idx| {
            if (idx > 0) try mobile_buf.append(',');
            try mobile_buf.appendSlice(num);
        }

        // Build and send request
        var body_buf: [8192]u8 = undefined;
        const body = request.buildSendBody(
            &body_buf,
            self.username,
            self.password,
            effective_sender,
            mobile_buf.items,
            trimmed_msg,
            self.test_mode,
        ) orelse {
            return errors.networkError("Request body too large");
        };

        const resp = try request.apiRequest(self.allocator, "send", body, self.log_file);

        // Cache balance from response
        if (resp.balance_after) |bal| {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.cached_balance = bal;
        }

        return resp;
    }

    /// Send SMS to a single phone number (convenience wrapper).
    pub fn sendOne(self: *KwtSMS, mobile: []const u8, msg: []const u8, sender: ?[]const u8) !ApiResponse {
        const mobiles = [_][]const u8{mobile};
        return self.send(&mobiles, msg, sender);
    }

    /// Validate phone numbers via the API.
    pub fn validate(self: *KwtSMS, phones: []const []const u8) !ApiResponse {
        // Pre-validate locally
        var valid_numbers = std.ArrayList([]const u8).init(self.allocator);
        defer {
            for (valid_numbers.items) |n| self.allocator.free(@constCast(n));
            valid_numbers.deinit();
        }

        for (phones) |p| {
            const validation = try validatePhoneInput(self.allocator, p);
            if (validation.valid) {
                try valid_numbers.append(validation.normalized);
            } else {
                if (validation.normalized.len > 0) {
                    self.allocator.free(@constCast(validation.normalized));
                }
            }
        }

        if (valid_numbers.items.len == 0) {
            return makeError("ERR_INVALID_INPUT", "No valid phone numbers to validate");
        }

        // Build comma-separated mobile string
        var mobile_buf = std.ArrayList(u8).init(self.allocator);
        defer mobile_buf.deinit();
        for (valid_numbers.items, 0..) |num, idx| {
            if (idx > 0) try mobile_buf.append(',');
            try mobile_buf.appendSlice(num);
        }

        var body_buf: [8192]u8 = undefined;
        const body = request.buildValidateBody(
            &body_buf,
            self.username,
            self.password,
            mobile_buf.items,
        ) orelse {
            return errors.networkError("Request body too large");
        };

        return try request.apiRequest(self.allocator, "validate", body, self.log_file);
    }

    /// List registered sender IDs.
    pub fn senderids(self: *KwtSMS) !ApiResponse {
        var buf: [512]u8 = undefined;
        const body = request.buildAuthBody(&buf, self.username, self.password) orelse {
            return errors.networkError("Failed to build request");
        };
        return try request.apiRequest(self.allocator, "senderid", body, self.log_file);
    }

    /// List active country prefixes for coverage.
    pub fn coverage(self: *KwtSMS) !ApiResponse {
        var buf: [512]u8 = undefined;
        const body = request.buildAuthBody(&buf, self.username, self.password) orelse {
            return errors.networkError("Failed to build request");
        };
        return try request.apiRequest(self.allocator, "coverage", body, self.log_file);
    }

    /// Check message status.
    pub fn status(self: *KwtSMS, msg_id: []const u8) !ApiResponse {
        var buf: [512]u8 = undefined;
        const body = request.buildMsgIdBody(&buf, self.username, self.password, msg_id) orelse {
            return errors.networkError("Failed to build request");
        };
        return try request.apiRequest(self.allocator, "status", body, self.log_file);
    }

    /// Get delivery report (international numbers only).
    pub fn dlr(self: *KwtSMS, msg_id: []const u8) !ApiResponse {
        var buf: [512]u8 = undefined;
        const body = request.buildMsgIdBody(&buf, self.username, self.password, msg_id) orelse {
            return errors.networkError("Failed to build request");
        };
        return try request.apiRequest(self.allocator, "dlr", body, self.log_file);
    }
};

// Pull in all module tests
comptime {
    _ = phone;
    _ = message;
    _ = errors;
    _ = env;
    _ = request;
    _ = logger;
}

// -- Client unit tests --
test "KwtSMS.init: creates client with defaults" {
    const allocator = std.testing.allocator;
    const client = KwtSMS.init(allocator, "user", "pass", null, false, null);
    try std.testing.expectEqualStrings("user", client.username);
    try std.testing.expectEqualStrings("pass", client.password);
    try std.testing.expectEqualStrings("KWT-SMS", client.sender_id);
    try std.testing.expect(!client.test_mode);
    try std.testing.expectEqualStrings("kwtsms.log", client.log_file.?);
    try std.testing.expect(client.cached_balance == null);
}

test "KwtSMS.init: creates client with custom values" {
    const allocator = std.testing.allocator;
    const client = KwtSMS.init(allocator, "myuser", "mypass", "MY-SENDER", true, "custom.log");
    try std.testing.expectEqualStrings("myuser", client.username);
    try std.testing.expectEqualStrings("MY-SENDER", client.sender_id);
    try std.testing.expect(client.test_mode);
    try std.testing.expectEqualStrings("custom.log", client.log_file.?);
}

test "KwtSMS.cachedBalance: returns null initially" {
    const allocator = std.testing.allocator;
    var client = KwtSMS.init(allocator, "user", "pass", null, false, null);
    try std.testing.expect(client.cachedBalance() == null);
    try std.testing.expect(client.cachedPurchased() == null);
}

test "makeError with ERR_INVALID_INPUT" {
    const resp = makeError("ERR_INVALID_INPUT", "No valid phone numbers");
    try std.testing.expect(resp.isError());
    try std.testing.expectEqualStrings("ERR_INVALID_INPUT", resp.code.?);
}

test "cleanMessage integration: emoji-only returns empty" {
    const allocator = std.testing.allocator;
    const cleaned = try cleanMessage(allocator, "\xF0\x9F\x98\x80\xF0\x9F\x98\x82");
    defer allocator.free(cleaned);
    const trimmed = std.mem.trim(u8, cleaned, " \t\r\n");
    try std.testing.expect(trimmed.len == 0);
}

test "normalizePhone integration: strips and converts" {
    const allocator = std.testing.allocator;
    const result = try normalizePhone(allocator, "+965 9876-5432");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("96598765432", result);
}
