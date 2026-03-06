const std = @import("std");

/// Environment variable configuration keys.
pub const EnvConfig = struct {
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
    sender_id: ?[]const u8 = null,
    test_mode: bool = false,
    log_file: ?[]const u8 = null,
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
pub fn loadConfig(allocator: std.mem.Allocator, env_file: []const u8) !EnvConfig {
    var config = EnvConfig{};

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

    // Environment variables take priority over .env file
    config.username = std.posix.getenv("KWTSMS_USERNAME") orelse env_map.get("KWTSMS_USERNAME");
    config.password = std.posix.getenv("KWTSMS_PASSWORD") orelse env_map.get("KWTSMS_PASSWORD");
    config.sender_id = std.posix.getenv("KWTSMS_SENDER_ID") orelse env_map.get("KWTSMS_SENDER_ID");
    config.log_file = std.posix.getenv("KWTSMS_LOG_FILE") orelse env_map.get("KWTSMS_LOG_FILE");

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
