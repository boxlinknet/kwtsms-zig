const std = @import("std");
const kwtsms = @import("kwtsms");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create client with test mode enabled
    var client = kwtsms.KwtSMS.init(
        allocator,
        "zig_username",
        "zig_password",
        "YOUR-SENDER", // Use a Transactional sender ID for OTP
        true, // test mode: set to false in production
        null,
    );

    // Generate OTP using the OS CSPRNG directly.
    // L1 fix: do not use a PRNG seeded from a timestamp — predictable within same second.
    // std.crypto.random draws from the OS entropy source on every call.
    var otp_buf: [6]u8 = undefined;
    for (&otp_buf) |*c| {
        c.* = '0' + std.crypto.random.intRangeAtMost(u8, 0, 9);
    }

    // Send OTP
    var msg_buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&msg_buf, "Your OTP for MyApp is: {s}. Valid for 5 minutes.", .{otp_buf}) catch unreachable;

    const resp = try client.sendOne("+96598765432", msg, null);
    if (resp.isOk()) {
        std.debug.print("OTP sent. msg-id: {s}\n", .{resp.msg_id.?});
        // Save msg-id and OTP to your database for verification
    } else {
        std.debug.print("Failed: {s}\n", .{resp.description.?});
    }
}
