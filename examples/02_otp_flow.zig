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

    // Generate OTP (use crypto random in production)
    var otp_buf: [6]u8 = undefined;
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();
    for (&otp_buf) |*c| {
        c.* = '0' + random.intRangeAtMost(u8, 0, 9);
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
