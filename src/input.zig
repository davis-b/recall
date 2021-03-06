const std = @import("std");
const meta = std.meta;
const print = std.debug.print;
const Needle = @import("needle.zig").Needle;
const call_fn_with_union_type = @import("needle.zig").call_fn_with_union_type;
const testing = std.testing;

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
pub fn askUserForValue(needle: *Needle) ![]u8 {
    print("Please enter value for {s} ", .{std.meta.tagName(needle.*)});
    call_fn_with_union_type(needle.*, void, printMinMax, .{});
    print("> ", .{});
    const maybe_input = getStdin();
    var buffer = user_value_buffer[0..];
    if (maybe_input) |input| {
        switch (needle.*) {
            .string => {
                return input;
            },
            else => {
                return try stringToType(input, needle);
            },
        }
    } else {
        return error.NoInputGiven;
    }
}

/// Prints the minimum and maximum value a type can be.
fn printMinMax(comptime T: type) void {
    switch (@typeInfo(T)) {
        .Int => {
            const min = std.math.minInt(T);
            const max = std.math.maxInt(T);
            print("between {} and {} ", .{ min, max });
        },
        .Float => {
            const min_max = switch (T) {
                f16 => .{ std.math.f16_min, std.math.f16_max },
                f32 => .{ std.math.f32_min, std.math.f32_max },
                f64 => .{ std.math.f64_min, std.math.f64_max },
                f128 => .{ std.math.f128_min, std.math.f128_max },
                else => unreachable,
            };
            print("{} and {}", .{ min_max[0], min_max[1] });
        },
        else => {},
    }
}

/// Reads string as a specified type.
/// Sets the needle's value to that result.
/// Reinterprets result as bytes, which then get returned.
/// Returned bytes are simply another representation of the needle data.
/// Therefore, they will change as the needle does, and they do not need to be free'd.
pub fn stringToType(string: []const u8, needle: *Needle) std.fmt.ParseIntError![]u8 {
    return try call_fn_with_union_type(needle.*, std.fmt.ParseIntError![]u8, stringToType_internal, .{ string, needle });
}

/// Internal implementation of stringToType.
/// Must be split into separate function because we are calling it with a comptime type derived from a given union type.
fn stringToType_internal(comptime T: type, string: []const u8, needle: *Needle) std.fmt.ParseIntError![]u8 {
    const tn = @tagName(needle.*);
    const result = switch (@typeInfo(T)) {
        .Int => |i| try std.fmt.parseInt(T, string, 10),
        .Float => |f| try std.fmt.parseFloat(T, string),
        // Would prefer to have the 'Void' case handled by our 'else' clause.
        // However, it gives compile errors in zig 0.7.1.
        .Void => unreachable,
        else => @compileError("Function called with invalid type " ++ @typeName(T)),
    };

    inline for (@typeInfo(Needle).Union.fields) |field| {
        if (field.field_type == T) {
            needle.* = @unionInit(Needle, field.name, result);
            return std.mem.asBytes(&@field(needle, field.name));
        }
    }
    @compileError(@typeName(T) ++ " is not a member of the given union " ++ @typeName(@TypeOf(needle.*)));
}

test "string to type" {
    var needle = Needle{ .u8 = 0 };
    // Invalid strings.
    try testing.expectError(error.Overflow, stringToType("-100", &needle));
    try testing.expectError(error.Overflow, stringToType("256", &needle));
    try testing.expectError(error.InvalidCharacter, stringToType("100 ", &needle));
    // Valid string.
    var byte_repr = try stringToType("255", &needle);
    try testing.expect(std.mem.eql(u8, byte_repr, &[_]u8{0xff}));
    // Prove function changes needle value.
    try testing.expectEqual(needle.u8, 255);

    // stringToType returns an array backed by the needle itself.
    needle = Needle{ .i16 = 0 };
    byte_repr = try stringToType("-1000", &needle);
    // Sanity check.
    var input_needle_value: i16 = -1000;
    try testing.expectEqual(needle.i16, input_needle_value);
    var expected_bytes = std.mem.asBytes(&input_needle_value);
    // Establish expected byte representation.
    try testing.expect(std.mem.eql(u8, byte_repr, expected_bytes));
    // Prove byte_repr is backed by needle, even as needle changes.
    needle.i16 += 1;
    try testing.expectEqual(needle.i16, -999);
    // We have modified needle only, yet byte_repr will change as well.
    try testing.expect(!std.mem.eql(u8, byte_repr, expected_bytes));
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
