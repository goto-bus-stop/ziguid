const io = @import("std").io;
const GUID = @import("./guid.zig").GUID;

pub fn main() !void {
    const stdout_file = try io.getStdOut();

    const guid = try GUID.v4();
    var buffer = []u8{0} ** 38;
    const str = try guid.toString(buffer[0..], .Braced, .Lower);

    try stdout_file.write(str);
}
