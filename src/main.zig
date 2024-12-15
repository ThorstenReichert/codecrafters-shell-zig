const std = @import("std");

const Result = union(enum) { exit: u8, cont };

fn nextCommand(reader: anytype, buffer: []u8) !?[]const u8 {
    const line = (try reader.readUntilDelimiterOrEof(buffer, '\n')) orelse return null;

    if (@import("builtin").os.tag == .windows) {
        return std.mem.trimRight(u8, line, "\r");
    } else {
        return line;
    }
}

fn handleCommand(writer: anytype, command: []const u8) !Result {
    if (std.mem.startsWith(u8, command, "exit 0")) {
        return Result{ .exit = 0 };
    } else {
        try writer.print("{s}: command not found\n", .{command});
        return Result{ .cont = {} };
    }
}

pub fn main() !u8 {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    var buffer: [1024]u8 = undefined;

    while (true) {
        try stdout.print("$ ", .{});

        @memset(&buffer, 0);
        const user_input = try nextCommand(stdin, &buffer);

        // TODO: Handle user input
        if (user_input) |command| {
            const result = try handleCommand(stdout, command);

            switch (result) {
                .cont => {},
                .exit => |code| return code,
            }
        }
    }
}
