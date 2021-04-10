const std = @import("std");
const os = std.os;
const warn = std.debug.warn;
const print = std.debug.print;

const c = @import("c.zig");
const input = @import("input.zig");
const Needle = @import("needle.zig").Needle;
const call_fn_with_union_type = @import("needle.zig").call_fn_with_union_type;

pub fn main() anyerror!u8 {
    if (os.argv.len < 5) {
        warn("User must supply [pid, (type + bit length), address, and a value to set the address to]\n", .{});
        return 2;
    }
    const pid = std.fmt.parseInt(os.pid_t, std.mem.span(os.argv[1]), 10) catch |err| {
        warn("Failed parsing PID \"{}\". {}\n", .{ os.argv[1], err });
        return 2;
    };

    var needle = input.parseStringForType(std.mem.span(os.argv[2])) catch |err| {
        warn("Failed parsing type \"{}\". {}\n", .{ os.argv[2], err });
        return 2;
    };

    const addr = std.fmt.parseInt(usize, std.mem.span(os.argv[3]), 10) catch |err| {
        warn("Failed parsing address \"{}\". {}\n", .{ os.argv[3], err });
        return 2;
    };

    const needle_value_str = std.mem.span(os.argv[4]);
    const needle_bytes = call_fn_with_union_type(needle, std.fmt.ParseIntError![]u8, input.stringToType, .{ needle_value_str, &needle }) catch |err| {
        warn("Failed obtaining a value to set address {x} to. {}\n", .{ addr, err });
        return 2;
    };

    const written = try c.writev(pid, needle_bytes, addr);
    warn("wrote {} bytes\n", .{written});

    return 0;
}
