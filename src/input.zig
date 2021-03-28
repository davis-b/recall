const std = @import("std");
const meta = std.meta;
const print = std.debug.print;

pub const NeedleType = union(enum) {
    i8: i8,
    i16: i16,
    i32: i32,
    i64: i64,
    i128: i128,

    u8: u8,
    u16: u16,
    u32: u32,
    u64: u64,
    u128: u128,

    f16: f16,
    f32: f32,
    f64: f64,
    f128: f128,

    string: void,
};

pub fn parseStringForType(string: []const u8) !NeedleType {
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
        .string => return NeedleType{ .string = undefined },
        .int, .uint, .float => {
            if (string.len == 1) return error.NoBitAmountProvided;
            const bits = std.fmt.parseInt(u8, string[1..], 10) catch return error.InvalidBitNumber;

            return switch (subtype) {
                .string => unreachable,
                .int => switch (bits) {
                    8 => NeedleType{ .i8 = undefined },
                    16 => NeedleType{ .i16 = undefined },
                    32 => NeedleType{ .i32 = undefined },
                    64 => NeedleType{ .i64 = undefined },
                    128 => NeedleType{ .i128 = undefined },
                    else => error.InvalidBitCountForInt,
                },
                .uint => switch (bits) {
                    8 => NeedleType{ .u8 = undefined },
                    16 => NeedleType{ .u16 = undefined },
                    32 => NeedleType{ .u32 = undefined },
                    64 => NeedleType{ .u64 = undefined },
                    128 => NeedleType{ .u128 = undefined },
                    else => error.InvalidBitCountForUInt,
                },
                .float => switch (bits) {
                    16 => NeedleType{ .f16 = undefined },
                    32 => NeedleType{ .f32 = undefined },
                    64 => NeedleType{ .f64 = undefined },
                    128 => NeedleType{ .f128 = undefined },
                    else => error.InvalidBitCountForFloat,
                },
            };
        },
    }
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
