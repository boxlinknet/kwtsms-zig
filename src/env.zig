const std = @import("std");

/// Environment variable configuration keys.
pub const EnvConfig = struct {
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
    sender_id: ?[]const u8 = null,
    test_mode: bool = false,
    log_file: ?[]const u8 = null,
    // Tracks which string fields were heap-duped from the .env file
    // and must be freed by the owner. Fields from process env are stable
    // pointers and must NOT be freed.
    _owned_username: bool = false,
    _owned_password: bool = false,
    _owned_sender_id: bool = false,
    _owned_log_file: bool = false,

    /// Free heap-allocated strings loaded from the .env file.
    /// Do NOT call on configs built from process-env-only values.
    pub fn deinit(self: EnvConfig, allocator: std.mem.Allocator) void {
        if (self._owned_username) if (self.username) |s| allocator.free(@constCast(s));
        if (self._owned_password) if (self.password) |s| allocator.free(@constCast(s));
        if (self._owned_sender_id) if (self.sender_id) |s| allocator.free(@constCast(s));
        if (self._owned_log_file) if (self.log_file) |s| allocator.free(@constCast(s));
    }
};

/// Load a .env file and return a map of key-value pairs.
/// Returns empty map if file does not exist. Never fails.
/// Handles:
/// - key=value pairs
/// - # comment lines (ignored)
/// - blank lines (ignored)
/// - quoted values: KWTSMS_SENDER_ID="MY APP" -> MY APP
/// - inline comments on unquoted values: KEY=value # comment -> value
pub fn loadEnvFile(allocator: std.mem.Allocator, path: []const u8) !std.StringHashMap([]const u8) {
    var map = std.StringHashMap([]const u8).init(allocator);

    const file = std.fs.cwd().openFile(path, .{}) catch {
        return map; // File not found: return empty map
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch {
        return map;
    };
    defer allocator.free(content);

    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip empty lines and comments
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Find '=' separator
        const eq_pos = std.mem.indexOf(u8, trimmed, "=") orelse continue;

        const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
        if (key.len == 0) continue;

        var value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

        // Handle quoted values
        if (value.len >= 2) {
            if ((value[0] == '"' and value[value.len - 1] == '"') or
                (value[0] == '\'' and value[value.len - 1] == '\''))
            {
                value = value[1 .. value.len - 1];
            } else {
                // Strip inline comments for unquoted values
                if (std.mem.indexOf(u8, value, " #")) |comment_pos| {
                    value = std.mem.trim(u8, value[0..comment_pos], " \t");
                }
            }
        }

        const owned_key = try allocator.dupe(u8, key);
        const owned_value = try allocator.dupe(u8, value);
        try map.put(owned_key, owned_value);
    }

    return map;
}

/// Load kwtSMS configuration from environment variables, falling back to .env file.
/// Process environment variables take priority. Values loaded from the .env file
/// are heap-duped; caller must call EnvConfig.deinit(allocator) when done.
pub fn loadConfig(allocator: std.mem.Allocator, env_file: []const u8) !EnvConfig {
    var config = EnvConfig{};
    // Free any duped strings if we error out mid-way
    errdefer config.deinit(allocator);

    // Load .env file as fallback
    var env_map = try loadEnvFile(allocator, env_file);
    defer {
        var it = env_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        env_map.deinit();
    }

    // For each field: process env takes priority (stable pointer, no free needed).
    // Fallback to .env file: dupe the value so it survives after the map is freed.
    if (std.posix.getenv("KWTSMS_USERNAME")) |v| {
        config.username = v;
    } else if (env_map.get("KWTSMS_USERNAME")) |v| {
        config.username = try allocator.dupe(u8, v);
        config._owned_username = true;
    }

    if (std.posix.getenv("KWTSMS_PASSWORD")) |v| {
        config.password = v;
    } else if (env_map.get("KWTSMS_PASSWORD")) |v| {
        config.password = try allocator.dupe(u8, v);
        config._owned_password = true;
    }

    if (std.posix.getenv("KWTSMS_SENDER_ID")) |v| {
        config.sender_id = v;
    } else if (env_map.get("KWTSMS_SENDER_ID")) |v| {
        config.sender_id = try allocator.dupe(u8, v);
        config._owned_sender_id = true;
    }

    if (std.posix.getenv("KWTSMS_LOG_FILE")) |v| {
        config.log_file = v;
    } else if (env_map.get("KWTSMS_LOG_FILE")) |v| {
        config.log_file = try allocator.dupe(u8, v);
        config._owned_log_file = true;
    }

    const test_mode_str = std.posix.getenv("KWTSMS_TEST_MODE") orelse env_map.get("KWTSMS_TEST_MODE") orelse "0";
    config.test_mode = std.mem.eql(u8, test_mode_str, "1") or std.mem.eql(u8, test_mode_str, "true");

    return config;
}

// -- Tests --
test "loadEnvFile: missing file returns empty map" {
    const allocator = std.testing.allocator;
    var map = try loadEnvFile(allocator, "/tmp/nonexistent_kwtsms_test_env_file");
    defer map.deinit();
    try std.testing.expectEqual(@as(u32, 0), map.count());
}

test "loadEnvFile: parses key=value" {
    const allocator = std.testing.allocator;

    // Write a temp .env file
    const tmp_path = "/tmp/kwtsms_test_env_parse";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("KWTSMS_USERNAME=testuser\nKWTSMS_PASSWORD=testpass\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    var map = try loadEnvFile(allocator, tmp_path);
    defer {
        var it = map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        map.deinit();
    }

    try std.testing.expectEqualStrings("testuser", map.get("KWTSMS_USERNAME").?);
    try std.testing.expectEqualStrings("testpass", map.get("KWTSMS_PASSWORD").?);
}

test "loadEnvFile: strips quotes" {
    const allocator = std.testing.allocator;

    const tmp_path = "/tmp/kwtsms_test_env_quotes";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("KEY1=\"double quoted\"\nKEY2='single quoted'\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    var map = try loadEnvFile(allocator, tmp_path);
    defer {
        var it = map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        map.deinit();
    }

    try std.testing.expectEqualStrings("double quoted", map.get("KEY1").?);
    try std.testing.expectEqualStrings("single quoted", map.get("KEY2").?);
}

test "loadEnvFile: skips comments and blank lines" {
    const allocator = std.testing.allocator;

    const tmp_path = "/tmp/kwtsms_test_env_comments";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("# This is a comment\n\nKEY=value\n# Another comment\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    var map = try loadEnvFile(allocator, tmp_path);
    defer {
        var it = map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        map.deinit();
    }

    try std.testing.expectEqual(@as(u32, 1), map.count());
    try std.testing.expectEqualStrings("value", map.get("KEY").?);
}

test "loadEnvFile: strips inline comments" {
    const allocator = std.testing.allocator;

    const tmp_path = "/tmp/kwtsms_test_env_inline";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("SENDER=MY-APP  # my sender ID\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    var map = try loadEnvFile(allocator, tmp_path);
    defer {
        var it = map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        map.deinit();
    }

    try std.testing.expectEqualStrings("MY-APP", map.get("SENDER").?);
}

test "loadEnvFile: values with equals signs" {
    const allocator = std.testing.allocator;

    const tmp_path = "/tmp/kwtsms_test_env_equals";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("PASS=abc=def=ghi\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    var map = try loadEnvFile(allocator, tmp_path);
    defer {
        var it = map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        map.deinit();
    }

    try std.testing.expectEqualStrings("abc=def=ghi", map.get("PASS").?);
}

test "loadConfig: values from .env file are owned and survive after return" {
    const allocator = std.testing.allocator;

    const tmp_path = "/tmp/kwtsms_test_loadconfig_owner";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("KWTSMS_USERNAME=cfguser\nKWTSMS_PASSWORD=cfgpass\nKWTSMS_SENDER_ID=TESTSENDER\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const config = try loadConfig(allocator, tmp_path);
    defer config.deinit(allocator);

    // Values must be accessible (not use-after-free) after loadConfig returns
    try std.testing.expectEqualStrings("cfguser", config.username.?);
    try std.testing.expectEqualStrings("cfgpass", config.password.?);
    try std.testing.expectEqualStrings("TESTSENDER", config.sender_id.?);
    try std.testing.expect(config._owned_username);
    try std.testing.expect(config._owned_password);
    try std.testing.expect(config._owned_sender_id);
}

test "loadConfig: missing file returns empty config" {
    const allocator = std.testing.allocator;
    const config = try loadConfig(allocator, "/tmp/nonexistent_kwtsms_config_test");
    defer config.deinit(allocator);
    try std.testing.expect(config.username == null);
    try std.testing.expect(config.password == null);
    try std.testing.expect(!config.test_mode);
}

test "loadConfig: test_mode parsed correctly" {
    const allocator = std.testing.allocator;

    const tmp_path = "/tmp/kwtsms_test_loadconfig_testmode";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("KWTSMS_TEST_MODE=1\n");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const config = try loadConfig(allocator, tmp_path);
    defer config.deinit(allocator);
    try std.testing.expect(config.test_mode);
}
