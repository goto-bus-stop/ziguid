const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("ziguid", "src/guid.zig");
    lib.setBuildMode(mode);

    const cli = b.addExecutable("ziguid", "src/main.zig");
    cli.setBuildMode(mode);

    const guid_tests = b.addTest("src/guid.zig");
    guid_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&guid_tests.step);

    b.default_step.dependOn(&lib.step);
    b.default_step.dependOn(&cli.step);
    b.installArtifact(lib);
}
