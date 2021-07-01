const std = @import("std");
const os = std.os;
const warn = std.debug.warn;
const print = std.debug.print;

const c = @import("c.zig");
const input = @import("input.zig");
const Needle = @import("needle.zig").Needle;

pub fn main() anyerror!u8 {
    if (os.argv.len < 5) {
        warn("User must supply [pid, (type + bit length), address, and a value to set the address to]\n", .{});
        return 2;
    }
    const pid = std.fmt.parseInt(os.pid_t, std.mem.span(os.argv[1]), 10) catch |err| {
        warn("Failed parsing PID \"{s}\". {}\n", .{ os.argv[1], err });
        return 2;
    };

    var needle = input.parseStringForType(std.mem.span(os.argv[2])) catch |err| {
        warn("Failed parsing type \"{s}\". {}\n", .{ os.argv[2], err });
        return 2;
    };

    const addr = std.fmt.parseInt(usize, std.mem.span(os.argv[3]), 10) catch |err| {
        warn("Failed parsing address \"{s}\". {}\n", .{ os.argv[3], err });
        return 2;
    };

    const new_value = std.mem.span(os.argv[4]);

    switch (needle) {
        .string => {
            const written = try c.writev(pid, new_value, addr);
            warn("wrote {} bytes\n", .{written});
        },
        else => {
            const needle_bytes = input.stringToType(new_value, &needle) catch |err| {
                warn("Failed obtaining a value to set address {x} to. {}\n", .{ addr, err });
                return 2;
            };

            const written = try c.writev(pid, needle_bytes, addr);
            warn("wrote {} bytes\n", .{written});
        },
    }

    return 0;
}
