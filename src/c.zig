const builtin = @import("builtin");
const std = @import("std");
const os = std.os;

pub const iovec = if (builtin.link_libc)
    @cImport({
        @cInclude("sys/uio.h");
    }).iovec
else
    extern struct {
        iov_base: *c_void,
        iov_len: usize,
    };

pub const readv = if (builtin.is_test) testable_readv else real_readv;

fn real_readv(pid: os.pid_t, buffer: []u8, remote_addr: usize) !usize {
    var local_iov = iovec{ .iov_base = @ptrCast(*c_void, buffer), .iov_len = buffer.len };
    var remote_iov = iovec{ .iov_base = @intToPtr(*c_void, remote_addr), .iov_len = buffer.len };

    var write_array = [_]iovec{local_iov};
    var read_array = [_]iovec{remote_iov};

    const result = os.linux.syscall6(
        os.SYS.process_vm_readv,
        @intCast(usize, pid),
        @ptrToInt(&write_array),
        write_array.len,
        @ptrToInt(&read_array),
        read_array.len,
        0,
    );
    try handleError(result);
    return result;
}

/// Instead of reading memory from an active process,
///  this function reads from the 'value_for_buffer' variable.
/// This is automatically used when zig is running tests.
fn testable_readv(unused: os.pid_t, buffer: []u8, value_for_buffer: anytype) !usize {
    const value_as_bytes = std.mem.asBytes(&value_for_buffer);
    if (value_as_bytes.len > buffer.len and value_as_bytes[buffer.len] != 0) return error.ReadvTestError;

    for (buffer) |*i, n| i.* = value_as_bytes[n];
    return buffer.len;
}

fn handleError(result: usize) !void {
    const err = os.errno(result);
    return switch (err) {
        0 => {},
        os.EFAULT => error.InvalidMemorySpace,
        os.EINVAL => error.EINVAL,
        os.ENOMEM => error.MemoryError,
        os.EPERM => error.InsufficientPermission,
        os.ESRCH => error.NoPIDExists,
        else => error.UnknownPVReadvError,
    };
}

pub fn writev(pid: os.pid_t, buffer: []u8, remote_addr: usize) !usize {
    var local_iov = iovec{ .iov_base = @ptrCast(*c_void, buffer), .iov_len = buffer.len };
    var remote_iov = iovec{ .iov_base = @intToPtr(*c_void, remote_addr), .iov_len = buffer.len };

    var read_array = [_]iovec{local_iov};
    var write_array = [_]iovec{remote_iov};

    const result = os.linux.syscall6(
        os.SYS.process_vm_writev,
        // Syscall expects pid_t, zig fn expects usize.
        @intCast(usize, pid),
        @ptrToInt(&read_array),
        write_array.len,
        @ptrToInt(&write_array),
        read_array.len,
        0,
    );
    try handleError(result);
    return result;
}
