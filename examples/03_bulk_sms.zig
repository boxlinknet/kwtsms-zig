const std = @import("std");
const kwtsms = @import("kwtsms");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var client = try kwtsms.KwtSMS.fromEnv(allocator, null);

    // Send to multiple numbers
    const mobiles = [_][]const u8{
        "96598765432",
        "+96512345678",
        "0096587654321",
    };

    const resp = try client.send(&mobiles, "Bulk message from kwtsms-zig", null);
    if (resp.isOk()) {
        std.debug.print("Sent to {d} numbers. Points: {d}, Balance: {d:.2}\n", .{
            resp.numbers.?,
            resp.points_charged.?,
            resp.balance_after.?,
        });
    } else {
        std.debug.print("Error: {s}\n", .{resp.description.?});
    }
}
