const std = @import("std");
const os = std.os;
const warn = std.debug.warn;
const expectEqual = std.testing.expectEqual;

const readv = @import("c.zig").readv;
const MemSegments = @import("read_map.zig").Segments;
const NeedleType = @import("input.zig").NeedleType;
// TODO@Performance: A linked list is likely to offer better performance in the most common scenarios
pub const Addresses = std.ArrayList(usize);

/// Looks through a dereferenced segment of memory for values that match our needle.
/// Returns the index of the next match, or null if there are no remaining matches.
/// 
/// "byte_alignment" helps determine how much padding is placed between each item in memory.
/// Or for our purposes, how many bytes we can skip after each checked item.
/// If the alignment is its minimum value of 1, items are placed contiguously 
///  in memory with no padding between them.
/// If the alignment, N, is greater than 1, there will exist padding between 
///  items such that the starting byte of each item will be at
///  an index evenly divisible by N.
/// Example: [ u16, pad_byte, pad_byte, u24, pad_byte, u32 ]
fn findMatches(pos: *usize, haystack: []const u8, needle: []const u8, byte_alignment: u8) ?usize {
    // Example situation: We're looking for a needle of 2 bytes in a haystack of 5 bytes.
    // The outer index will start at 0 and iterate through until it has finished an inner loop with the (5-2)nd byte.
    // The inner index will be iterated through upon each iteration of the outer index.
    // Visually it would look like:
    // [[1], 2, 3, 4, 5] outer = 0, inner = 0
    // [[1, 2], 3, 4, 5] outer = 0, inner = 1
    // [1, [2], 3, 4, 5] outer = 1, inner = 0
    // ...
    // [1, 2, 3, [4, 5]] outer = 3, inner = 1
    const new_haystack = haystack[pos.*..];
    var outer_index: usize = 0;
    while (outer_index < new_haystack.len) : (outer_index += byte_alignment) {
        // No more room left in haystack for needle matches.
        if (new_haystack.len < outer_index + needle.len) break;
        var is_match: bool = false;
        for (needle) |i, inner_index| {
            is_match = i == new_haystack[outer_index + inner_index];
            if (!is_match) {
                break;
            }
        }
        if (is_match) {
            const abs_index = outer_index + pos.*;
            pos.* += outer_index + 1;
            return abs_index;
        }
    }
    return null;
}

/// Takes a list of segments. Looks through each address for a match of our expected value.
/// The expected value is represented as a series of bytes.
/// Finally, returns a list of all memory addresses that contain the value we are looking for.
pub fn parseSegments(allocator: *std.mem.Allocator, pid: os.pid_t, segments: *MemSegments, expected_value: []const u8, byte_alignment: u8) !?Addresses {
    var potential_addresses = Addresses.init(allocator);
    errdefer potential_addresses.deinit();
    var buffer = try allocator.alloc(u8, 0);
    defer allocator.free(buffer);
    for (segments.items) |segment| {
        buffer = try allocator.realloc(buffer, segment.len);
        const read_amount = readv(pid, buffer, segment.start) catch |err| {
            warn("Failed reading from segment: 0x{x}-0x{x} name \"{s}\"\n", .{ segment.start, segment.start + segment.len, segment.name });
            return err;
        };
        if (read_amount != buffer.len) {
            warn("Partially read from segment: 0x{x}-0x{x} name \"{s}\"\n", .{ segment.start, segment.start + segment.len, segment.name });
            warn("Expected to read {} bytes, instead read {} bytes\n", .{ segment.len, read_amount });
            continue;
        }
        var pos: usize = 0;
        while (findMatches(&pos, buffer[0..read_amount], expected_value, byte_alignment)) |match_pos| {
            try potential_addresses.append(segment.start + match_pos);
        }
    }

    if (potential_addresses.items.len == 0) {
        return null;
    } else {
        return potential_addresses;
    }
}

// TODO@Performance
// it might be faster to simply readv the entire memory segment from the target process, at least when we're dealing with large haystacks.
// A single larger than necessary read will be faster than many small reads
pub fn pruneAddresses(pid: os.pid_t, needle: []const u8, haystack: *Addresses) !void {
    var buffer = [_]u8{0} ** 256;
    var pos: usize = haystack.items.len - 1;
    while (true) {
        const ptr = haystack.items[pos];
        if (!isMatch(pid, buffer[0..], needle, ptr)) {
            _ = haystack.orderedRemove(pos);
        }
        if (pos == 0) break;
        pos -= 1;
    }
}

fn isMatch(pid: os.pid_t, buffer: []u8, expected: []const u8, ptr: usize) bool {
    std.debug.assert(buffer.len >= expected.len);
    const read_amount = readv(pid, buffer[0..expected.len], ptr) catch |err| {
        warn("{} reading ptr: {x}\n", .{ err, ptr });
        return false;
    };
    std.debug.assert(read_amount == expected.len);
    return std.mem.eql(u8, expected, buffer[0..read_amount]);
}

/// Reads from a remote process at the given address.
/// Reads as much as the buffer will allow.
pub fn readRemote(buffer: []u8, pid: os.pid_t, address: usize) !usize {
    const read = try readv(pid, buffer[0..], address);
    if (read != buffer.len) return error.RemoteReadAmountMismatch;
    return read;
}

/// Reads the value located at an address.
/// Prints that value to the buffer as a string.
pub fn readToBufferAs(comptime T: type, buffer: []u8, pid: os.pid_t, address: usize) !usize {
    if (@typeInfo(T) != .Int and @typeInfo(T) != .Float) return @compileError("readToBufferAs requires an int or float type\n");
    var result_buffer = [_]u8{0} ** @sizeOf(T);
    const read_amount = try readRemote(result_buffer[0..], pid, address);
    const result = @ptrCast(*align(1) T, result_buffer[0..read_amount]).*;
    return (try std.fmt.bufPrint(buffer, "{}", .{result})).len;
}

test "find matches with 1 byte alignment" {
    const haystack = &[_]u8{ 11, 12, 13, 14, 15 };
    var pos: usize = 0;
    // Normal use.
    try expectEqual(@as(?usize, 0), findMatches(&pos, haystack, &[_]u8{11}, 1));
    try expectEqual(@as(?usize, 1), pos);
    pos = 0;
    try expectEqual(@as(?usize, 0), findMatches(&pos, haystack, &[_]u8{ 11, 12, 13, 14, 15 }, 1));
    pos = 0;
    try expectEqual(@as(?usize, 2), findMatches(&pos, haystack, &[_]u8{ 13, 14 }, 1));
    try expectEqual(@as(?usize, 3), pos);
    pos = 0;
    try expectEqual(@as(?usize, 4), findMatches(&pos, haystack, &[_]u8{15}, 1));
    try expectEqual(@as(?usize, 5), pos);

    // Calling function after a simluated match, where our needle is not in the adjusted buffer.
    pos = 1;
    try expectEqual(@as(?usize, null), findMatches(&pos, haystack, &[_]u8{ 11, 12, 13, 14, 15 }, 1));
    try expectEqual(@as(?usize, 1), pos);
    try expectEqual(@as(?usize, null), findMatches(&pos, haystack, &[_]u8{ 11, 12, 13, 14 }, 1));
    pos = 0;

    // Calling function after a simluated match, where our needle is in the adjusted buffer.
    pos = 2;
    try expectEqual(@as(?usize, 2), findMatches(&pos, haystack, &[_]u8{ 13, 14 }, 1));

    // Needle is not in buffer
    pos = 0;
    try expectEqual(@as(?usize, null), findMatches(&pos, haystack, &[_]u8{ 9, 5, 8, 7, 3 }, 1));
    try expectEqual(@as(?usize, 0), pos);
    try expectEqual(@as(?usize, null), findMatches(&pos, haystack, &[_]u8{ 11, 12, 13, 14, 17 }, 1));
    try expectEqual(@as(?usize, 0), pos);
    try expectEqual(@as(?usize, null), findMatches(&pos, haystack, &[_]u8{ 13, 13, 14 }, 1));
    try expectEqual(@as(?usize, 0), pos);

    // Needle is larger than adjusted buffer, but not full buffer.
    pos = 3;
    try expectEqual(@as(?usize, null), findMatches(&pos, haystack, &[_]u8{ 14, 15, 16 }, 1));
}

test "find matches with variable byte alignment" {
    var haystack: [100]u8 = undefined;
    for (haystack) |*i, index| i.* = @intCast(u8, index);
    const hay = haystack[0..];
    var pos: usize = 0;

    try expectEqual(@as(?usize, 4), findMatches(&pos, hay, &[_]u8{ 4, 5, 6 }, 4));
    try expectEqual(@as(?usize, null), findMatches(&pos, hay, &[_]u8{ 4, 5, 6 }, 4));
    pos = 0;

    try expectEqual(@as(?usize, 0), findMatches(&pos, hay, hay, 30));
    pos = 0;

    try expectEqual(@as(?usize, null), findMatches(&pos, hay, &[_]u8{1}, 2));
    try expectEqual(@as(?usize, 0), pos);
    pos = 0;

    try expectEqual(@as(?usize, 0), findMatches(&pos, hay, &[_]u8{0}, 4));
    try expectEqual(@as(?usize, 1), pos);
    pos = 0;

    try expectEqual(@as(?usize, 8), findMatches(&pos, hay, &[_]u8{ 8, 9, 10, 11, 12, 13, 14, 15, 16 }, 8));
    pos = 0;
}
