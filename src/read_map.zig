const std = @import("std");
const os = std.os;

pub const Segments = std.ArrayList(Segment);
/// A segment of readable memory.
const Segment = struct {
    start: usize,
    len: usize,
    name: ?[]u8 = null,
};

/// Reads /proc/pid/maps file for a given pid.
/// Translates the addresses in that file into Segment structs, representing memory owned by the pid.
pub fn readMemMap(allocator: *std.mem.Allocator, pid: os.pid_t) !Segments {
    var path_buffer = [_]u8{0} ** 30;
    var fbs = std.io.fixedBufferStream(path_buffer[0..]);
    try std.fmt.format(fbs.writer(), "/proc/{}/maps", .{pid});
    const path = path_buffer[0..fbs.pos];

    const fd = try os.open(path, 0, os.O_RDONLY);
    defer os.close(fd);

    var file = std.fs.File{ .handle = fd };
    const map_data = try file.readToEndAlloc(allocator, 1_024_000);
    defer allocator.free(map_data);

    return try parseMap(allocator, map_data);
}

fn parseMap(allocator: *std.mem.Allocator, map_data: []u8) !Segments {
    var segments = Segments.init(allocator);
    errdefer segments.deinit();

    // map_data's line structure:
    // start-end, perms, data, time, data, maybe_name
    var it = std.mem.split(map_data, "\n");
    while (it.next()) |line| {
        if (line.len == 0) continue;
        var tokens = std.mem.split(line, " ");
        var token_index: usize = 0;
        var segment: Segment = undefined;
        while (tokens.next()) |token| {
            // Ignore tokens that are more delimeters
            // Might not be needed if we move token 4+ code into its own block
            // if (token_index > 4 and token.len == 0) continue;
            if (token_index == 0) {
                segment = try parseMemRange(token);
            }
            // Check to see if the memory segment is readable. We can safely ignore memory that is not readable.
            else if (token_index == 1) {
                if (token[0] != 'r') {
                    break;
                }
                // There is the possiblity for memory to have no name associated.
                // Thus, we must look at future tokens from the token preceding the name token.
            } else if (token_index == 4) {
                var has_name = false;
                while (tokens.next()) |name| {
                    if (name.len == 0) continue;
                    has_name = true;
                    // Token is the name of the memory allocator
                    // Ignore [stack], [vsyscall], etc
                    if (name[0] == '[' or name[0] == ' ') break;
                    if (std.mem.startsWith(u8, name, "/dev/")) break;
                    if (std.mem.startsWith(u8, name, "/newroot/dev/")) break;
                    // if (std.mem.indexOf(u8, name, ".so")) |_| break;
                    // if (std.mem.indexOf(u8, name, ".cache")) |_| break;

                    segment.name = try allocator.alloc(u8, name.len);
                    for (name) |char, index| segment.name.?[index] = char;
                    try segments.append(segment);
                }
                if (!has_name) {
                    try segments.append(segment);
                }
            }
            token_index += 1;
        }
    }
    return segments;
}

fn parseMemRange(str_range: []const u8) !Segment {
    var it = std.mem.split(str_range, "-");
    const hex_start = it.next().?;
    const start = try std.fmt.parseInt(usize, hex_start, 16);
    const hex_end = it.next().?;
    const end = try std.fmt.parseInt(usize, hex_end, 16);
    const size = end - start;
    return Segment{ .start = start, .len = size };
}
