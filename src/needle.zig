const std = @import("std");

pub const Needle = union(enum) {
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

    /// Returns the size of the active field.
    pub fn size(self: *const Needle) usize {
        const tn = @tagName(self.*);
        inline for (@typeInfo(Needle).Union.fields) |f| {
            if (std.mem.eql(u8, f.name, tn)) {
                return @sizeOf(f.field_type);
            }
        }
        unreachable;
    }
};

// We would prefer to infer the return type from the function type. However, the only return type we are getting from @typeInfo is null while the function is generic.
/// Calls a function with the given arguments prepended by the type of the given union value.
/// Returns the value given by the function.
pub fn call_fn_with_union_type(union_item: anytype, comptime return_type: type, comptime func: anytype, args: anytype) return_type {
    const tn = std.meta.tagName(union_item);
    const ti = @typeInfo(@TypeOf(union_item));
    switch (ti) {
        .Union => |u| {
            inline for (u.fields) |f| {
                if (std.mem.eql(u8, f.name, tn)) {
                    return @call(.{ .modifier = .auto, .stack = null }, func, .{f.field_type} ++ args);
                }
            }
            unreachable;
        },
        else => @compileError("Invalid type \"" ++ @typeName(@TypeOf(union_item)) ++ "\" called with this function."),
    }
}
