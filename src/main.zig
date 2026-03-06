const std = @import("std");
const kwtsms = @import("kwtsms");

const stdout_file = std.io.getStdOut();
const stderr_file = std.io.getStdErr();

pub const Command = enum {
    help,
    setup,
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
    if (std.mem.eql(u8, arg, "setup")) return .setup;
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
        \\  setup                                 Interactive setup wizard (create .env)
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
        \\  Run 'kwtsms setup' to create a .env file interactively, or set
        \\  KWTSMS_USERNAME, KWTSMS_PASSWORD, KWTSMS_SENDER_ID,
        \\  KWTSMS_TEST_MODE, KWTSMS_LOG_FILE as environment variables.
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

/// Read a line from stdin into the provided buffer. Returns the trimmed slice.
fn readLine(buf: []u8) ?[]const u8 {
    const reader = std.io.getStdIn().reader();
    const line = reader.readUntilDelimiterOrEof(buf, '\n') catch return null;
    if (line) |l| {
        return std.mem.trim(u8, l, " \t\r\n");
    }
    return null;
}

/// Disable terminal echo for password input, restore on return.
fn readPassword(buf: []u8) ?[]const u8 {
    const stdin_fd = std.io.getStdIn().handle;
    const orig_termios = std.posix.tcgetattr(stdin_fd) catch {
        // Fallback: read without hiding (non-terminal, e.g. piped input)
        return readLine(buf);
    };

    var noecho = orig_termios;
    noecho.lflag.ECHO = false;
    std.posix.tcsetattr(stdin_fd, .FLUSH, noecho) catch {
        return readLine(buf);
    };
    defer {
        std.posix.tcsetattr(stdin_fd, .FLUSH, orig_termios) catch {};
        stdout_file.writer().print("\n", .{}) catch {};
    }

    return readLine(buf);
}

/// Try to fetch sender IDs and let user select one. Returns null if fetching fails.
fn fetchAndSelectSenderId(
    allocator: std.mem.Allocator,
    client: *kwtsms.KwtSMS,
    w: anytype,
    default_sender: []const u8,
    sid_buf: *[256]u8,
) ?[]const u8 {
    const resp = client.senderids() catch {
        w.print("(failed)\n", .{}) catch {};
        return null;
    };

    if (!resp.isOk()) {
        w.print("(failed)\n", .{}) catch {};
        return null;
    }

    const body = resp.raw_body orelse {
        w.print("(none returned)\n", .{}) catch {};
        return null;
    };

    // Parse senderid array from raw JSON
    var sids = std.ArrayList([]const u8).init(allocator);
    defer sids.deinit();

    var search_key_buf: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&search_key_buf, "\"senderid\":[", .{}) catch return null;
    const idx = std.mem.indexOf(u8, body, needle) orelse {
        w.print("(none returned)\n", .{}) catch {};
        return null;
    };
    const arr_start = idx + needle.len;
    const arr_end = std.mem.indexOfPos(u8, body, arr_start, "]") orelse {
        w.print("(none returned)\n", .{}) catch {};
        return null;
    };

    var iter = std.mem.splitScalar(u8, body[arr_start..arr_end], ',');
    while (iter.next()) |item| {
        const trimmed = std.mem.trim(u8, item, " \t\"");
        if (trimmed.len > 0) {
            sids.append(trimmed) catch {};
        }
    }

    if (sids.items.len == 0) {
        w.print("(none returned)\n", .{}) catch {};
        return null;
    }

    w.print("OK\n\nAvailable Sender IDs:\n", .{}) catch {};
    for (sids.items, 1..) |sid, i| {
        w.print("  {d}. {s}\n", .{ i, sid }) catch {};
    }
    const sid_default = if (default_sender.len > 0) default_sender else sids.items[0];
    w.print("\nSelect Sender ID (number or name) [{s}]: ", .{sid_default}) catch {};

    const sid_input = readLine(sid_buf) orelse return sid_default;
    if (sid_input.len == 0) return sid_default;

    // Check if it's a number selection
    const num = std.fmt.parseInt(usize, sid_input, 10) catch 0;
    if (num >= 1 and num <= sids.items.len) {
        return sids.items[num - 1];
    }
    return sid_input;
}

/// Interactive setup wizard: verify credentials, select sender ID, write .env file.
fn runSetup(allocator: std.mem.Allocator) void {
    const w = stdout_file.writer();

    w.print("\n── kwtSMS Setup ──────────────────────────────────────────────────\n", .{}) catch {};
    w.print("Verifies your API credentials and creates a .env file.\n", .{}) catch {};
    w.print("Press Enter to keep the value shown in brackets.\n\n", .{}) catch {};

    // Load existing .env values as defaults
    var env_map = kwtsms.env.loadEnvFile(allocator, ".env") catch {
        printError("Failed to read .env file", null);
        std.process.exit(1);
    };
    defer {
        var it = env_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        env_map.deinit();
    }

    const default_user = env_map.get("KWTSMS_USERNAME") orelse "";
    const default_pass = env_map.get("KWTSMS_PASSWORD") orelse "";
    const default_sender = env_map.get("KWTSMS_SENDER_ID") orelse "";
    const default_test_mode = env_map.get("KWTSMS_TEST_MODE") orelse "1";
    const default_log = env_map.get("KWTSMS_LOG_FILE") orelse "kwtsms.log";

    // --- Username ---
    var user_buf: [256]u8 = undefined;
    if (default_user.len > 0) {
        w.print("API Username [{s}]: ", .{default_user}) catch {};
    } else {
        w.print("API Username: ", .{}) catch {};
    }
    const user_input = readLine(&user_buf) orelse "";
    const username = if (user_input.len > 0) user_input else default_user;

    // --- Password (hidden) ---
    var pass_buf: [256]u8 = undefined;
    if (default_pass.len > 0) {
        w.print("API Password [keep existing]: ", .{}) catch {};
    } else {
        w.print("API Password: ", .{}) catch {};
    }
    const pass_input = readPassword(&pass_buf) orelse "";
    const password = if (pass_input.len > 0) pass_input else default_pass;

    if (username.len == 0 or password.len == 0) {
        w.print("\nError: username and password are required.\n", .{}) catch {};
        std.process.exit(1);
    }

    // --- Verify credentials ---
    w.print("\nVerifying credentials... ", .{}) catch {};
    var client = kwtsms.KwtSMS.init(allocator, username, password, null, true, "");
    const verify_result = client.verify() catch {
        w.print("FAILED\nError: Connection failed. Check your network and try again.\n", .{}) catch {};
        std.process.exit(1);
    };
    if (!verify_result.ok) {
        w.print("FAILED\nError: {s}\n", .{verify_result.err orelse "Wrong username or password"}) catch {};
        std.process.exit(1);
    }
    if (verify_result.balance) |b| {
        w.print("OK  (Balance: {d:.0})\n", .{b}) catch {};
    } else {
        w.print("OK\n", .{}) catch {};
    }

    // --- Fetch Sender IDs ---
    w.print("Fetching Sender IDs... ", .{}) catch {};
    var sender_id: []const u8 = default_sender;
    var sid_buf: [256]u8 = undefined;
    const got_sids = fetchAndSelectSenderId(allocator, &client, w, default_sender, &sid_buf);
    if (got_sids) |selected| {
        sender_id = selected;
    } else {
        const fallback = if (default_sender.len > 0) default_sender else "KWT-SMS";
        w.print("Sender ID [{s}]: ", .{fallback}) catch {};
        const sid_input = readLine(&sid_buf) orelse "";
        sender_id = if (sid_input.len > 0) sid_input else fallback;
    }

    // --- Send mode ---
    w.print("\nSend mode:\n", .{}) catch {};
    w.print("  1. Test mode: messages queued but NOT delivered, no credits consumed  [default]\n", .{}) catch {};
    w.print("  2. Live mode: messages delivered to handsets, credits consumed\n", .{}) catch {};

    const mode_default: []const u8 = if (std.mem.eql(u8, default_test_mode, "0")) "2" else "1";
    w.print("\nChoose [{s}]: ", .{mode_default}) catch {};

    var mode_buf: [16]u8 = undefined;
    const mode_input = readLine(&mode_buf) orelse "";
    const mode_choice = if (mode_input.len > 0) mode_input else mode_default;
    const test_mode: []const u8 = if (std.mem.eql(u8, mode_choice, "2")) "0" else "1";

    if (std.mem.eql(u8, test_mode, "1")) {
        w.print("  → Test mode selected.\n", .{}) catch {};
    } else {
        w.print("  → Live mode selected. Real messages will be sent and credits consumed.\n", .{}) catch {};
    }

    // --- Log file ---
    w.print("\nAPI logging (every API call is logged to a file, passwords are always masked):\n", .{}) catch {};
    if (default_log.len > 0) {
        w.print("  Current: {s}\n", .{default_log}) catch {};
    }
    w.print("  Type \"off\" to disable logging.\n", .{}) catch {};
    w.print("  Log file path [{s}]: ", .{if (default_log.len > 0) default_log else "off"}) catch {};

    var log_buf: [256]u8 = undefined;
    const log_input = readLine(&log_buf) orelse "";
    var log_file: []const u8 = default_log;
    if (log_input.len > 0) {
        if (std.mem.eql(u8, log_input, "off")) {
            log_file = "";
            w.print("  → Logging disabled.\n", .{}) catch {};
        } else {
            log_file = log_input;
        }
    }

    // --- Write .env file ---
    const env_file = std.fs.cwd().createFile(".env", .{}) catch {
        w.print("\nError writing .env file.\n", .{}) catch {};
        std.process.exit(1);
    };
    defer env_file.close();

    env_file.writer().print(
        \\# kwtSMS credentials, generated by kwtsms setup
        \\KWTSMS_USERNAME={s}
        \\KWTSMS_PASSWORD={s}
        \\KWTSMS_SENDER_ID={s}
        \\KWTSMS_TEST_MODE={s}
        \\KWTSMS_LOG_FILE={s}
        \\
    , .{ username, password, sender_id, test_mode, log_file }) catch {
        w.print("\nError writing .env file.\n", .{}) catch {};
        std.process.exit(1);
    };

    // Set file permissions to 0600 (owner read/write only)
    std.posix.fchmod(env_file.handle, 0o600) catch {};

    w.print("\n  Saved to .env\n", .{}) catch {};
    if (std.mem.eql(u8, test_mode, "1")) {
        w.print("  Mode: TEST: messages queued but not delivered (no credits consumed)\n", .{}) catch {};
    } else {
        w.print("  Mode: LIVE: messages will be delivered and credits consumed\n", .{}) catch {};
    }
    w.print("  Run 'kwtsms setup' at any time to change settings.\n", .{}) catch {};
    w.print("─────────────────────────────────────────────────────────────────\n\n", .{}) catch {};
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

    if (parsed.command == .setup) {
        runSetup(allocator);
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
        printError("Failed to load configuration. Run 'kwtsms setup' or set KWTSMS_USERNAME and KWTSMS_PASSWORD.", null);
        std.process.exit(1);
    };

    if (client.username.len == 0 or client.password.len == 0) {
        printError("Credentials not configured. Run 'kwtsms setup' or set KWTSMS_USERNAME and KWTSMS_PASSWORD environment variables.", null);
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
        .help, .setup => unreachable, // handled above
        .unknown => unreachable,
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
    try std.testing.expectEqual(Command.setup, parseCommand("setup"));
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

test "parseArgs: setup command" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "kwtsms", "setup" };
    const parsed = try parseArgs(allocator, &args);
    defer allocator.free(parsed.positional);
    try std.testing.expectEqual(Command.setup, parsed.command);
    try std.testing.expectEqual(@as(usize, 0), parsed.positional.len);
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
