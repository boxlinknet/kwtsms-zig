const std = @import("std");

/// Clean a message for SMS sending.
/// 1. Convert Arabic-Indic and Extended Arabic-Indic digits to Latin
/// 2. Remove emojis
/// 3. Remove hidden invisible characters (zero-width space, BOM, soft hyphen, etc.)
/// 4. Remove directional formatting characters
/// 5. Remove C0/C1 control characters (preserve \n and \t)
/// 6. Strip HTML tags
/// Arabic text is preserved.
pub fn cleanMessage(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < text.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch {
            i += 1;
            continue;
        };
        if (i + cp_len > text.len) break;

        const cp = std.unicode.utf8Decode(text[i..][0..cp_len]) catch {
            i += 1;
            continue;
        };

        // HTML tag stripping: skip '<' until '>'
        if (cp == '<') {
            var j = i + 1;
            while (j < text.len and text[j] != '>') : (j += 1) {}
            if (j < text.len) {
                i = j + 1; // skip past '>'
                continue;
            }
        }

        // Convert Arabic-Indic digits U+0660-U+0669
        if (cp >= 0x0660 and cp <= 0x0669) {
            try result.append(@intCast(cp - 0x0660 + '0'));
            i += cp_len;
            continue;
        }

        // Convert Extended Arabic-Indic / Persian digits U+06F0-U+06F9
        if (cp >= 0x06F0 and cp <= 0x06F9) {
            try result.append(@intCast(cp - 0x06F0 + '0'));
            i += cp_len;
            continue;
        }

        // Remove emojis
        if (isEmoji(cp)) {
            i += cp_len;
            continue;
        }

        // Remove hidden invisible characters
        if (isHiddenChar(cp)) {
            i += cp_len;
            continue;
        }

        // Remove directional formatting characters
        if (isDirectionalChar(cp)) {
            i += cp_len;
            continue;
        }

        // Remove C0/C1 control characters (preserve \n U+000A and \t U+0009)
        if (isControlChar(cp)) {
            i += cp_len;
            continue;
        }

        // Keep everything else (including Arabic letters)
        try result.appendSlice(text[i .. i + cp_len]);
        i += cp_len;
    }

    return try result.toOwnedSlice();
}

fn isEmoji(cp: u21) bool {
    // Mahjong tiles
    if (cp >= 0x1F000 and cp <= 0x1F02F) return true;
    // Playing cards
    if (cp >= 0x1F0A0 and cp <= 0x1F0FF) return true;
    // Regional indicator symbols / flags
    if (cp >= 0x1F1E0 and cp <= 0x1F1FF) return true;
    // Misc symbols and pictographs
    if (cp >= 0x1F300 and cp <= 0x1F5FF) return true;
    // Emoticons
    if (cp >= 0x1F600 and cp <= 0x1F64F) return true;
    // Transport and map
    if (cp >= 0x1F680 and cp <= 0x1F6FF) return true;
    // Alchemical symbols
    if (cp >= 0x1F700 and cp <= 0x1F77F) return true;
    // Geometric shapes extended
    if (cp >= 0x1F780 and cp <= 0x1F7FF) return true;
    // Supplemental arrows
    if (cp >= 0x1F800 and cp <= 0x1F8FF) return true;
    // Supplemental symbols and pictographs
    if (cp >= 0x1F900 and cp <= 0x1F9FF) return true;
    // Chess symbols
    if (cp >= 0x1FA00 and cp <= 0x1FA6F) return true;
    // Symbols and pictographs extended
    if (cp >= 0x1FA70 and cp <= 0x1FAFF) return true;
    // Misc symbols
    if (cp >= 0x2600 and cp <= 0x26FF) return true;
    // Dingbats
    if (cp >= 0x2700 and cp <= 0x27BF) return true;
    // Variation selectors (emoji style modifiers)
    if (cp >= 0xFE00 and cp <= 0xFE0F) return true;
    // Combining enclosing keycap
    if (cp == 0x20E3) return true;
    // Tags block (subdivision flags)
    if (cp >= 0xE0000 and cp <= 0xE007F) return true;

    return false;
}

fn isHiddenChar(cp: u21) bool {
    return switch (cp) {
        0x200B, // Zero-width space
        0x200C, // Zero-width non-joiner
        0x200D, // Zero-width joiner
        0x2060, // Word joiner
        0x00AD, // Soft hyphen
        0xFEFF, // BOM
        0xFFFC, // Object replacement character
        => true,
        else => false,
    };
}

fn isDirectionalChar(cp: u21) bool {
    // LRM, RLM
    if (cp == 0x200E or cp == 0x200F) return true;
    // LRE, RLE, PDF, LRO, RLO
    if (cp >= 0x202A and cp <= 0x202E) return true;
    // LRI, RLI, FSI, PDI
    if (cp >= 0x2066 and cp <= 0x2069) return true;
    return false;
}

fn isControlChar(cp: u21) bool {
    // C0 controls except TAB (0x09) and LF (0x0A)
    if (cp <= 0x001F and cp != 0x0009 and cp != 0x000A) return true;
    // DEL
    if (cp == 0x007F) return true;
    // C1 controls
    if (cp >= 0x0080 and cp <= 0x009F) return true;
    return false;
}

// -- Tests --
test "cleanMessage: plain ASCII passes through" {
    const allocator = std.testing.allocator;
    const result = try cleanMessage(allocator, "Hello World");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello World", result);
}

test "cleanMessage: converts Arabic-Indic digits" {
    const allocator = std.testing.allocator;
    // ١٢٣٤ = 1234
    const result = try cleanMessage(allocator, "\xD9\xA1\xD9\xA2\xD9\xA3\xD9\xA4");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("1234", result);
}

test "cleanMessage: converts Extended Arabic-Indic digits" {
    const allocator = std.testing.allocator;
    // ۱۲۳ = 123
    const result = try cleanMessage(allocator, "\xDB\xB1\xDB\xB2\xDB\xB3");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("123", result);
}

test "cleanMessage: strips emojis" {
    const allocator = std.testing.allocator;
    // 😀 = F0 9F 98 80
    const result = try cleanMessage(allocator, "Hello \xF0\x9F\x98\x80 World");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello  World", result);
}

test "cleanMessage: strips multiple emojis" {
    const allocator = std.testing.allocator;
    // 🎉 = F0 9F 8E 89, 🚀 = F0 9F 9A 80
    const result = try cleanMessage(allocator, "\xF0\x9F\x8E\x89 Party \xF0\x9F\x9A\x80");
    defer allocator.free(result);
    try std.testing.expectEqualStrings(" Party ", result);
}

test "cleanMessage: strips HTML tags" {
    const allocator = std.testing.allocator;
    const result = try cleanMessage(allocator, "<b>Hello</b> <i>World</i>");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello World", result);
}

test "cleanMessage: strips zero-width space" {
    const allocator = std.testing.allocator;
    // U+200B = E2 80 8B
    const result = try cleanMessage(allocator, "Hello\xE2\x80\x8BWorld");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("HelloWorld", result);
}

test "cleanMessage: strips BOM" {
    const allocator = std.testing.allocator;
    // U+FEFF = EF BB BF
    const result = try cleanMessage(allocator, "\xEF\xBB\xBFHello");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello", result);
}

test "cleanMessage: strips soft hyphen" {
    const allocator = std.testing.allocator;
    // U+00AD = C2 AD
    const result = try cleanMessage(allocator, "soft\xC2\xADhyphen");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("softhyphen", result);
}

test "cleanMessage: preserves Arabic text" {
    const allocator = std.testing.allocator;
    // مرحبا = D9 85 D8 B1 D8 AD D8 A8 D8 A7
    const result = try cleanMessage(allocator, "\xD9\x85\xD8\xB1\xD8\xAD\xD8\xA8\xD8\xA7");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("\xD9\x85\xD8\xB1\xD8\xAD\xD8\xA8\xD8\xA7", result);
}

test "cleanMessage: preserves newlines" {
    const allocator = std.testing.allocator;
    const result = try cleanMessage(allocator, "Line 1\nLine 2");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Line 1\nLine 2", result);
}

test "cleanMessage: preserves tabs" {
    const allocator = std.testing.allocator;
    const result = try cleanMessage(allocator, "Col1\tCol2");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Col1\tCol2", result);
}

test "cleanMessage: strips C0 control chars" {
    const allocator = std.testing.allocator;
    const result = try cleanMessage(allocator, "Hello\x01\x02World");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("HelloWorld", result);
}

test "cleanMessage: strips directional marks" {
    const allocator = std.testing.allocator;
    // U+200E LRM = E2 80 8E, U+200F RLM = E2 80 8F
    const result = try cleanMessage(allocator, "Hello\xE2\x80\x8E\xE2\x80\x8FWorld");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("HelloWorld", result);
}

test "cleanMessage: emoji-only message returns empty" {
    const allocator = std.testing.allocator;
    const result = try cleanMessage(allocator, "\xF0\x9F\x98\x80\xF0\x9F\x98\x82");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}

test "cleanMessage: strips variation selectors" {
    const allocator = std.testing.allocator;
    // U+FE0F = EF B8 8F (emoji presentation selector)
    const result = try cleanMessage(allocator, "Star\xEF\xB8\x8Fhere");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Starhere", result);
}
