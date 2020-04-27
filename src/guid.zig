const builtin = @import("builtin");
const mem = @import("std").mem;
const assert = @import("std").debug.assert;
const crypto = @import("std").crypto;
const testing = @import("std").testing;

pub const Format = enum {
    Bare,
    Dashed,
    Braced,
};
pub const Case = enum {
    Lower,
    Upper,
};

const GUIDBuilder = struct {
    bytes: [16]u8,
    first_nibble: ?u8 = null,
    pointer: usize = 0,

    const Self = @This();

    pub inline fn init() Self {
        return Self{ .bytes = undefined };
    }

    inline fn pushNibble(self: *Self, nib: u8) void {
        assert(self.pointer < 16);
        assert(nib <= 0xF);
        if (self.first_nibble) |val| {
            self.bytes[self.pointer] = val * 16 + nib;
            self.pointer += 1;
            self.first_nibble = null;
        } else {
            self.first_nibble = nib;
        }
    }

    pub inline fn build(self: *const Self) GUID {
        assert(self.pointer == 16);
        return GUID.fromBytes(self.bytes);
    }

    inline fn parseUnbraced(comptime format: Format, string: []const u8) !GUID {
        var builder = GUIDBuilder.init();
        for (string) |c, i| {
            switch (c) {
                'A'...'F' => builder.pushNibble(c - 'A' + 10),
                'a'...'f' => builder.pushNibble(c - 'a' + 10),
                '0'...'9' => builder.pushNibble(c - '0'),
                '-' => {
                    if (format == .Bare) {
                        return error.UnexpectedDash;
                    }
                    if (i != 8 and i != 13 and i != 18 and i != 23) {
                        return error.UnexpectedDash;
                    }
                },
                else => return error.UnexpectedCharacter,
            }
        }
        return builder.build();
    }
};

fn StringBuilder(comptime format: Format, comptime case: Case) type {
    const len = switch (format) {
        .Bare => 32,
        .Dashed => 36,
        .Braced => 38,
    };
    return struct {
        string: []u8,
        pointer: usize = 0,

        const Self = @This();

        pub fn init(buffer: []u8) !Self {
            if (buffer.len < len) {
                return error.BufferTooSmall;
            }
            var self = Self{ .string = buffer };
            if (format == .Braced) {
                self.string[0] = '{';
                self.pointer += 1;
            }
            return self;
        }

        fn pushNibble(self: *Self, nib: u8) void {
            const char = switch (nib) {
                0...9 => '0' + nib,
                0xA...0xF => if (case == Case.Lower) 'a' + nib - 10 else 'A' + nib - 10,
                else => unreachable,
            };
            self.string[self.pointer] = char;
            self.pointer += 1;
        }

        pub fn pushByte(self: *Self, byte: u8) void {
            self.pushNibble((byte & 0xF0) >> 4);
            self.pushNibble(byte & 0x0F);
            const char: ?u8 = if (format == .Braced) switch (self.pointer) {
                9, 14, 19, 24 => @as(u8, '-'),
                len - 1 => @as(u8, '}'),
                else => null,
            } else if (format == .Dashed) switch (self.pointer) {
                8, 13, 18, 23 => @as(u8, '-'),
                else => null,
            } else null;
            if (char) |c| {
                self.string[self.pointer] = c;
                self.pointer += 1;
            }
        }

        pub fn build(self: *const Self) []u8 {
            assert(self.pointer == len);
            return self.string;
        }
    };
}

/// A winapi-compatible GUID.
pub const GUID = packed struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,

    const Self = @This();

    /// Does this GUID equal the other GUID?
    pub inline fn eq(self: *const Self, other: *const Self) bool {
        return mem.eql(u8, @ptrCast(*const [16]u8, self), @ptrCast(*const [16]u8, other));
    }

    /// Initialize a null GUID (all zeroes).
    pub fn nil() Self {
        return Self.from("00000000-0000-0000-0000-000000000000");
    }

    pub fn v4() !Self {
        var bytes: [16]u8 = undefined;
        try crypto.randomBytes(bytes[0..]);
        return Self.fromBytes(bytes);
    }

    /// Initialize a GUID from a byte array.
    pub fn fromBytes(bytes: [16]u8) Self {
        return @bitCast(Self, bytes);
    }

    /// Get the GUID data as a byte array.
    pub fn asBytes(self: *const Self) *const [16]u8 {
        return @ptrCast(*const [16]u8, self);
    }

    /// Parse a GUID string at runtime.
    /// It can be any of the three forms:
    /// - Bare: 12345678ABCDEFEF90901234567890AB
    /// - Dashed: 12345678-ABCD-EFEF-9090-1234567890AB
    /// - Braced: {12345678-ABCD-EFEF-9090-1234567890AB}
    pub fn parse(string: []const u8) !Self {
        if (string.len == 38) return Self.parseBraced(string);
        if (string.len == 36) return Self.parseDashed(string);
        if (string.len == 32) return Self.parseBare(string);
        return error.UnsupportedFormat;
    }

    /// Parse a braced GUID, of the form: "{12345678-ABCD-EFEF-9090-1234567890AB}"
    pub fn parseBraced(string: []const u8) !Self {
        if (string.len != 38) return error.IncorrectLength;
        return Self.parseDashed(string[1..37]);
    }

    /// Parse a dashed GUID, of the form: "12345678-ABCD-EFEF-9090-1234567890AB"
    pub fn parseDashed(string: []const u8) !Self {
        if (string.len != 36) return error.IncorrectLength;
        return GUIDBuilder.parseUnbraced(.Dashed, string);
    }

    /// Parse a bare GUID, of the form: "12345678ABCDEFEF90901234567890AB"
    pub fn parseBare(string: []const u8) !Self {
        if (string.len != 32) return error.IncorrectLength;
        return GUIDBuilder.parseUnbraced(.Bare, string);
    }

    /// Create a GUID at compile time.
    /// It can be any of the three forms:
    /// - Bare: 12345678ABCDEFEF90901234567890AB
    /// - Dashed: 12345678-ABCD-EFEF-9090-1234567890AB
    /// - Braced: {12345678-ABCD-EFEF-9090-1234567890AB}
    pub fn from(comptime string: []const u8) Self {
        comptime var actual_string = string;
        if (string.len == 38) {
            actual_string = string[1..37];
        }
        const format = if (actual_string.len == 36) .Dashed else .Bare;
        if (format == .Bare) {
            assert(actual_string.len == 32);
        }

        return GUIDBuilder.parseUnbraced(format, actual_string) catch unreachable;
    }

    pub fn toString(self: *const Self, buffer: []u8, comptime format: Format, comptime case: Case) ![]u8 {
        var builder = try StringBuilder(format, case).init(buffer);
        for (self.asBytes()) |byte| {
            builder.pushByte(byte);
        }
        return builder.build();
    }
};

test "nil equals nil" {
    testing.expect(GUID.nil().eq(&GUID.nil()));
}

test "compile time and runtime parsing" {
    testing.expect(GUID.from("12345678-ABCD-EFEF-9090-1234567890AB").eq(&try GUID.parse("12345678-ABCD-EFEF-9090-1234567890AB")));
    testing.expect(GUID.from("12345678-ABCD-EFEF-9090-1234567890AB").eq(&try GUID.parse("{12345678-ABCD-EFEF-9090-1234567890AB}")));
    testing.expect(GUID.from("{12345678-ABCD-EFEF-9090-1234567890AB}").eq(&try GUID.parse("12345678ABCDEFEF90901234567890AB")));
    testing.expect(GUID.from("12345678ABCDEFEF90901234567890AB").eq(&try GUID.parse("12345678-ABCD-EFEF-9090-1234567890AB")));
}

test "to string" {
    var buffer = [_]u8{0} ** 38;
    const guid = GUID.from("12345678-ABCD-EFEF-9090-1234567890AB");
    var str = try guid.toString(buffer[0..], .Dashed, .Upper);
    testing.expectEqualSlices(u8, "12345678-ABCD-EFEF-9090-1234567890AB", str[0..36]);
    str = try guid.toString(buffer[0..], .Braced, .Lower);
    testing.expectEqualSlices(u8, "{12345678-abcd-efef-9090-1234567890ab}", str);
}

test "parse error" {
    testing.expectError(error.UnexpectedCharacter, GUID.parse("nothexad-ABCD-EFEF-9090-1234567890AB"));
    testing.expectError(error.UnexpectedDash, GUID.parse("1234-678-ABCD-EFEF-9090-1234567890AB"));
}
