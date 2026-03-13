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

/// ValidateResult wraps the API response plus locally-rejected numbers.
/// Call deinit(allocator) to free the rejected slice and its error strings.
pub const ValidateResult = struct {
    response: ?ApiResponse,
    rejected: []InvalidEntry,

    pub fn deinit(self: ValidateResult, allocator: std.mem.Allocator) void {
        for (self.rejected) |entry| {
            allocator.free(@constCast(entry.err));
        }
        allocator.free(self.rejected);
    }
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

    /// M4 fix: free all heap-allocated fields.
    /// msg_ids entries are duped; batch_errors and invalid slices are allocated.
    /// raw_body pointers inside batch_errors are intentionally NOT freed (owned by ApiResponse).
    pub fn deinit(self: BulkSendResult, allocator: std.mem.Allocator) void {
        for (self.msg_ids) |id| allocator.free(@constCast(id));
        allocator.free(self.msg_ids);
        allocator.free(self.batch_errors);
        allocator.free(self.invalid);
    }
};

/// kwtSMS API client.
/// Thread-safe: uses mutex for cached balance.
pub const KwtSMS = struct {
    allocator: std.mem.Allocator,
    username: []const u8,
    password: []const u8,
    // C1 fix: holds ownership of strings loaded from a .env file (via fromEnv).
    // Null when using init() with caller-owned string literals.
    _env_config: ?env.EnvConfig = null,
    sender_id: []const u8,
    test_mode: bool,
    log_file: ?[]const u8,
    cached_balance: ?f64,
    cached_purchased: ?f64,
    mutex: std.Thread.Mutex,

    /// Free resources when the client was created via fromEnv().
    /// Not needed when using init() with string literals.
    pub fn deinit(self: *KwtSMS) void {
        if (self._env_config) |cfg| cfg.deinit(self.allocator);
        self._env_config = null;
    }

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
    /// C1 fix: config strings that came from the .env file are heap-duped by loadConfig.
    /// We store the EnvConfig in _env_config so they stay alive as long as the client does.
    /// Call client.deinit() when done to free them.
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
            ._env_config = config, // keeps duped strings alive
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

    /// Send a batch of already-validated numbers as comma-separated string (internal).
    fn sendBatchRaw(self: *KwtSMS, mobile_csv: []const u8, msg: []const u8, sender: []const u8) !ApiResponse {
        var body_buf: [8192]u8 = undefined;
        const body = request.buildSendBody(
            &body_buf,
            self.username,
            self.password,
            sender,
            mobile_csv,
            msg,
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

    /// Validate, normalize, and deduplicate phone numbers. Returns owned slices.
    fn prepareNumbers(self: *KwtSMS, mobiles: []const []const u8) !struct {
        valid: std.ArrayList([]const u8),
        seen: std.StringHashMap(void),
    } {
        var valid_numbers = std.ArrayList([]const u8).init(self.allocator);
        errdefer {
            for (valid_numbers.items) |n| self.allocator.free(@constCast(n));
            valid_numbers.deinit();
        }

        var seen = std.StringHashMap(void).init(self.allocator);
        errdefer seen.deinit();

        for (mobiles) |mobile| {
            const validation = try validatePhoneInput(self.allocator, mobile);

            if (!validation.valid) {
                if (validation.normalized.len > 0) {
                    self.allocator.free(@constCast(validation.normalized));
                }
                if (validation.err_allocated) {
                    if (validation.err) |e| self.allocator.free(@constCast(e));
                }
                continue; // Skip invalid numbers
            }

            // Free allocated format errors on valid path too (err is null for valid numbers,
            // but guard anyway)
            if (validation.err_allocated) {
                if (validation.err) |e| self.allocator.free(@constCast(e));
            }

            // Deduplicate
            if (seen.contains(validation.normalized)) {
                self.allocator.free(@constCast(validation.normalized));
                continue;
            }

            // M2 fix: append before put so that if seen.put fails (OOM), we can undo
            // the append and free the normalized string cleanly. This closes the window
            // where normalized would be in seen but not in valid_numbers, leaking on error.
            try valid_numbers.append(validation.normalized);
            seen.put(validation.normalized, {}) catch |err| {
                _ = valid_numbers.pop();
                self.allocator.free(@constCast(validation.normalized));
                return err;
            };
        }

        return .{ .valid = valid_numbers, .seen = seen };
    }

    /// Build comma-separated string from a slice of numbers.
    fn buildMobileCsv(self: *KwtSMS, numbers: []const []const u8) ![]u8 {
        var mobile_buf = std.ArrayList(u8).init(self.allocator);
        errdefer mobile_buf.deinit();
        for (numbers, 0..) |num, idx| {
            if (idx > 0) try mobile_buf.append(',');
            try mobile_buf.appendSlice(num);
        }
        return try mobile_buf.toOwnedSlice();
    }

    /// Send SMS to one or more phone numbers.
    /// Automatically validates/normalizes numbers and cleans the message.
    /// For >200 numbers, auto-splits into batches with 1s delay.
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
        var prepared = try self.prepareNumbers(mobiles);
        defer {
            for (prepared.valid.items) |n| self.allocator.free(@constCast(n));
            prepared.valid.deinit();
            prepared.seen.deinit();
        }

        if (prepared.valid.items.len == 0) {
            return makeError("ERR_INVALID_INPUT", "No valid phone numbers provided");
        }

        // Single batch (≤200 numbers)
        if (prepared.valid.items.len <= 200) {
            const csv = try self.buildMobileCsv(prepared.valid.items);
            defer self.allocator.free(csv);
            return self.sendBatchRaw(csv, trimmed_msg, effective_sender);
        }

        // Bulk: split into batches of 200 with 1s delay
        var last_resp: ApiResponse = makeError("ERR_INVALID_INPUT", "No batches sent");
        var total_numbers: i64 = 0;
        var total_points: i64 = 0;
        var batch_count: usize = 0;

        var offset: usize = 0;
        while (offset < prepared.valid.items.len) {
            const end = @min(offset + 200, prepared.valid.items.len);
            const batch = prepared.valid.items[offset..end];

            if (batch_count > 0) {
                std.time.sleep(1 * std.time.ns_per_s);
            }

            const csv = try self.buildMobileCsv(batch);
            defer self.allocator.free(csv);

            const resp = try self.sendBatchRaw(csv, trimmed_msg, effective_sender);

            if (resp.isOk()) {
                if (resp.numbers) |n| total_numbers += n;
                if (resp.points_charged) |p| total_points += p;
            }

            last_resp = resp;
            batch_count += 1;

            if (resp.isError()) break;
            offset = end;
        }

        // Return aggregated response
        last_resp.numbers = total_numbers;
        last_resp.points_charged = total_points;
        return last_resp;
    }

    /// Send SMS to multiple numbers with detailed per-batch results.
    /// Returns BulkSendResult with individual msg_ids for each batch.
    /// For >200 numbers, auto-splits into batches of 200 with 1s delay.
    pub fn sendBulk(self: *KwtSMS, mobiles: []const []const u8, msg: []const u8, sender: ?[]const u8) !BulkSendResult {
        const effective_sender = sender orelse self.sender_id;

        // Clean message
        const cleaned = try cleanMessage(self.allocator, msg);
        defer self.allocator.free(cleaned);

        const trimmed_msg = std.mem.trim(u8, cleaned, " \t\r\n");
        if (trimmed_msg.len == 0) {
            return BulkSendResult{
                .result = "ERROR",
                .bulk = false,
                .batches = 0,
                .numbers = 0,
                .points_charged = 0,
                .balance_after = 0,
                .msg_ids = try self.allocator.alloc([]const u8, 0),
                .batch_errors = try self.allocator.alloc(ApiResponse, 0),
                .invalid = try self.allocator.alloc(InvalidEntry, 0),
            };
        }

        // Validate and normalize phone numbers
        var prepared = try self.prepareNumbers(mobiles);
        defer {
            for (prepared.valid.items) |n| self.allocator.free(@constCast(n));
            prepared.valid.deinit();
            prepared.seen.deinit();
        }

        if (prepared.valid.items.len == 0) {
            return BulkSendResult{
                .result = "ERROR",
                .bulk = false,
                .batches = 0,
                .numbers = 0,
                .points_charged = 0,
                .balance_after = 0,
                .msg_ids = try self.allocator.alloc([]const u8, 0),
                .batch_errors = try self.allocator.alloc(ApiResponse, 0),
                .invalid = try self.allocator.alloc(InvalidEntry, 0),
            };
        }

        // Split into batches of 200
        const batch_size: usize = 200;
        var msg_ids = std.ArrayList([]const u8).init(self.allocator);
        errdefer {
            for (msg_ids.items) |id| self.allocator.free(@constCast(id));
            msg_ids.deinit();
        }
        var batch_errors = std.ArrayList(ApiResponse).init(self.allocator);
        errdefer batch_errors.deinit();

        var total_numbers: usize = 0;
        var total_points: i64 = 0;
        var last_balance: f64 = 0;
        var all_ok = true;
        var any_ok = false;
        var batch_count: usize = 0;

        var offset: usize = 0;
        while (offset < prepared.valid.items.len) {
            const end = @min(offset + batch_size, prepared.valid.items.len);
            const batch = prepared.valid.items[offset..end];

            // Delay between batches (1 second)
            if (batch_count > 0) {
                std.time.sleep(1 * std.time.ns_per_s);
            }

            const csv = try self.buildMobileCsv(batch);
            defer self.allocator.free(csv);

            const resp = try self.sendBatchRaw(csv, trimmed_msg, effective_sender);

            if (resp.isOk()) {
                any_ok = true;
                if (resp.msg_id) |id| {
                    try msg_ids.append(try self.allocator.dupe(u8, id));
                }
                if (resp.numbers) |n| total_numbers += @intCast(n);
                if (resp.points_charged) |p| total_points += p;
                if (resp.balance_after) |b| last_balance = b;
            } else {
                all_ok = false;
                try batch_errors.append(resp);
            }

            batch_count += 1;
            offset = end;
        }

        const result_str: []const u8 = if (all_ok and any_ok) "OK" else if (any_ok) "PARTIAL" else "ERROR";

        return BulkSendResult{
            .result = result_str,
            .bulk = batch_count > 1,
            .batches = batch_count,
            .numbers = total_numbers,
            .points_charged = total_points,
            .balance_after = last_balance,
            .msg_ids = try msg_ids.toOwnedSlice(),
            .batch_errors = try batch_errors.toOwnedSlice(),
            .invalid = try self.allocator.alloc(InvalidEntry, 0),
        };
    }

    /// Send SMS to a single phone number (convenience wrapper).
    pub fn sendOne(self: *KwtSMS, mobile: []const u8, msg: []const u8, sender: ?[]const u8) !ApiResponse {
        const mobiles = [_][]const u8{mobile};
        return self.send(&mobiles, msg, sender);
    }

    /// Validate phone numbers via the API.
    /// Returns a ValidateResult containing the API response and any locally-rejected numbers.
    /// Call result.deinit(allocator) when done.
    pub fn validate(self: *KwtSMS, phones: []const []const u8) !ValidateResult {
        var valid_numbers = std.ArrayList([]const u8).init(self.allocator);
        defer {
            for (valid_numbers.items) |n| self.allocator.free(@constCast(n));
            valid_numbers.deinit();
        }

        // L3 fix: collect rejected numbers instead of silently discarding them.
        var rejected = std.ArrayList(InvalidEntry).init(self.allocator);
        errdefer {
            for (rejected.items) |entry| self.allocator.free(@constCast(entry.err));
            rejected.deinit();
        }

        for (phones) |p| {
            const validation = try validatePhoneInput(self.allocator, p);
            if (validation.valid) {
                try valid_numbers.append(validation.normalized);
            } else {
                // Dupe the error string so InvalidEntry always owns it.
                const err_str = if (validation.err) |e| e else "invalid phone number";
                const owned_err = try self.allocator.dupe(u8, err_str);
                // Free original if it was heap-allocated
                if (validation.err_allocated) {
                    if (validation.err) |e| self.allocator.free(@constCast(e));
                }
                // normalized may be empty for totally unparseable input; free if allocated
                if (validation.normalized.len > 0) {
                    self.allocator.free(@constCast(validation.normalized));
                }
                try rejected.append(InvalidEntry{ .input = p, .err = owned_err });
            }
        }

        const rejected_slice = try rejected.toOwnedSlice();

        if (valid_numbers.items.len == 0) {
            return ValidateResult{
                .response = makeError("ERR_INVALID_INPUT", "No valid phone numbers to validate"),
                .rejected = rejected_slice,
            };
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
            // Free rejected_slice before returning error
            for (rejected_slice) |entry| self.allocator.free(@constCast(entry.err));
            self.allocator.free(rejected_slice);
            return error.OutOfMemory;
        };

        const resp = try request.apiRequest(self.allocator, "validate", body, self.log_file);
        return ValidateResult{ .response = resp, .rejected = rejected_slice };
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
        // M3 fix: 1024 bytes comfortably fits username(64) + password(64) + msg_id(up to ~400)
        // plus JSON framing. The old 512-byte buffer would overflow with long msg_ids.
        var buf: [1024]u8 = undefined;
        const body = request.buildMsgIdBody(&buf, self.username, self.password, msg_id) orelse {
            return errors.networkError("Failed to build request");
        };
        return try request.apiRequest(self.allocator, "status", body, self.log_file);
    }

    /// Get delivery report (international numbers only).
    pub fn dlr(self: *KwtSMS, msg_id: []const u8) !ApiResponse {
        // M3 fix: same 1024-byte buffer as status().
        var buf: [1024]u8 = undefined;
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

test "KwtSMS.fromEnv: strings from .env file are valid after return (C1 fix)" {
    const allocator = std.testing.allocator;

    const tmp_path = "/tmp/kwtsms_test_fromenv_uaf";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("KWTSMS_USERNAME=envuser\nKWTSMS_PASSWORD=envpass\nKWTSMS_SENDER_ID=ENVSENDER\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    var client = try KwtSMS.fromEnv(allocator, tmp_path);
    defer client.deinit();

    // These must be valid strings (not dangling pointers into freed env_map memory)
    try std.testing.expectEqualStrings("envuser", client.username);
    try std.testing.expectEqualStrings("envpass", client.password);
    try std.testing.expectEqualStrings("ENVSENDER", client.sender_id);
}

test "BulkSendResult.deinit: frees without crash (M4 fix)" {
    const allocator = std.testing.allocator;

    // Allocate a minimal BulkSendResult and verify deinit frees correctly
    const msg_ids = try allocator.alloc([]const u8, 2);
    msg_ids[0] = try allocator.dupe(u8, "msgid1");
    msg_ids[1] = try allocator.dupe(u8, "msgid2");
    const batch_errors = try allocator.alloc(ApiResponse, 0);
    const invalid = try allocator.alloc(InvalidEntry, 0);

    const result = BulkSendResult{
        .result = "OK",
        .bulk = false,
        .batches = 1,
        .numbers = 2,
        .points_charged = 2,
        .balance_after = 100.0,
        .msg_ids = msg_ids,
        .batch_errors = batch_errors,
        .invalid = invalid,
    };

    result.deinit(allocator); // Must free msg_ids[0], msg_ids[1], msg_ids slice, batch_errors, invalid
}

test "ValidateResult.deinit: frees rejected entries without crash (L3 fix)" {
    const allocator = std.testing.allocator;

    const rejected = try allocator.alloc(InvalidEntry, 2);
    rejected[0] = .{ .input = "bad1", .err = try allocator.dupe(u8, "too short") };
    rejected[1] = .{ .input = "bad2", .err = try allocator.dupe(u8, "unknown country code") };

    const vr = ValidateResult{ .response = null, .rejected = rejected };
    vr.deinit(allocator);
}

test "ValidateResult: all-invalid input returns rejected entries" {
    const allocator = std.testing.allocator;
    var client = KwtSMS.init(allocator, "user", "pass", null, false, null);

    const phones = [_][]const u8{ "abc", "123" };
    var result = try client.validate(&phones);
    defer result.deinit(allocator);

    // All inputs are locally invalid, so rejected must be non-empty
    try std.testing.expect(result.rejected.len > 0);
    // Response is an error makeError result (no API call made)
    try std.testing.expect(result.response != null);
    try std.testing.expect(result.response.?.isError());
}

test "ValidateResult: mixed input returns rejected slice for bad numbers" {
    // page_allocator: apiRequest allocates raw_body which is intentionally never freed (by design).
    const allocator = std.heap.page_allocator;
    var client = KwtSMS.init(allocator, "user", "pass", null, false, null);

    // One valid (Kuwait number), one garbage
    const phones = [_][]const u8{ "96598765432", "notaphone" };
    var result = try client.validate(&phones);
    defer result.deinit(allocator);

    // "notaphone" must appear in rejected
    try std.testing.expect(result.rejected.len == 1);
    try std.testing.expectEqualStrings("notaphone", result.rejected[0].input);
    try std.testing.expect(result.rejected[0].err.len > 0);
}
