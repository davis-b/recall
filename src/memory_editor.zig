const std = @import("std");
const os = std.os;
const warn = std.debug.warn;

const c = @import("c.zig");

pub fn main() anyerror!void {
    if (os.argv.len < 3) {
        warn("user must supply pid and address\n", .{});
        warn("Optionally, a value may be supplied to increment the deferenced address by\n", .{});
        os.exit(2);
    }
    const pid = std.fmt.parseInt(os.pid_t, std.mem.span(os.argv[1]), 10) catch os.exit(2);
    const addr = std.fmt.parseInt(usize, std.mem.span(os.argv[2]), 10) catch os.exit(2);

    const T = i32;
    var amount: ?T = null;
    if (os.argv.len == 4) {
        amount = std.fmt.parseInt(T, std.mem.span(os.argv[3]), 10) catch os.exit(2);
    }

    warn("T {}\n", .{@typeName(T)});
    var buffer: [@bitSizeOf(T) / 8]u8 = undefined;
    const read_amount = try c.readv(pid, buffer[0..], addr);
    warn("buffer: {x}\n", .{buffer});
    var result = @bitCast(T, buffer);
    // const result = @ptrCast(*T, &buffer[0..read_amount]).*;
    warn("result: {}\n", .{result});

    if (amount) |amt| {
        result += amt;
        buffer = std.mem.asBytes(@alignCast(1, &result)).*;
        const written = try c.writev(pid, buffer[0..], addr);
        warn("wrote {} bytes\n", .{written});
    }
}
