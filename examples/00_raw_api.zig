// 00_raw_api.zig — Raw kwtSMS API calls without the client library.
//
// Demonstrates every kwtSMS endpoint using only std.http.Client.
// Copy-paste any section into your own project.
//
// Build:  zig build example-00
// Run:    ./zig-out/bin/example-00

const std = @import("std");

// ─── Configuration ───────────────────────────────────────────────────────────
// Change these to your kwtSMS API credentials.
const USERNAME = "ZIG_YOUR_USERNAME";
const PASSWORD = "ZIG_YOUR_PASSWORD";
const SENDER_ID = "KWT-SMS"; // Use your registered sender ID in production
const TEST_MODE = true; // true = messages queued but NOT delivered (no credits consumed)
// ─────────────────────────────────────────────────────────────────────────────

const API_BASE = "https://www.kwtsms.com/API/";

/// POST JSON to a kwtSMS endpoint and return the raw response body.
fn apiPost(allocator: std.mem.Allocator, endpoint: []const u8, json_body: []const u8) ![]u8 {
    // Build URL: https://www.kwtsms.com/API/<endpoint>/
    var url_buf: [256]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "{s}{s}/", .{ API_BASE, endpoint });
    const uri = try std.Uri.parse(url);

    // Create HTTP client and request
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var header_buf: [4096]u8 = undefined;
    var req = try client.open(.POST, uri, .{
        .server_header_buffer = &header_buf,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "Accept", .value = "application/json" },
        },
    });
    defer req.deinit();

    // Send JSON body
    req.transfer_encoding = .{ .content_length = json_body.len };
    try req.send();
    try req.writer().writeAll(json_body);
    try req.finish();
    try req.wait();

    // Read entire response
    return try req.reader().readAllAlloc(allocator, 1024 * 1024);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const out = std.io.getStdOut().writer();

    // ═══════════════════════════════════════════════════════════════════════
    // 1. BALANCE — Check account balance
    // ═══════════════════════════════════════════════════════════════════════
    try out.print("\n=== 1. Balance ===\n", .{});
    {
        var buf: [512]u8 = undefined;
        const body = try std.fmt.bufPrint(&buf,
            \\{{"username":"{s}","password":"{s}"}}
        , .{ USERNAME, PASSWORD });

        const response = try apiPost(allocator, "balance", body);
        try out.print("Request:  POST /API/balance/\n", .{});
        try out.print("Response: {s}\n", .{response});
        // Expected: {"result":"OK","available":150,"purchased":1000}
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 2. SENDER ID — List registered sender IDs
    // ═══════════════════════════════════════════════════════════════════════
    try out.print("\n=== 2. Sender IDs ===\n", .{});
    {
        var buf: [512]u8 = undefined;
        const body = try std.fmt.bufPrint(&buf,
            \\{{"username":"{s}","password":"{s}"}}
        , .{ USERNAME, PASSWORD });

        const response = try apiPost(allocator, "senderid", body);
        try out.print("Request:  POST /API/senderid/\n", .{});
        try out.print("Response: {s}\n", .{response});
        // Expected: {"result":"OK","senderid":["KWT-SMS","MY-APP"]}
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 3. COVERAGE — List active country prefixes
    // ═══════════════════════════════════════════════════════════════════════
    try out.print("\n=== 3. Coverage ===\n", .{});
    {
        var buf: [512]u8 = undefined;
        const body = try std.fmt.bufPrint(&buf,
            \\{{"username":"{s}","password":"{s}"}}
        , .{ USERNAME, PASSWORD });

        const response = try apiPost(allocator, "coverage", body);
        try out.print("Request:  POST /API/coverage/\n", .{});
        try out.print("Response: {s}\n", .{response});
        // Expected: {"result":"OK","coverage":["965","966","971",...]}
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 4. VALIDATE — Validate phone numbers before sending
    // ═══════════════════════════════════════════════════════════════════════
    try out.print("\n=== 4. Validate ===\n", .{});
    {
        var buf: [1024]u8 = undefined;
        const body = try std.fmt.bufPrint(&buf,
            \\{{"username":"{s}","password":"{s}","mobile":"96598765432,96512345678,invalid123"}}
        , .{ USERNAME, PASSWORD });

        const response = try apiPost(allocator, "validate", body);
        try out.print("Request:  POST /API/validate/\n", .{});
        try out.print("Numbers:  96598765432, 96512345678, invalid123\n", .{});
        try out.print("Response: {s}\n", .{response});
        // Expected: {"result":"OK","mobile":{"OK":["96598765432"],"ER":["invalid123"],"NR":["96512345678"]}}
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 5. SEND — Send an SMS (test mode)
    // ═══════════════════════════════════════════════════════════════════════
    try out.print("\n=== 5. Send SMS ===\n", .{});
    var saved_msg_id: ?[]const u8 = null;
    {
        var buf: [4096]u8 = undefined;
        const body = try std.fmt.bufPrint(&buf,
            \\{{"username":"{s}","password":"{s}","sender":"{s}","mobile":"96598765432","message":"Hello from Zig raw API example","test":"{s}"}}
        , .{ USERNAME, PASSWORD, SENDER_ID, if (TEST_MODE) "1" else "0" });

        const response = try apiPost(allocator, "send", body);
        try out.print("Request:  POST /API/send/\n", .{});
        try out.print("To:       96598765432\n", .{});
        try out.print("Message:  Hello from Zig raw API example\n", .{});
        try out.print("Test:     {s}\n", .{if (TEST_MODE) "yes (queued, not delivered)" else "no (LIVE)"});
        try out.print("Response: {s}\n", .{response});
        // Expected: {"result":"OK","msg-id":"abc123...","numbers":1,"points-charged":1,"balance-after":149,"unix-timestamp":1684763355}

        // Save msg-id for status/dlr checks below
        saved_msg_id = extractString(response, "msg-id");
        if (saved_msg_id) |id| {
            try out.print("Saved msg-id: {s}\n", .{id});
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 6. SEND (multiple numbers) — Comma-separated, max 200 per request
    // ═══════════════════════════════════════════════════════════════════════
    try out.print("\n=== 6. Send SMS (multiple numbers) ===\n", .{});
    {
        var buf: [4096]u8 = undefined;
        const body = try std.fmt.bufPrint(&buf,
            \\{{"username":"{s}","password":"{s}","sender":"{s}","mobile":"96598765432,96512345678","message":"Bulk hello from Zig","test":"{s}"}}
        , .{ USERNAME, PASSWORD, SENDER_ID, if (TEST_MODE) "1" else "0" });

        const response = try apiPost(allocator, "send", body);
        try out.print("Request:  POST /API/send/\n", .{});
        try out.print("To:       96598765432, 96512345678\n", .{});
        try out.print("Response: {s}\n", .{response});
        // Expected: {"result":"OK","msg-id":"...","numbers":2,"points-charged":2,...}
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 7. STATUS — Check message queue status (requires msg-id from send)
    // ═══════════════════════════════════════════════════════════════════════
    try out.print("\n=== 7. Status ===\n", .{});
    if (saved_msg_id) |msg_id| {
        var buf: [512]u8 = undefined;
        const body = try std.fmt.bufPrint(&buf,
            \\{{"username":"{s}","password":"{s}","msgid":"{s}"}}
        , .{ USERNAME, PASSWORD, msg_id });

        const response = try apiPost(allocator, "status", body);
        try out.print("Request:  POST /API/status/\n", .{});
        try out.print("msg-id:   {s}\n", .{msg_id});
        try out.print("Response: {s}\n", .{response});
        // Expected: {"result":"OK","status":"queued","description":"Message accepted and in delivery queue"}
        // Or test mode: {"result":"ERROR","code":"ERR030","description":"..."}
    } else {
        try out.print("Skipped (no msg-id from send step)\n", .{});
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 8. DLR — Delivery report (international numbers only, not Kuwait)
    // ═══════════════════════════════════════════════════════════════════════
    try out.print("\n=== 8. Delivery Report (DLR) ===\n", .{});
    if (saved_msg_id) |msg_id| {
        var buf: [512]u8 = undefined;
        const body = try std.fmt.bufPrint(&buf,
            \\{{"username":"{s}","password":"{s}","msgid":"{s}"}}
        , .{ USERNAME, PASSWORD, msg_id });

        const response = try apiPost(allocator, "dlr", body);
        try out.print("Request:  POST /API/dlr/\n", .{});
        try out.print("msg-id:   {s}\n", .{msg_id});
        try out.print("Response: {s}\n", .{response});
        // Expected: {"result":"ERROR","code":"ERR019","description":"No delivery reports found"}
        // (DLR is only available for international numbers, not Kuwait)
    } else {
        try out.print("Skipped (no msg-id from send step)\n", .{});
    }

    try out.print("\n=== Done ===\n", .{});
}

/// Extract a JSON string value by key from a response (minimal helper).
/// Example: extractString(json, "msg-id") returns the value of "msg-id".
fn extractString(json: []const u8, key: []const u8) ?[]const u8 {
    var search_buf: [128]u8 = undefined;
    const needle = std.fmt.bufPrint(&search_buf, "\"{s}\":", .{key}) catch return null;
    const idx = std.mem.indexOf(u8, json, needle) orelse return null;
    var start = idx + needle.len;
    while (start < json.len and (json[start] == ' ' or json[start] == '\t')) : (start += 1) {}
    if (start >= json.len or json[start] != '"') return null;
    start += 1;
    const end = std.mem.indexOfPos(u8, json, start, "\"") orelse return null;
    return json[start..end];
}
