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
};
