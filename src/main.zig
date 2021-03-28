const std = @import("std");
const os = std.os;
const warn = std.debug.warn;
const print = std.debug.print;

const readv = @import("c.zig").readv;
const memory = @import("memory.zig");
const readMemMap = @import("read_map.zig").readMemMap;
const input = @import("input.zig");

fn help() void {
    warn("User must supply pid and (type hint + bit length)\n", .{});
    warn("Available type hints are: [i, u, f, s]\n", .{});
    warn("i: signed integer\n", .{});
    warn("u: unsigned integer\n", .{});
    warn("f: float - Only available with bit lengths [16, 32, 64] \n", .{});
    warn("s: string - Does not require a bit length\n", .{});
    warn("Example Usage: {} 5005 u32\n", .{os.argv[0]});
}

pub fn main() anyerror!void {
    if (os.argv.len < 3) {
        help();
        os.exit(2);
    }

    const pid = std.fmt.parseInt(os.pid_t, std.mem.span(os.argv[1]), 10) catch |err| {
        warn("Failed parsing PID \"{}\". {}\n", .{ os.argv[1], err });
        os.exit(2);
    };
    const needle_typeinfo = input.parseStringForType(std.mem.span(os.argv[2])) catch |err| {
        warn("Failed parsing search type \"{}\". {}\n", .{ os.argv[2], err });
        os.exit(2);
    };

    const allocator = std.heap.page_allocator; // Perhaps we should link with libc to use malloc

    const st = std.time.milliTimestamp();
    var memory_segments = readMemMap(allocator, pid) catch |err| {
        switch (err) {
            error.FileNotFound => {
                warn("Process matching pid {} not found.\n", .{pid});
                os.exit(1);
            },
            else => return err,
        }
    };
    defer memory_segments.deinit();
    defer for (memory_segments.items) |*i| if (i.name) |n| allocator.free(n);

    const process_name = find_process_name(allocator, pid) catch null;
    defer if (process_name) |pn| allocator.free(pn);

    if (memory_segments.items.len == 0) {
        print("No memory segments found for \"{}\", pid {}. Exiting\n", .{ process_name, pid });
        return;
    }
    var total_memory: usize = 0;
    for (memory_segments.items) |i, n| {
        total_memory += i.len;
    }
    print("{} is using {} memory segments for a total of ", .{ process_name, memory_segments.items.len });
    printHumanReadableByteCount(total_memory);
    print("\n", .{});

    const needle: []const u8 = try input.askUserForValue(needle_typeinfo);

    const initial_scan_start = std.time.milliTimestamp();
    var potential_addresses = (try memory.parseSegments(allocator, pid, &memory_segments, needle)) orelse {
        print("No matches!\n", .{});
        return;
    };
    defer potential_addresses.deinit();
    print("Initial scan took {} ms\n", .{std.time.milliTimestamp() - initial_scan_start});

    while (potential_addresses.items.len > 1) {
        print("Potential addresses: {}\n", .{potential_addresses.items.len});
        if (potential_addresses.items.len < 5) {
            for (potential_addresses.items) |pa| warn("pa: {} \n", .{pa});
        }
        const new_needle: []const u8 = try input.askUserForValue(needle_typeinfo);
        try memory.pruneAddresses(pid, new_needle, &potential_addresses);
    }
    if (potential_addresses.items.len == 1) {
        const final_address = potential_addresses.items[0];
        print("Match found at: {}\n", .{final_address});
        var buffer = [_]u8{0} ** 400;
        while (true) {
            if (needle_typeinfo.T == .string) {
                print("Please enter the number of characters you would like to read\n", .{});
            } else {
                print("Enter any character to print value at needle address, or nothing to exit\n", .{});
            }
            const user_input = input.getStdin() orelse break;

            var str_len: usize = 0;
            if (needle_typeinfo.T == .string) {
                const peek_length = std.fmt.parseInt(usize, user_input, 10) catch {
                    continue;
                };
                str_len = try memory.readRemote(buffer[0..peek_length], pid, final_address);
            } else {
                var needle_bytes = [_]u8{0} ** input.NeedleType.max_bytes;
                _ = try memory.readRemote(needle_bytes[0..needle_typeinfo.bytes], pid, final_address);
                str_len = try bytesToString(needle_typeinfo, needle_bytes[0..needle_typeinfo.bytes], buffer[0..]);
            }
            print("value is: {}\n", .{buffer[0..str_len]});
        }
    } else {
        print("No matches remain!\n", .{});
    }
}

/// Reads the given bytes as a type appropriate for the given NeedleType.
/// Prints that value to the buffer as a string.
/// Returns the number of characters written to buffer.
fn bytesToString(NT: input.NeedleType, bytes: []u8, buffer: []u8) !usize {
    switch (NT.T) {
        .string => unreachable,
        .int => |signed| {
            if (signed) {
                return try switch (NT.bytes) {
                    1 => printToBufferAs(i8, bytes, buffer),
                    2 => printToBufferAs(i16, bytes, buffer),
                    4 => printToBufferAs(i32, bytes, buffer),
                    8 => printToBufferAs(i64, bytes, buffer),
                    16 => printToBufferAs(i128, bytes, buffer),
                    else => unreachable,
                };
            } else {
                return try switch (NT.bytes) {
                    1 => printToBufferAs(u8, bytes, buffer),
                    2 => printToBufferAs(u16, bytes, buffer),
                    4 => printToBufferAs(u32, bytes, buffer),
                    8 => printToBufferAs(u64, bytes, buffer),
                    16 => printToBufferAs(u128, bytes, buffer),
                    else => unreachable,
                };
            }
        },
        .float => {
            return try switch (NT.bytes) {
                2 => printToBufferAs(f16, bytes, buffer),
                4 => printToBufferAs(f32, bytes, buffer),
                8 => printToBufferAs(f64, bytes, buffer),
                16 => printToBufferAs(f128, bytes, buffer),
                else => unreachable,
            };
        },
    }
}

/// Takes a type, bytes that will turn into that type, and a buffer to print to.
/// Transforms those bytes into that type, and then prints that type to the out buffer.
fn printToBufferAs(comptime T: type, bytes: []u8, out: []u8) !usize {
    const result = @ptrCast(*align(1) T, bytes[0..]).*;
    return (try std.fmt.bufPrint(out, "{}", .{result})).len;
}

// Zig std lib provides a built-in alternative, "{B:.2}".
// However, I am unhappy with its output, thus we have this.
// For reference, 500MB would be printed as 0.50GB.
fn printHumanReadableByteCount(bytes: usize) void {
    const kb_limit = 1000 * 1000;
    const bytes_per_kb = 1000;

    const mb_limit = kb_limit * 1000;
    const bytes_per_mb = bytes_per_kb * 1000;

    const bytes_per_gb = bytes_per_mb * 1000;

    const fbytes = @intToFloat(f64, bytes);
    if (bytes < 1000) {
        print("{d:.2} B", .{bytes});
    } else if (bytes < kb_limit) {
        print("{d:.2} KB", .{fbytes / bytes_per_kb});
    } else if (bytes < mb_limit) {
        print("{d:.2} MB", .{fbytes / bytes_per_mb});
    } else {
        print("{d:.2} GB", .{fbytes / bytes_per_gb});
    }
}

fn find_process_name(allocator: *std.mem.Allocator, pid: os.pid_t) ![]u8 {
    var path_buffer = [_]u8{0} ** 30;
    var fbs = std.io.fixedBufferStream(path_buffer[0..]);
    try std.fmt.format(fbs.outStream(), "/proc/{}/comm", .{pid});
    const path = path_buffer[0..fbs.pos];

    const fd = try os.open(path, 0, os.O_RDONLY);
    defer os.close(fd);
    var file = std.fs.File{ .handle = fd };
    var name = try file.readToEndAlloc(allocator, 1000);
    if (std.mem.endsWith(u8, name, "\n")) {
        name = allocator.shrink(name, name.len - 1);
    }
    return name;
}
