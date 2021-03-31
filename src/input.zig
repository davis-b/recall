const std = @import("std");
const meta = std.meta;
const print = std.debug.print;
const Needle = @import("needle.zig").Needle;

pub fn parseStringForType(string: []const u8) !Needle {
    if (string.len == 0) return error.EmptyStringProvided;

    const Subtype = enum {
        uint,
        int,
        float,
        string,
    };

    const head = string[0];
    const subtype = switch (head) {
        's' => Subtype.string,
        'i' => Subtype.int,
        'u' => Subtype.uint,
        'f' => Subtype.float,
        else => return error.InvalidTypeHint,
    };

    switch (subtype) {
        .string => return Needle{ .string = undefined },
        .int, .uint, .float => {
            if (string.len == 1) return error.NoBitAmountProvided;
            const bits = std.fmt.parseInt(u8, string[1..], 10) catch return error.InvalidBitNumber;

            return switch (subtype) {
                .string => unreachable,
                .int => switch (bits) {
                    8 => Needle{ .i8 = undefined },
                    16 => Needle{ .i16 = undefined },
                    32 => Needle{ .i32 = undefined },
                    64 => Needle{ .i64 = undefined },
                    128 => Needle{ .i128 = undefined },
                    else => error.InvalidBitCountForInt,
                },
                .uint => switch (bits) {
                    8 => Needle{ .u8 = undefined },
                    16 => Needle{ .u16 = undefined },
                    32 => Needle{ .u32 = undefined },
                    64 => Needle{ .u64 = undefined },
                    128 => Needle{ .u128 = undefined },
                    else => error.InvalidBitCountForUInt,
                },
                .float => switch (bits) {
                    16 => Needle{ .f16 = undefined },
                    32 => Needle{ .f32 = undefined },
                    64 => Needle{ .f64 = undefined },
                    128 => Needle{ .f128 = undefined },
                    else => error.InvalidBitCountForFloat,
                },
            };
        },
    }
}

pub fn askUserForType() Needle {
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
pub fn askUserForValue(NT: NeedleType) ![]const u8 {
    print("Please enter value for {} > ", .{std.meta.tagName(NT)});
    const input = getStdin();
    var buffer = user_value_buffer[0..];
    if (input) |string| {
        switch (NT) {
            .string => {
                return string;
            },
            else => {
                const tn = std.meta.tagName(NT);
                const ti = @typeInfo(NeedleType).Union;
                inline for (ti.fields) |f| {
                    if (std.mem.eql(u8, f.name, tn)) {
                        try readStringAs(f.field_type, string, buffer[0..]);
                        return buffer[0..@sizeOf(f.field_type)];
                    }
                }
                @panic("Highly unexpected situation. Our NeedleType union could not find a matching name on an active tag of itself.\n");
            },
        }
    } else {
        return error.NoInputGiven;
    }
}

// TODO instead of using a buffer, we can now store the result in our NeedleType, thus allowing us to return the bytes directly. (Pass NT pointers for the memory to be consistent)

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
        // Would prefer to have the 'Void' case handled by our 'else' clause.
        // However, it gives compile errors in zig 0.7.1.
        .Void => unreachable,
        else => @compileError("Function called with invalid type " ++ @typeName(T)),
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
