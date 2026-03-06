const std = @import("std");

/// Result of phone number validation.
pub const PhoneValidation = struct {
    valid: bool,
    err: ?[]const u8,
    normalized: []const u8,
};

/// Convert Arabic-Indic (U+0660-U+0669) and Extended Arabic-Indic (U+06F0-U+06F9)
/// digits to Latin (0-9). Strips all non-digit characters. Strips leading zeros.
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

    // Strip leading zeros
    var start: usize = 0;
    while (start < result.items.len and result.items[start] == '0') {
        start += 1;
    }

    if (start == result.items.len) {
        // All zeros or empty
        result.clearAndFree();
        return try allocator.alloc(u8, 0);
    }

    if (start > 0) {
        const remaining = result.items.len - start;
        std.mem.copyForwards(u8, result.items[0..remaining], result.items[start..]);
        result.shrinkRetainingCapacity(remaining);
    }

    return try result.toOwnedSlice();
}

/// Validate a phone number input. Returns validation result with normalized form.
/// Never crashes on any input.
pub fn validatePhoneInput(allocator: std.mem.Allocator, phone: []const u8) !PhoneValidation {
    // Coerce to trimmed string
    const trimmed = std.mem.trim(u8, phone, " \t\r\n");

    // Empty / blank
    if (trimmed.len == 0) {
        return PhoneValidation{
            .valid = false,
            .err = "Phone number is required",
            .normalized = "",
        };
    }

    // Contains @ (email address)
    if (std.mem.indexOf(u8, trimmed, "@") != null) {
        return PhoneValidation{
            .valid = false,
            .err = "This looks like an email address, not a phone number",
            .normalized = "",
        };
    }

    const normalized = try normalizePhone(allocator, trimmed);

    // No digits found
    if (normalized.len == 0) {
        return PhoneValidation{
            .valid = false,
            .err = "Not a valid phone number, no digits found",
            .normalized = "",
        };
    }

    // Too short (< 7 digits)
    if (normalized.len < 7) {
        return PhoneValidation{
            .valid = false,
            .err = "Phone number is too short (minimum 7 digits)",
            .normalized = normalized,
        };
    }

    // Too long (> 15 digits)
    if (normalized.len > 15) {
        allocator.free(normalized);
        return PhoneValidation{
            .valid = false,
            .err = "Phone number is too long (maximum 15 digits)",
            .normalized = "",
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

test "validatePhoneInput: valid minimum (7 digits)" {
    const allocator = std.testing.allocator;
    const result = try validatePhoneInput(allocator, "1234567");
    defer if (result.normalized.len > 0) allocator.free(@constCast(result.normalized));
    try std.testing.expect(result.valid);
    try std.testing.expect(result.err == null);
    try std.testing.expectEqualStrings("1234567", result.normalized);
}

test "validatePhoneInput: valid maximum (15 digits)" {
    const allocator = std.testing.allocator;
    const result = try validatePhoneInput(allocator, "123456789012345");
    defer if (result.normalized.len > 0) allocator.free(@constCast(result.normalized));
    try std.testing.expect(result.valid);
    try std.testing.expectEqualStrings("123456789012345", result.normalized);
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
