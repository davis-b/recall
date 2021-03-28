// This program is tested to build with zig version 0.7.1
const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("memview", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const memedit = b.addExecutable("memedit", "src/memory_editor.zig");
    memedit.setTarget(target);
    memedit.setBuildMode(mode);
    memedit.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run library tests");

    const tests = .{
        "src/memory.zig",
    };

    inline for (tests) |path| {
        var test_ = b.addTest(path);
        test_.setTarget(target);
        test_.setBuildMode(mode);
        test_.linkLibC();
        test_step.dependOn(&test_.step);
    }
}
