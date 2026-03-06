const std = @import("std");
const kwtsms = @import("kwtsms");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var client = try kwtsms.KwtSMS.fromEnv(allocator, null);

    // Phone validation
    const validation = try kwtsms.validatePhoneInput(allocator, "user@example.com");
    if (!validation.valid) {
        std.debug.print("Invalid phone: {s}\n", .{validation.err.?});
    }

    // Message cleaning
    const cleaned = try kwtsms.cleanMessage(allocator, "Hello \xF0\x9F\x98\x80 World <b>bold</b>");
    defer allocator.free(cleaned);
    std.debug.print("Cleaned message: {s}\n", .{cleaned});

    // Send with error handling
    const resp = try client.sendOne("96598765432", "Test message", null);
    if (resp.isOk()) {
        std.debug.print("Success. msg-id: {s}\n", .{resp.msg_id.?});
    } else {
        std.debug.print("API Error: [{s}] {s}\n", .{
            resp.code orelse "UNKNOWN",
            resp.description orelse "No description",
        });
        if (resp.action) |action| {
            std.debug.print("How to fix: {s}\n", .{action});
        }
    }

    // Error code lookup
    if (kwtsms.errors.getAction("ERR003")) |action| {
        std.debug.print("ERR003 guidance: {s}\n", .{action});
    }
}
