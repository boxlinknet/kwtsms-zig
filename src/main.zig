const std = @import("std");
const kwtsms = @import("kwtsms");

const stdout_file = std.io.getStdOut();
const stderr_file = std.io.getStdErr();

pub const Command = enum {
    help,
    verify,
    balance,
    senderid,
    coverage,
    send,
    validate,
    status,
    dlr,
    unknown,
};

pub const ParsedArgs = struct {
    command: Command,
    positional: []const []const u8,
    sender: ?[]const u8,
};

/// Map a command string to a Command enum.
pub fn parseCommand(arg: []const u8) Command {
    if (std.mem.eql(u8, arg, "help") or std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) return .help;
    if (std.mem.eql(u8, arg, "verify")) return .verify;
    if (std.mem.eql(u8, arg, "balance")) return .balance;
    if (std.mem.eql(u8, arg, "senderid")) return .senderid;
    if (std.mem.eql(u8, arg, "coverage")) return .coverage;
    if (std.mem.eql(u8, arg, "send")) return .send;
    if (std.mem.eql(u8, arg, "validate")) return .validate;
    if (std.mem.eql(u8, arg, "status")) return .status;
    if (std.mem.eql(u8, arg, "dlr")) return .dlr;
    return .unknown;
}

/// Parse command-line arguments into a structured ParsedArgs.
pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !ParsedArgs {
    if (args.len < 2) {
        return ParsedArgs{ .command = .help, .positional = try allocator.alloc([]const u8, 0), .sender = null };
    }

    const command = parseCommand(args[1]);

    var positional = std.ArrayList([]const u8).init(allocator);
    errdefer positional.deinit();
    var sender: ?[]const u8 = null;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--sender") and i + 1 < args.len) {
            i += 1;
            sender = args[i];
        } else {
            try positional.append(args[i]);
        }
    }

    return ParsedArgs{
        .command = command,
        .positional = try positional.toOwnedSlice(),
        .sender = sender,
    };
}

fn printUsage() void {
    stdout_file.writer().print(
        \\kwtsms - kwtSMS API command-line client
        \\
        \\Usage: kwtsms <command> [options]
        \\
        \\Commands:
        \\  verify                                Test credentials, show balance
        \\  balance                               Show available credits
        \\  senderid                              List sender IDs
        \\  coverage                              List active country prefixes
        \\  send <mobile> <message> [--sender ID] Send SMS
        \\  validate <number> [number ...]        Validate phone numbers
        \\  status <msg-id>                       Check message status
        \\  dlr <msg-id>                          Get delivery report
        \\  help                                  Show this help
        \\
        \\Configuration:
        \\  Set KWTSMS_USERNAME, KWTSMS_PASSWORD, KWTSMS_SENDER_ID,
        \\  KWTSMS_TEST_MODE, KWTSMS_LOG_FILE as environment variables
        \\  or in a .env file.
        \\
    , .{}) catch {};
}

fn printError(msg: []const u8, action: ?[]const u8) void {
    stderr_file.writer().print("Error: {s}\n", .{msg}) catch {};
    if (action) |a| {
        stderr_file.writer().print("  Fix: {s}\n", .{a}) catch {};
    }
}

fn printApiError(resp: kwtsms.ApiResponse) void {
    const w = stderr_file.writer();
    if (resp.description) |desc| {
        if (resp.code) |code| {
            w.print("Error [{s}]: {s}\n", .{ code, desc }) catch {};
        } else {
            w.print("Error: {s}\n", .{desc}) catch {};
        }
    } else {
        w.print("Error: API returned an error\n", .{}) catch {};
    }
    if (resp.action) |action| {
        w.print("  Fix: {s}\n", .{action}) catch {};
    }
}

fn runVerify(client: *kwtsms.KwtSMS) !void {
    const result = try client.verify();
    const w = stdout_file.writer();
    if (result.ok) {
        try w.print("OK\n", .{});
        if (result.balance) |b| {
            try w.print("Balance: {d:.2}\n", .{b});
        }
    } else {
        printError(result.err orelse "Verification failed", null);
        std.process.exit(1);
    }
}

fn runBalance(client: *kwtsms.KwtSMS) !void {
    const bal = try client.balance();
    if (bal) |b| {
        try stdout_file.writer().print("{d:.2}\n", .{b});
    } else {
        printError("Could not retrieve balance", null);
        std.process.exit(1);
    }
}

fn runSenderid(client: *kwtsms.KwtSMS) !void {
    const resp = try client.senderids();
    if (resp.isOk()) {
        if (resp.raw_body) |body| {
            // Extract senderid array from raw JSON
            printJsonArray(body, "senderid");
        } else {
            try stdout_file.writer().print("OK\n", .{});
        }
    } else {
        printApiError(resp);
        std.process.exit(1);
    }
}

fn runCoverage(client: *kwtsms.KwtSMS) !void {
    const resp = try client.coverage();
    if (resp.isOk()) {
        if (resp.raw_body) |body| {
            try stdout_file.writer().print("{s}\n", .{body});
        } else {
            try stdout_file.writer().print("OK\n", .{});
        }
    } else {
        printApiError(resp);
        std.process.exit(1);
    }
}

fn runSend(client: *kwtsms.KwtSMS, positional: []const []const u8, sender: ?[]const u8) !void {
    if (positional.len < 2) {
        printError("Usage: kwtsms send <mobile> <message> [--sender ID]", null);
        std.process.exit(1);
    }

    const mobile = positional[0];
    const msg = positional[1];

    // Test mode warning
    if (client.test_mode) {
        stderr_file.writer().print("WARNING: Test mode is ON. Messages will be queued but NOT delivered.\n", .{}) catch {};
    }

    // Split comma-separated numbers
    const w = stdout_file.writer();
    if (std.mem.indexOf(u8, mobile, ",") != null) {
        // Multiple numbers: split and use send()
        var numbers = std.ArrayList([]const u8).init(client.allocator);
        defer numbers.deinit();
        var iter = std.mem.splitScalar(u8, mobile, ',');
        while (iter.next()) |num| {
            const trimmed = std.mem.trim(u8, num, " ");
            if (trimmed.len > 0) {
                try numbers.append(trimmed);
            }
        }
        const resp = try client.send(numbers.items, msg, sender);
        if (resp.isOk()) {
            try w.print("OK\n", .{});
            if (resp.msg_id) |id| try w.print("msg-id: {s}\n", .{id});
            if (resp.numbers) |n| try w.print("numbers: {d}\n", .{n});
            if (resp.points_charged) |p| try w.print("points-charged: {d}\n", .{p});
            if (resp.balance_after) |b| try w.print("balance-after: {d:.2}\n", .{b});
        } else {
            printApiError(resp);
            std.process.exit(1);
        }
    } else {
        // Single number
        const resp = try client.sendOne(mobile, msg, sender);
        if (resp.isOk()) {
            try w.print("OK\n", .{});
            if (resp.msg_id) |id| try w.print("msg-id: {s}\n", .{id});
            if (resp.numbers) |n| try w.print("numbers: {d}\n", .{n});
            if (resp.points_charged) |p| try w.print("points-charged: {d}\n", .{p});
            if (resp.balance_after) |b| try w.print("balance-after: {d:.2}\n", .{b});
        } else {
            printApiError(resp);
            std.process.exit(1);
        }
    }
}

fn runValidate(client: *kwtsms.KwtSMS, positional: []const []const u8) !void {
    if (positional.len < 1) {
        printError("Usage: kwtsms validate <number> [number ...]", null);
        std.process.exit(1);
    }

    const resp = try client.validate(positional);
    if (resp.isOk()) {
        if (resp.raw_body) |body| {
            try stdout_file.writer().print("{s}\n", .{body});
        } else {
            try stdout_file.writer().print("OK\n", .{});
        }
    } else {
        printApiError(resp);
        std.process.exit(1);
    }
}

fn runStatus(client: *kwtsms.KwtSMS, positional: []const []const u8) !void {
    if (positional.len < 1) {
        printError("Usage: kwtsms status <msg-id>", null);
        std.process.exit(1);
    }

    const resp = try client.status(positional[0]);
    const w = stdout_file.writer();
    if (resp.isOk()) {
        if (resp.raw_body) |body| {
            try w.print("{s}\n", .{body});
        } else {
            try w.print("OK\n", .{});
        }
    } else {
        printApiError(resp);
        std.process.exit(1);
    }
}

fn runDlr(client: *kwtsms.KwtSMS, positional: []const []const u8) !void {
    if (positional.len < 1) {
        printError("Usage: kwtsms dlr <msg-id>", null);
        std.process.exit(1);
    }

    const resp = try client.dlr(positional[0]);
    const w = stdout_file.writer();
    if (resp.isOk()) {
        if (resp.raw_body) |body| {
            try w.print("{s}\n", .{body});
        } else {
            try w.print("OK\n", .{});
        }
    } else {
        printApiError(resp);
        std.process.exit(1);
    }
}

/// Extract and print values from a JSON array field (e.g., "senderid":["KWT-SMS","MY-APP"]).
fn printJsonArray(json: []const u8, key: []const u8) void {
    const w = stdout_file.writer();
    // Find "key":[ pattern
    var search_buf: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&search_buf, "\"{s}\":[", .{key}) catch {
        w.print("{s}\n", .{json}) catch {};
        return;
    };

    const idx = std.mem.indexOf(u8, json, needle) orelse {
        w.print("{s}\n", .{json}) catch {};
        return;
    };

    const arr_start = idx + needle.len;
    const arr_end = std.mem.indexOfPos(u8, json, arr_start, "]") orelse {
        w.print("{s}\n", .{json}) catch {};
        return;
    };

    const arr_content = json[arr_start..arr_end];

    // Parse comma-separated quoted strings
    var iter = std.mem.splitScalar(u8, arr_content, ',');
    while (iter.next()) |item| {
        const trimmed = std.mem.trim(u8, item, " \t\"");
        if (trimmed.len > 0) {
            w.print("{s}\n", .{trimmed}) catch {};
        }
    }
}

pub fn main() void {
    const allocator = std.heap.page_allocator;

    const args = std.process.argsAlloc(allocator) catch {
        printError("Failed to read command-line arguments", null);
        std.process.exit(1);
    };
    defer std.process.argsFree(allocator, args);

    // Convert [:0]u8 slice to []const u8 slice for parseArgs
    const arg_slices = allocator.alloc([]const u8, args.len) catch {
        printError("Out of memory", null);
        std.process.exit(1);
    };
    defer allocator.free(arg_slices);
    for (args, 0..) |arg, i| {
        arg_slices[i] = arg;
    }

    const parsed = parseArgs(allocator, arg_slices) catch {
        printError("Failed to parse arguments", null);
        std.process.exit(1);
    };
    defer allocator.free(parsed.positional);

    if (parsed.command == .help) {
        printUsage();
        return;
    }

    if (parsed.command == .unknown) {
        if (arg_slices.len > 1) {
            var err_buf: [256]u8 = undefined;
            const err_msg = std.fmt.bufPrint(&err_buf, "Unknown command: {s}", .{arg_slices[1]}) catch "Unknown command";
            printError(err_msg, null);
        }
        printUsage();
        std.process.exit(1);
    }

    // All other commands need a client
    var client = kwtsms.KwtSMS.fromEnv(allocator, null) catch {
        printError("Failed to load configuration. Set KWTSMS_USERNAME and KWTSMS_PASSWORD.", null);
        std.process.exit(1);
    };

    if (client.username.len == 0 or client.password.len == 0) {
        printError("Credentials not configured. Set KWTSMS_USERNAME and KWTSMS_PASSWORD environment variables or create a .env file.", null);
        std.process.exit(1);
    }

    const run_err = switch (parsed.command) {
        .verify => runVerify(&client),
        .balance => runBalance(&client),
        .senderid => runSenderid(&client),
        .coverage => runCoverage(&client),
        .send => runSend(&client, parsed.positional, parsed.sender),
        .validate => runValidate(&client, parsed.positional),
        .status => runStatus(&client, parsed.positional),
        .dlr => runDlr(&client, parsed.positional),
        else => unreachable,
    };

    run_err catch {
        printError("Connection failed. Check your network and try again.", null);
        std.process.exit(1);
    };
}

// -- Tests --

test "parseCommand: all valid commands" {
    try std.testing.expectEqual(Command.help, parseCommand("help"));
    try std.testing.expectEqual(Command.help, parseCommand("--help"));
    try std.testing.expectEqual(Command.help, parseCommand("-h"));
    try std.testing.expectEqual(Command.verify, parseCommand("verify"));
    try std.testing.expectEqual(Command.balance, parseCommand("balance"));
    try std.testing.expectEqual(Command.senderid, parseCommand("senderid"));
    try std.testing.expectEqual(Command.coverage, parseCommand("coverage"));
    try std.testing.expectEqual(Command.send, parseCommand("send"));
    try std.testing.expectEqual(Command.validate, parseCommand("validate"));
    try std.testing.expectEqual(Command.status, parseCommand("status"));
    try std.testing.expectEqual(Command.dlr, parseCommand("dlr"));
}

test "parseCommand: unknown commands" {
    try std.testing.expectEqual(Command.unknown, parseCommand("foo"));
    try std.testing.expectEqual(Command.unknown, parseCommand(""));
    try std.testing.expectEqual(Command.unknown, parseCommand("VERIFY"));
}

test "parseArgs: no arguments returns help" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{"kwtsms"};
    const parsed = try parseArgs(allocator, &args);
    defer allocator.free(parsed.positional);
    try std.testing.expectEqual(Command.help, parsed.command);
    try std.testing.expectEqual(@as(usize, 0), parsed.positional.len);
    try std.testing.expect(parsed.sender == null);
}

test "parseArgs: verify command" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "kwtsms", "verify" };
    const parsed = try parseArgs(allocator, &args);
    defer allocator.free(parsed.positional);
    try std.testing.expectEqual(Command.verify, parsed.command);
    try std.testing.expectEqual(@as(usize, 0), parsed.positional.len);
}

test "parseArgs: send with positional args" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "kwtsms", "send", "96598765432", "Hello world" };
    const parsed = try parseArgs(allocator, &args);
    defer allocator.free(parsed.positional);
    try std.testing.expectEqual(Command.send, parsed.command);
    try std.testing.expectEqual(@as(usize, 2), parsed.positional.len);
    try std.testing.expectEqualStrings("96598765432", parsed.positional[0]);
    try std.testing.expectEqualStrings("Hello world", parsed.positional[1]);
    try std.testing.expect(parsed.sender == null);
}

test "parseArgs: send with --sender flag" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "kwtsms", "send", "96598765432", "Hello", "--sender", "MY-APP" };
    const parsed = try parseArgs(allocator, &args);
    defer allocator.free(parsed.positional);
    try std.testing.expectEqual(Command.send, parsed.command);
    try std.testing.expectEqual(@as(usize, 2), parsed.positional.len);
    try std.testing.expectEqualStrings("MY-APP", parsed.sender.?);
}

test "parseArgs: validate with multiple numbers" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "kwtsms", "validate", "96598765432", "96512345678", "invalid" };
    const parsed = try parseArgs(allocator, &args);
    defer allocator.free(parsed.positional);
    try std.testing.expectEqual(Command.validate, parsed.command);
    try std.testing.expectEqual(@as(usize, 3), parsed.positional.len);
}

test "parseArgs: status with msg-id" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "kwtsms", "status", "abc123def456" };
    const parsed = try parseArgs(allocator, &args);
    defer allocator.free(parsed.positional);
    try std.testing.expectEqual(Command.status, parsed.command);
    try std.testing.expectEqual(@as(usize, 1), parsed.positional.len);
    try std.testing.expectEqualStrings("abc123def456", parsed.positional[0]);
}

test "parseArgs: unknown command" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "kwtsms", "foo" };
    const parsed = try parseArgs(allocator, &args);
    defer allocator.free(parsed.positional);
    try std.testing.expectEqual(Command.unknown, parsed.command);
}

test "parseArgs: --sender without value is treated as positional" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "kwtsms", "send", "96598765432", "Hello", "--sender" };
    const parsed = try parseArgs(allocator, &args);
    defer allocator.free(parsed.positional);
    // --sender at end with no value is treated as positional
    try std.testing.expectEqual(@as(usize, 3), parsed.positional.len);
    try std.testing.expect(parsed.sender == null);
}
