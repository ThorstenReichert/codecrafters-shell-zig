const std = @import("std");

fn nextCommand(reader: anytype, buffer: []u8) !?[]const u8 {
    const line = (try reader.readUntilDelimiterOrEof(buffer, '\n')) orelse return null;

    if (@import("builtin").os.tag == .windows) {
        return std.mem.trimRight(u8, line, "\r");
    } else {
        return line;
    }
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    var buffer: [1024]u8 = undefined;

    while (true) {
        try stdout.print("$ ", .{});

        @memset(&buffer, 0);
        const user_input = try nextCommand(stdin, &buffer);

        // TODO: Handle user input
        if (user_input) |command| {
            try stdout.print("{s}: command not found\n", .{command});
        }
    }
}
