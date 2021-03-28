const std = @import("std");
const meta = std.meta;
const print = std.debug.print;

pub const NeedleType = struct {
    bytes: u16,
    T: union(enum) {
        // Bool represents whether or not the int is signed.
        int: bool,
        float: bool,
        string: void,
    },
};

pub fn parseStringForType(string: []const u8) !NeedleType {
    if (string.len == 0) return error.EmptyStringProvided;

    var result = NeedleType{
        .bytes = 0,
        .T = undefined,
    };

    const head = string[0];
    switch (head) {
        's' => result.T = .{ .string = undefined },
        'u' => result.T = .{ .int = false },
        'i' => result.T = .{ .int = true },
        'f' => result.T = .{ .float = true },
        else => return error.InvalidTypeHint,
    }

    switch (result.T) {
        .string => {},
        .int, .float => {
            if (string.len == 1) return error.NoBitAmountProvided;
            const bits = std.fmt.parseInt(u16, string[1..], 10) catch return error.InvalidBitNumber;
            if (result.T == .int) {
                switch (bits) {
                    8, 16, 32, 64, 128 => {},
                    else => return error.InvalidBitCountForInt,
                }
                // if (bits > @typeInfo(usize).Int.bits) return error.RequestsTooManyBits;
            } else {
                switch (bits) {
                    16, 32, 64, 128 => {},
                    else => return error.InvalidBitCountForFloat,
                }
            }
            result.bytes = bits / 8;
        },
    }
    return result;
}

pub fn askUserForType() NeedleType {
    if (getStdin()) |string| {
        return parseStringForType(string) catch return askUserForType();
    } else {
        print("try again\n", .{});
        return askUserForType();
    }
}

var user_value_buffer = [_]u8{0} ** 128;

/// Asks user for input, expecting it to conform to a specific type.
/// However, this is a type chosen at runtime instead of comptime.
/// Thus, we have to go about this in a roundabout fashion.
/// Eventually, we return the bytes representing the input value for the requested type.
/// The bytes returned are global to this module and are not owned by the caller.
pub fn askUserForValue(T: NeedleType) ![]const u8 {
    print("Please enter value for {} of {} bytes > ", .{ std.meta.tagName(T.T), T.bytes });
    const input = getStdin();
    var buffer = user_value_buffer[0..];
    if (input) |string| {
        switch (T.T) {
            .int => |signed| {
                if (signed) {
                    switch (T.bytes) {
                        1 => try readStringAs(i8, string, buffer[0..]),
                        2 => try readStringAs(i16, string, buffer[0..]),
                        4 => try readStringAs(i32, string, buffer[0..]),
                        8 => try readStringAs(i64, string, buffer[0..]),
                        16 => try readStringAs(i128, string, buffer[0..]),
                        else => @panic("Invalid signed int bit amount\n"),
                    }
                } else {
                    switch (T.bytes) {
                        1 => try readStringAs(u8, string, buffer[0..]),
                        2 => try readStringAs(u16, string, buffer[0..]),
                        4 => try readStringAs(u32, string, buffer[0..]),
                        8 => try readStringAs(u64, string, buffer[0..]),
                        16 => try readStringAs(u128, string, buffer[0..]),
                        else => @panic("Invalid unsigned int bit amount\n"),
                    }
                }
                return buffer[0..T.bytes];
            },
            .float => {
                switch (T.bytes) {
                    2 => try readStringAs(f16, string, buffer[0..]),
                    4 => try readStringAs(f32, string, buffer[0..]),
                    8 => try readStringAs(f64, string, buffer[0..]),
                    16 => try readStringAs(f128, string, buffer[0..]),
                    else => @panic("Invalid float bit amount\n"),
                }
                return buffer[0..T.bytes];
            },
            .string => {
                return string;
            },
        }
    } else {
        return error.NoInputGiven;
    }
}

/// Reads string as a specified type.
/// Interprets result as bytes, which then
///  get moved into user_value_buffer.
fn readStringAs(comptime T: type, string: []const u8, buffer: []u8) !void {
    switch (@typeInfo(T)) {
        .Int => |i| {
            const result = try std.fmt.parseInt(T, string, 10);
            const bytes = std.mem.asBytes(&result);
            for (bytes) |b, index| buffer[index] = b;
        },
        .Float => |f| {
            const result = try std.fmt.parseFloat(T, string);
            const bytes = std.mem.asBytes(&result);
            for (bytes) |b, index| buffer[index] = b;
        },
        else => @compileError("Function called with invalid type"),
    }
}

var stdin_buffer = [_]u8{0} ** 100;
pub fn getStdin() ?[]u8 {
    const stdin = std.io.getStdIn();
    var read_bytes = stdin.read(stdin_buffer[0..]) catch return null;
    if (read_bytes == 0) return null;
    if (stdin_buffer[0] == 0 or stdin_buffer[0] == '\n') return null;
    if (stdin_buffer[read_bytes - 1] == '\n') read_bytes -= 1;
    return stdin_buffer[0..read_bytes];
}
