const std = @import("std");

/// Result of phone number validation.
pub const PhoneValidation = struct {
    valid: bool,
    /// Error message. When err_allocated is true, free with your allocator.
    err: ?[]const u8,
    normalized: []const u8,
    /// True when err was allocated by the caller's allocator and must be freed.
    err_allocated: bool = false,
};

/// Country-specific format rules for local numbers (digits after country code).
pub const PhoneRule = struct {
    /// Valid digit counts for the local part (after the country code).
    local_lengths: []const u8,
    /// Each byte is a valid first digit for mobile numbers.
    /// Empty slice means any starting digit is accepted.
    mobile_start: []const u8,
};

/// Phone number format rules by country code (longest-match wins).
/// Sources: ITU-T E.164, national numbering plans, Wikipedia.
///
/// local_lengths: valid digit count(s) AFTER country code.
/// mobile_start: valid first digit(s) of the local number. Empty = any.
pub const phone_rules = std.StaticStringMap(PhoneRule).initComptime(.{
    // === GCC ===
    .{ "965", PhoneRule{ .local_lengths = &[_]u8{8}, .mobile_start = "4569" } }, // Kuwait: 4x=Virgin/STC, 5x=STC/Zain, 6x=Ooredoo, 9x=Zain
    .{ "966", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "5" } }, // Saudi Arabia: 50-59
    .{ "971", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "5" } }, // UAE: 50,52-56,58
    .{ "973", PhoneRule{ .local_lengths = &[_]u8{8}, .mobile_start = "36" } }, // Bahrain: 3x,6x
    .{ "974", PhoneRule{ .local_lengths = &[_]u8{8}, .mobile_start = "3567" } }, // Qatar: 33,55,66,77
    .{ "968", PhoneRule{ .local_lengths = &[_]u8{8}, .mobile_start = "79" } }, // Oman: 7x,9x
    // === Levant ===
    .{ "962", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "7" } }, // Jordan: 75,77,78,79
    .{ "961", PhoneRule{ .local_lengths = &[_]u8{ 7, 8 }, .mobile_start = "378" } }, // Lebanon: 3x (7-digit), 7x/81 (8-digit)
    .{ "970", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "5" } }, // Palestine: 56=Jawwal, 59=Ooredoo
    .{ "964", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "7" } }, // Iraq: 75-79
    .{ "963", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "9" } }, // Syria: 93-96,98,99
    // === Other Arab ===
    .{ "967", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "7" } }, // Yemen: 70,71,73,77
    .{ "20", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "1" } }, // Egypt: 10,11,12,15
    .{ "218", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "9" } }, // Libya: 91-95
    .{ "216", PhoneRule{ .local_lengths = &[_]u8{8}, .mobile_start = "2459" } }, // Tunisia: 2x,4x,5x,9x
    .{ "212", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "67" } }, // Morocco: 6x,7x
    .{ "213", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "567" } }, // Algeria: 5x,6x,7x
    .{ "249", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "9" } }, // Sudan: 90,91,92,96,99
    // === Non-Arab Middle East ===
    .{ "98", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "9" } }, // Iran: 9x
    .{ "90", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "5" } }, // Turkey: 5x
    .{ "972", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "5" } }, // Israel: 50,52-55,58
    // === South Asia ===
    .{ "91", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "6789" } }, // India: 6-9x
    .{ "92", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "3" } }, // Pakistan: 3x
    .{ "880", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "1" } }, // Bangladesh: 1x
    .{ "94", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "7" } }, // Sri Lanka: 70-78
    .{ "960", PhoneRule{ .local_lengths = &[_]u8{7}, .mobile_start = "79" } }, // Maldives: 7x,9x
    // === East Asia ===
    .{ "86", PhoneRule{ .local_lengths = &[_]u8{11}, .mobile_start = "1" } }, // China: 13-19x
    .{ "81", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "789" } }, // Japan: 70,80,90
    .{ "82", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "1" } }, // South Korea: 010
    .{ "886", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "9" } }, // Taiwan: 9x
    // === Southeast Asia ===
    .{ "65", PhoneRule{ .local_lengths = &[_]u8{8}, .mobile_start = "89" } }, // Singapore: 8x,9x
    .{ "60", PhoneRule{ .local_lengths = &[_]u8{ 9, 10 }, .mobile_start = "1" } }, // Malaysia: 1x (9 or 10 digits)
    .{ "62", PhoneRule{ .local_lengths = &[_]u8{ 9, 10, 11, 12 }, .mobile_start = "8" } }, // Indonesia: 8x (variable length)
    .{ "63", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "9" } }, // Philippines: 9x
    .{ "66", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "689" } }, // Thailand: 6x,8x,9x
    .{ "84", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "35789" } }, // Vietnam: 3x,5x,7x,8x,9x
    .{ "95", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "9" } }, // Myanmar: 9x
    .{ "855", PhoneRule{ .local_lengths = &[_]u8{ 8, 9 }, .mobile_start = "16789" } }, // Cambodia: mixed lengths
    .{ "976", PhoneRule{ .local_lengths = &[_]u8{8}, .mobile_start = "689" } }, // Mongolia: 6x,8x,9x
    // === Europe ===
    .{ "44", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "7" } }, // UK: 7x
    .{ "33", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "67" } }, // France: 6x,7x
    .{ "49", PhoneRule{ .local_lengths = &[_]u8{ 10, 11 }, .mobile_start = "1" } }, // Germany: 15x,16x,17x
    .{ "39", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "3" } }, // Italy: 3x
    .{ "34", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "67" } }, // Spain: 6x,7x
    .{ "31", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "6" } }, // Netherlands: 6x
    .{ "32", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "" } }, // Belgium: length only
    .{ "41", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "7" } }, // Switzerland: 74-79
    .{ "43", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "6" } }, // Austria: 65x-69x
    .{ "47", PhoneRule{ .local_lengths = &[_]u8{8}, .mobile_start = "49" } }, // Norway: 4x,9x
    .{ "48", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "" } }, // Poland: length only
    .{ "30", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "6" } }, // Greece: 69x
    .{ "420", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "67" } }, // Czech Republic: 6x,7x
    .{ "46", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "7" } }, // Sweden: 7x
    .{ "45", PhoneRule{ .local_lengths = &[_]u8{8}, .mobile_start = "" } }, // Denmark: length only
    .{ "40", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "7" } }, // Romania: 7x
    .{ "36", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "" } }, // Hungary: length only
    .{ "380", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "" } }, // Ukraine: length only
    // === Americas ===
    .{ "1", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "" } }, // USA/Canada: no mobile-specific prefix
    .{ "52", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "" } }, // Mexico: no mobile-specific prefix since 2019
    .{ "55", PhoneRule{ .local_lengths = &[_]u8{11}, .mobile_start = "" } }, // Brazil: area code + 9 + subscriber
    .{ "57", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "3" } }, // Colombia: 3x
    .{ "54", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "9" } }, // Argentina: 9 + area + subscriber
    .{ "56", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "9" } }, // Chile: 9x
    .{ "58", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "4" } }, // Venezuela: 4x
    .{ "51", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "9" } }, // Peru: 9x
    .{ "593", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "9" } }, // Ecuador: 9x
    .{ "53", PhoneRule{ .local_lengths = &[_]u8{8}, .mobile_start = "56" } }, // Cuba: 5x,6x
    // === Africa ===
    .{ "27", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "678" } }, // South Africa: 6x,7x,8x
    .{ "234", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "789" } }, // Nigeria: 70,71,80,81,90,91
    .{ "254", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "17" } }, // Kenya: 1x,7x
    .{ "233", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "25" } }, // Ghana: 2x,5x
    .{ "251", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "79" } }, // Ethiopia: 7x,9x
    .{ "255", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "67" } }, // Tanzania: 6x,7x
    .{ "256", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "7" } }, // Uganda: 7x
    .{ "237", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "6" } }, // Cameroon: 6x
    .{ "225", PhoneRule{ .local_lengths = &[_]u8{10}, .mobile_start = "" } }, // Ivory Coast: length only
    .{ "221", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "7" } }, // Senegal: 7x
    .{ "252", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "67" } }, // Somalia: 6x,7x
    .{ "250", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "7" } }, // Rwanda: 7x
    // === Oceania ===
    .{ "61", PhoneRule{ .local_lengths = &[_]u8{9}, .mobile_start = "4" } }, // Australia: 4x
    .{ "64", PhoneRule{ .local_lengths = &[_]u8{ 8, 9, 10 }, .mobile_start = "2" } }, // New Zealand: 21,22,27-29
});

/// Find the country code in a normalized (digits-only, no leading zeros) phone number.
/// Tries 3-digit codes first, then 2-digit, then 1-digit (longest match wins).
/// Returns a slice of normalized pointing to the matched country code, or null.
pub fn findCountryCode(normalized: []const u8) ?[]const u8 {
    if (normalized.len >= 3 and phone_rules.get(normalized[0..3]) != null) return normalized[0..3];
    if (normalized.len >= 2 and phone_rules.get(normalized[0..2]) != null) return normalized[0..2];
    if (normalized.len >= 1 and phone_rules.get(normalized[0..1]) != null) return normalized[0..1];
    return null;
}

/// Validate a normalized phone number against country-specific format rules.
/// Checks local number length and mobile starting digit.
/// Numbers with no matching country rule pass through (generic E.164 only).
/// Returns null if valid, or an allocated error string if invalid (caller must free).
pub fn validatePhoneFormat(allocator: std.mem.Allocator, normalized: []const u8) !?[]u8 {
    const cc = findCountryCode(normalized) orelse return null; // unknown country: pass through
    const rule = phone_rules.get(cc).?;
    const local = normalized[cc.len..];

    // Check local number length.
    var valid_len = false;
    for (rule.local_lengths) |expected| {
        if (local.len == @as(usize, expected)) {
            valid_len = true;
            break;
        }
    }
    if (!valid_len) {
        var exp_buf: [32]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&exp_buf);
        const w = fbs.writer();
        for (rule.local_lengths, 0..) |l, i| {
            if (i > 0) try w.writeAll(" or ");
            try w.print("{d}", .{l});
        }
        return try std.fmt.allocPrint(
            allocator,
            "Invalid +{s} number: expected {s} local digits after country code, got {d}",
            .{ cc, fbs.getWritten(), local.len },
        );
    }

    // Check mobile starting digit.
    if (rule.mobile_start.len > 0 and local.len > 0) {
        var valid_prefix = false;
        for (rule.mobile_start) |c| {
            if (local[0] == c) {
                valid_prefix = true;
                break;
            }
        }
        if (!valid_prefix) {
            var starts_buf: [32]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&starts_buf);
            const w = fbs.writer();
            for (rule.mobile_start, 0..) |c, i| {
                if (i > 0) try w.writeAll(", ");
                try w.print("{c}", .{c});
            }
            return try std.fmt.allocPrint(
                allocator,
                "Invalid +{s} mobile number: must start with {s} after +{s}",
                .{ cc, fbs.getWritten(), cc },
            );
        }
    }

    return null; // valid
}

/// Normalize a phone number to digits-only E.164 format (no + prefix).
///
/// Steps:
///   1. Convert Arabic-Indic (U+0660-U+0669) and Extended Arabic-Indic (U+06F0-U+06F9) to Latin.
///   2. Strip all non-digit characters (+, spaces, dashes, dots, parens, etc.).
///   3. Strip global leading zeros (handles 00-prefix and 0-prefix dialing).
///   4. Strip domestic trunk prefix: leading 0 in the local part after country code.
///      e.g. 9660559xxxx (Saudi with trunk 0) -> 966559xxxx
///           97105xxxxxxx (UAE with trunk 0) -> 9715xxxxxxx
pub fn normalizePhone(allocator: std.mem.Allocator, phone: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    const trimmed = std.mem.trim(u8, phone, " \t\r\n");

    var i: usize = 0;
    while (i < trimmed.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(trimmed[i]) catch {
            i += 1;
            continue;
        };
        if (i + cp_len > trimmed.len) break;

        const cp = std.unicode.utf8Decode(trimmed[i..][0..cp_len]) catch {
            i += 1;
            continue;
        };

        // Arabic-Indic digits U+0660-U+0669
        if (cp >= 0x0660 and cp <= 0x0669) {
            try result.append(@intCast(cp - 0x0660 + '0'));
        }
        // Extended Arabic-Indic / Persian digits U+06F0-U+06F9
        else if (cp >= 0x06F0 and cp <= 0x06F9) {
            try result.append(@intCast(cp - 0x06F0 + '0'));
        }
        // ASCII digits
        else if (cp >= '0' and cp <= '9') {
            try result.append(@intCast(cp));
        }
        // Skip all other characters (spaces, +, dashes, dots, parens, etc.)

        i += cp_len;
    }

    // Step 3: Strip global leading zeros (handles 00xxx and 0xxx dialing prefixes).
    var start: usize = 0;
    while (start < result.items.len and result.items[start] == '0') {
        start += 1;
    }

    if (start == result.items.len) {
        result.clearAndFree();
        return try allocator.alloc(u8, 0);
    }

    if (start > 0) {
        const remaining = result.items.len - start;
        std.mem.copyForwards(u8, result.items[0..remaining], result.items[start..]);
        result.shrinkRetainingCapacity(remaining);
    }

    // Step 4: Strip domestic trunk prefix (leading 0 in local part after country code).
    // e.g. 9660559xxx -> 966559xxx, 97105xxx -> 9715xxx, 20010xxx -> 2010xxx
    if (findCountryCode(result.items)) |cc| {
        const local_start = cc.len;
        if (local_start < result.items.len and result.items[local_start] == '0') {
            var zeros: usize = 0;
            while (local_start + zeros < result.items.len and
                result.items[local_start + zeros] == '0')
            {
                zeros += 1;
            }
            const tail_start = local_start + zeros;
            const tail_len = result.items.len - tail_start;
            std.mem.copyForwards(
                u8,
                result.items[local_start .. local_start + tail_len],
                result.items[tail_start..],
            );
            result.shrinkRetainingCapacity(local_start + tail_len);
        }
    }

    return try result.toOwnedSlice();
}

/// Validate a phone number input. Returns a validation result with the normalized form.
/// Never crashes on any input.
///
/// Memory: result.normalized is allocated; free it when result.normalized.len > 0.
/// result.err is allocated when result.err_allocated is true; free it too in that case.
pub fn validatePhoneInput(allocator: std.mem.Allocator, phone: []const u8) !PhoneValidation {
    const trimmed = std.mem.trim(u8, phone, " \t\r\n");

    if (trimmed.len == 0) {
        return PhoneValidation{
            .valid = false,
            .err = "Phone number is required",
            .normalized = "",
        };
    }

    if (std.mem.indexOf(u8, trimmed, "@") != null) {
        return PhoneValidation{
            .valid = false,
            .err = "This looks like an email address, not a phone number",
            .normalized = "",
        };
    }

    const normalized = try normalizePhone(allocator, trimmed);

    if (normalized.len == 0) {
        return PhoneValidation{
            .valid = false,
            .err = "Not a valid phone number, no digits found",
            .normalized = "",
        };
    }

    if (normalized.len < 7) {
        return PhoneValidation{
            .valid = false,
            .err = "Phone number is too short (minimum 7 digits)",
            .normalized = normalized,
        };
    }

    if (normalized.len > 15) {
        allocator.free(normalized);
        return PhoneValidation{
            .valid = false,
            .err = "Phone number is too long (maximum 15 digits)",
            .normalized = "",
        };
    }

    // Country-specific format validation (length + mobile prefix).
    if (try validatePhoneFormat(allocator, normalized)) |fmt_err| {
        return PhoneValidation{
            .valid = false,
            .err = fmt_err,
            .normalized = normalized,
            .err_allocated = true,
        };
    }

    return PhoneValidation{
        .valid = true,
        .err = null,
        .normalized = normalized,
    };
}

// -- Tests --

test "normalizePhone: strips + prefix" {
    const allocator = std.testing.allocator;
    const result = try normalizePhone(allocator, "+96598765432");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("96598765432", result);
}

test "normalizePhone: strips 00 prefix" {
    const allocator = std.testing.allocator;
    const result = try normalizePhone(allocator, "0096598765432");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("96598765432", result);
}

test "normalizePhone: strips spaces" {
    const allocator = std.testing.allocator;
    const result = try normalizePhone(allocator, "965 9876 5432");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("96598765432", result);
}

test "normalizePhone: strips dashes" {
    const allocator = std.testing.allocator;
    const result = try normalizePhone(allocator, "965-9876-5432");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("96598765432", result);
}

test "normalizePhone: strips dots" {
    const allocator = std.testing.allocator;
    const result = try normalizePhone(allocator, "965.9876.5432");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("96598765432", result);
}

test "normalizePhone: strips parens" {
    const allocator = std.testing.allocator;
    const result = try normalizePhone(allocator, "(965) 98765432");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("96598765432", result);
}

test "normalizePhone: converts Arabic-Indic digits" {
    const allocator = std.testing.allocator;
    const result = try normalizePhone(allocator, "\xD9\xA9\xD9\xA6\xD9\xA5\xD9\xA9\xD9\xA8\xD9\xA7\xD9\xA6\xD9\xA5\xD9\xA4\xD9\xA3\xD9\xA2");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("96598765432", result);
}

test "normalizePhone: converts Extended Arabic-Indic / Persian digits" {
    const allocator = std.testing.allocator;
    const result = try normalizePhone(allocator, "\xDB\xB9\xDB\xB6\xDB\xB5\xDB\xB1\xDB\xB2\xDB\xB3\xDB\xB4\xDB\xB5\xDB\xB6\xDB\xB7\xDB\xB8");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("96512345678", result);
}

test "normalizePhone: empty string returns empty" {
    const allocator = std.testing.allocator;
    const result = try normalizePhone(allocator, "");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}

test "normalizePhone: only zeros returns empty" {
    const allocator = std.testing.allocator;
    const result = try normalizePhone(allocator, "0000");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}

test "normalizePhone: Saudi trunk prefix stripped (9660559... -> 966559...)" {
    const allocator = std.testing.allocator;
    // Saudi number dialed with domestic trunk 0: 966 + 0 + 559xxxxxx
    const result = try normalizePhone(allocator, "9660559123456");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("966559123456", result);
}

test "normalizePhone: UAE trunk prefix stripped (97105... -> 9715...)" {
    const allocator = std.testing.allocator;
    const result = try normalizePhone(allocator, "971050123456");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("97150123456", result);
}

test "normalizePhone: Egypt trunk prefix stripped (20010... -> 2010...)" {
    const allocator = std.testing.allocator;
    const result = try normalizePhone(allocator, "200101234567");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("20101234567", result);
}

test "normalizePhone: Kuwait no trunk prefix (correct number unchanged)" {
    const allocator = std.testing.allocator;
    const result = try normalizePhone(allocator, "96598765432");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("96598765432", result);
}

test "validatePhoneInput: empty string" {
    const allocator = std.testing.allocator;
    const result = try validatePhoneInput(allocator, "");
    try std.testing.expect(!result.valid);
    try std.testing.expectEqualStrings("Phone number is required", result.err.?);
}

test "validatePhoneInput: blank string" {
    const allocator = std.testing.allocator;
    const result = try validatePhoneInput(allocator, "   ");
    try std.testing.expect(!result.valid);
    try std.testing.expectEqualStrings("Phone number is required", result.err.?);
}

test "validatePhoneInput: email address" {
    const allocator = std.testing.allocator;
    const result = try validatePhoneInput(allocator, "user@example.com");
    try std.testing.expect(!result.valid);
    try std.testing.expect(std.mem.indexOf(u8, result.err.?, "email") != null);
}

test "validatePhoneInput: no digits" {
    const allocator = std.testing.allocator;
    const result = try validatePhoneInput(allocator, "abc");
    try std.testing.expect(!result.valid);
    try std.testing.expect(std.mem.indexOf(u8, result.err.?, "no digits") != null);
}

test "validatePhoneInput: too short" {
    const allocator = std.testing.allocator;
    const result = try validatePhoneInput(allocator, "12345");
    defer if (result.normalized.len > 0) allocator.free(@constCast(result.normalized));
    try std.testing.expect(!result.valid);
    try std.testing.expect(std.mem.indexOf(u8, result.err.?, "too short") != null);
}

test "validatePhoneInput: too long" {
    const allocator = std.testing.allocator;
    const result = try validatePhoneInput(allocator, "1234567890123456");
    try std.testing.expect(!result.valid);
    try std.testing.expect(std.mem.indexOf(u8, result.err.?, "too long") != null);
}

test "validatePhoneInput: valid minimum (7 digits, unknown country)" {
    // 2991234 starts with 299 (Greenland) which is not in our rules — passes through as unknown.
    const allocator = std.testing.allocator;
    const result = try validatePhoneInput(allocator, "2991234");
    defer if (result.normalized.len > 0) allocator.free(@constCast(result.normalized));
    try std.testing.expect(result.valid);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("2991234", result.normalized);
}

test "validatePhoneInput: valid maximum (15 digits, unknown country)" {
    // 299123456789012 starts with 299 (Greenland) which is not in our rules — passes through as unknown.
    const allocator = std.testing.allocator;
    const result = try validatePhoneInput(allocator, "299123456789012");
    defer if (result.normalized.len > 0) allocator.free(@constCast(result.normalized));
    try std.testing.expect(result.valid);
    try std.testing.expectEqualStrings("299123456789012", result.normalized);
}

test "validatePhoneInput: valid with + prefix" {
    const allocator = std.testing.allocator;
    const result = try validatePhoneInput(allocator, "+96598765432");
    defer if (result.normalized.len > 0) allocator.free(@constCast(result.normalized));
    try std.testing.expect(result.valid);
    try std.testing.expectEqualStrings("96598765432", result.normalized);
}

test "validatePhoneInput: valid with Arabic digits" {
    const allocator = std.testing.allocator;
    // ٩٦٥٩٨٧٦٥٤٣٢ = 96598765432
    const result = try validatePhoneInput(allocator, "\xD9\xA9\xD9\xA6\xD9\xA5\xD9\xA9\xD9\xA8\xD9\xA7\xD9\xA6\xD9\xA5\xD9\xA4\xD9\xA3\xD9\xA2");
    defer if (result.normalized.len > 0) allocator.free(@constCast(result.normalized));
    try std.testing.expect(result.valid);
    try std.testing.expectEqualStrings("96598765432", result.normalized);
}

test "validatePhoneInput: Kuwait valid mobile" {
    const allocator = std.testing.allocator;
    const result = try validatePhoneInput(allocator, "96598765432");
    defer if (result.normalized.len > 0) allocator.free(@constCast(result.normalized));
    try std.testing.expect(result.valid);
}

test "validatePhoneInput: Kuwait invalid prefix (starts with 1)" {
    const allocator = std.testing.allocator;
    const result = try validatePhoneInput(allocator, "96512345678");
    defer if (result.normalized.len > 0) allocator.free(@constCast(result.normalized));
    defer if (result.err_allocated) if (result.err) |e| allocator.free(@constCast(e));
    try std.testing.expect(!result.valid);
    try std.testing.expect(std.mem.indexOf(u8, result.err.?, "+965") != null);
}

test "validatePhoneInput: Saudi valid mobile" {
    const allocator = std.testing.allocator;
    const result = try validatePhoneInput(allocator, "966559123456");
    defer if (result.normalized.len > 0) allocator.free(@constCast(result.normalized));
    try std.testing.expect(result.valid);
}

test "validatePhoneInput: Saudi trunk 0 normalized and valid" {
    const allocator = std.testing.allocator;
    // 9660559123456 -> normalizes to 966559123456 (trunk 0 stripped)
    const result = try validatePhoneInput(allocator, "9660559123456");
    defer if (result.normalized.len > 0) allocator.free(@constCast(result.normalized));
    try std.testing.expect(result.valid);
    try std.testing.expectEqualStrings("966559123456", result.normalized);
}

test "findCountryCode: Kuwait" {
    const cc = findCountryCode("96598765432");
    try std.testing.expect(cc != null);
    try std.testing.expectEqualStrings("965", cc.?);
}

test "findCountryCode: Saudi Arabia" {
    const cc = findCountryCode("966559123456");
    try std.testing.expect(cc != null);
    try std.testing.expectEqualStrings("966", cc.?);
}

test "findCountryCode: USA (1-digit code)" {
    const cc = findCountryCode("12125551234");
    try std.testing.expect(cc != null);
    try std.testing.expectEqualStrings("1", cc.?);
}

test "findCountryCode: unknown returns null" {
    const cc = findCountryCode("9991234567");
    try std.testing.expect(cc == null);
}
