const std = @import("std");
const kwtsms = @import("kwtsms");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create client from environment variables / .env file
    var client = try kwtsms.KwtSMS.fromEnv(allocator, null);

    // Verify credentials
    const verify_result = try client.verify();
    if (verify_result.ok) {
        std.debug.print("Connected. Balance: {d:.2}\n", .{verify_result.balance.?});
    } else {
        std.debug.print("Verification failed: {s}\n", .{verify_result.err.?});
        return;
    }

    // Send SMS
    const resp = try client.sendOne("96598765432", "Hello from kwtsms-zig!", null);
    if (resp.isOk()) {
        std.debug.print("Sent. msg-id: {s}, balance: {d:.2}\n", .{
            resp.msg_id.?,
            resp.balance_after.?,
        });
    } else {
        std.debug.print("Error: {s}\n", .{resp.description.?});
        if (resp.action) |action| {
            std.debug.print("Action: {s}\n", .{action});
        }
    }
}
