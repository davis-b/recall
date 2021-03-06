const std = @import("std");
const os = std.os;
const warn = std.debug.warn;
const print = std.debug.print;

const memory = @import("memory.zig");
const readMemMap = @import("read_map.zig").readMemMap;
const input = @import("input.zig");
const Needle = @import("needle.zig").Needle;
const call_fn_with_union_type = @import("needle.zig").call_fn_with_union_type;

fn help() void {
    warn("User must supply pid and (type + bit length). User may optionally supply a byte alignment.\n", .{});
    warn("Available types are: [i, u, f, s]\n", .{});
    warn("i: signed integer   - Available with bit lengths [8, 16, 32, 64]\n", .{});
    warn("u: unsigned integer - Available with bit lengths [8, 16, 32, 64]\n", .{});
    warn("f: float            - Available with bit lengths [16, 32, 64] \n", .{});
    warn("s: string           - Does not use a bit length\n", .{});
    warn("\n", .{});
    warn("Example Usage: {s} 5005 u32\n", .{os.argv[0]});
}

pub fn main() anyerror!void {
    if (os.argv.len < 3) {
        help();
        os.exit(2);
    }

    const pid = std.fmt.parseInt(os.pid_t, std.mem.span(os.argv[1]), 10) catch |err| {
        warn("Failed parsing PID \"{s}\". {}\n", .{ os.argv[1], err });
        os.exit(2);
    };
    var needle_typeinfo = input.parseStringForType(std.mem.span(os.argv[2])) catch |err| {
        warn("Failed parsing search type \"{s}\". {}\n", .{ os.argv[2], err });
        os.exit(2);
    };

    const byte_alignment: u8 = blk: {
        const default = 4;
        if (os.argv.len > 3) {
            const result = std.fmt.parseInt(u8, std.mem.span(os.argv[3]), 10) catch default;
            if (result < 1) break :blk 1;
            break :blk result;
        }
        break :blk default;
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
        print("No memory segments found for \"{s}\", pid {}. Exiting\n", .{ process_name, pid });
        return;
    }
    var total_memory: usize = 0;
    for (memory_segments.items) |i, n| {
        total_memory += i.len;
    }
    print("{s} is using {} memory segments for a total of ", .{ process_name, memory_segments.items.len });
    printHumanReadableByteCount(total_memory);
    print("\n", .{});

    const needle: []const u8 = try input.askUserForValue(&needle_typeinfo);

    const initial_scan_start = std.time.milliTimestamp();
    var potential_addresses = (memory.parseSegments(allocator, pid, &memory_segments, needle, byte_alignment) catch |err| {
        switch (err) {
            error.InsufficientPermission => {
                print("Insufficient permission to read memory from \"{s}\" (pid {})\n", .{ process_name, pid });
                return;
            },
            else => return err,
        }
    }) orelse {
        print("No match found. Exiting.\n", .{});
        return;
    };
    defer potential_addresses.deinit();
    print("Initial scan took {} ms\n", .{std.time.milliTimestamp() - initial_scan_start});

    const maybe_final_address = try findMatch(&needle_typeinfo, pid, &potential_addresses);
    if (maybe_final_address) |addr| {
        print("Match found at: {} ({x})\n", .{ addr, addr });
        try handleFinalMatch(needle_typeinfo, pid, addr);
    } else {
        print("No match found. Exiting.\n", .{});
    }
}

/// Using user input, filters potential addresses until we have a single one remaining.
fn findMatch(needle: *Needle, pid: os.pid_t, potential_addresses: *memory.Addresses) !?usize {
    var justPrintedAddresses = false;
    while (potential_addresses.items.len > 1) {
        print("Potential addresses: {}\n", .{potential_addresses.items.len});
        if (potential_addresses.items.len < 5) {
            for (potential_addresses.items) |pa| print("potential addr: {} ({x}) \n", .{ pa, pa });
        }
        const needle_bytes = getNewNeedle(needle, potential_addresses.items);
        try memory.pruneAddresses(pid, needle_bytes, potential_addresses);
    }
    if (potential_addresses.items.len == 1) {
        return potential_addresses.items[0];
    } else {
        return null;
    }
}

/// Returns the bytes for a new needle from the user.
/// Will not return until a valid needle value is given.
/// This may result in multiple requests to the user for a needle value.
fn getNewNeedle(needle: *Needle, potential_addresses: []usize) []const u8 {
    const needle_bytes: []const u8 = input.askUserForValue(needle) catch |err| {
        switch (err) {
            error.NoInputGiven => {
                for (potential_addresses) |i, index| print("#{}: {} ({x})\n", .{ index, i, i });
                print("\n", .{});
            },
            error.Overflow, error.InvalidCharacter => warn("{}\n\n", .{err}),
        }
        return getNewNeedle(needle, potential_addresses);
    };
    return needle_bytes;
}

/// Allows user to repeatedly view the value located at the needle address.
fn handleFinalMatch(needle: Needle, pid: os.pid_t, needle_address: usize) !void {
    var buffer = [_]u8{0} ** 400;
    while (true) {
        if (needle == .string) {
            print("\nPlease enter the number of characters you would like to read, up to {} >  ", .{buffer.len});
        } else {
            print("\nEnter any character to print value at needle address, or nothing to exit >  ", .{});
        }
        const user_input = input.getStdin() orelse break;

        var str_len: usize = 0;
        if (needle == .string) {
            var peek_length = std.fmt.parseInt(usize, user_input, 10) catch continue;
            if (peek_length > buffer.len) peek_length = buffer.len;
            str_len = memory.readRemote(buffer[0..peek_length], pid, needle_address) catch |err| {
                switch (err) {
                    error.RemoteReadAmountMismatch => {
                        print("{} exceeded the length of the valid address space. Try a smaller number\n", .{peek_length});
                        continue;
                    },
                    else => return err,
                }
            };
        } else {
            _ = try memory.readRemote(buffer[0..needle.size()], pid, needle_address);
            // We are intentionally re-using parts of buffer here for both parameters. The function is safe for this use case.
            str_len = try call_fn_with_union_type(needle, anyerror!usize, printToBufferAs, .{ buffer[0..needle.size()], buffer[0..] });
        }
        print("value is: {s}\n", .{buffer[0..str_len]});
    }
}

/// Reads the given bytes as a type appropriate for the given NeedleType.
/// Prints that value to the buffer as a string.
/// Returns the number of characters written to buffer.
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

/// Returns the process name for a given pid.
/// Caller owns the memory.
fn find_process_name(allocator: *std.mem.Allocator, pid: os.pid_t) ![]u8 {
    var path_buffer = [_]u8{0} ** 30;
    var fbs = std.io.fixedBufferStream(path_buffer[0..]);
    try std.fmt.format(fbs.writer(), "/proc/{}/comm", .{pid});
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
