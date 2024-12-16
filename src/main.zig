const std = @import("std");
const mem = std.mem;
const expect = std.testing.expect;

const Result = union(enum) { exit: u8, cont };
const SplitResult = struct { []const u8, []const u8 };

fn splitAtNext(text: []const u8, separator: []const u8) SplitResult {
    const separator_index = mem.indexOf(u8, text, separator);
    if (separator_index) |index| {
        return SplitResult{ text[0..index], text[(index + 1)..] };
    } else {
        return SplitResult{ text, "" };
    }
}

test "splitAtNext [separator in middle]" {
    const token, const remainder = splitAtNext("first second third", " ");

    try expect(mem.eql(u8, token, "first"));
    try expect(mem.eql(u8, remainder, "second third"));
}

test "splitAtNext [separator at start]" {
    const token, const remainder = splitAtNext(" first second", " ");

    try expect(mem.eql(u8, token, ""));
    try expect(mem.eql(u8, remainder, "first second"));
}

test "splitAtNext [separator at end]" {
    const token, const remainder = splitAtNext("first ", " ");

    try expect(mem.eql(u8, token, "first"));
    try expect(mem.eql(u8, remainder, ""));
}

fn nextCommand(reader: anytype, buffer: []u8) ?[]const u8 {
    const line = reader.readUntilDelimiterOrEof(buffer, '\n') catch {
        return null;
    };

    if (line) |l| {
        if (@import("builtin").os.tag == .windows) {
            return mem.trimRight(u8, l, "\r");
        } else {
            return l;
        }
    } else {
        return null;
    }
}

fn handleCommand(writer: anytype, command: []const u8) !Result {
    const command_name, const args = splitAtNext((command), " ");

    if (mem.eql(u8, command_name, "exit")) {
        const code_text, _ = splitAtNext(args, " ");
        const code = try std.fmt.parseInt(u8, code_text, 10);
        return Result{ .exit = code };
    } else if (mem.eql(u8, command_name, "echo")) {
        try writer.print("{s}\n", .{args});
        return Result{ .cont = {} };
    } else {
        try writer.print("{s}: command not found\n", .{command});
        return Result{ .cont = {} };
    }
}

test "parse int" {
    _, const arg = splitAtNext("exit 1", " ");

    const code = try std.fmt.parseInt(u8, arg, 10);
    try expect(code == 1);
}

pub fn main() !u8 {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    var buffer: [1024]u8 = undefined;

    while (true) {
        try stdout.print("$ ", .{});

        @memset(&buffer, 0);
        const user_input = nextCommand(stdin, &buffer);

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
