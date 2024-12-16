const std = @import("std");
const mem = std.mem;
const expect = std.testing.expect;

const Result = union(enum) { exit: u8, cont };
const SplitResult = struct { []const u8, []const u8 };
const CommandType = enum { exit, echo, type, unknown };

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

fn parseCommandType(command_name: []const u8) CommandType {
    if (mem.eql(u8, command_name, "exit")) {
        return .exit;
    } else if (mem.eql(u8, command_name, "echo")) {
        return .echo;
    } else if (mem.eql(u8, command_name, "type")) {
        return .type;
    } else {
        return .unknown;
    }
}

fn handleExitCommand(args: []const u8) !Result {
    const code_text, _ = splitAtNext(args, " ");
    const code = try std.fmt.parseInt(u8, code_text, 10);

    return Result{ .exit = code };
}

fn handleEchoCommand(writer: anytype, args: []const u8) !Result {
    try writer.print("{s}\n", .{args});

    return Result{ .cont = {} };
}

fn handleTypeCommand(writer: anytype, args: []const u8) !Result {
    const type_text, _ = splitAtNext(args, " ");
    const command_type = parseCommandType(type_text);

    const builtin = "{s} is a shell builtin\n";
    const not_found = "{s}: not found\n";
    switch (command_type) {
        .exit => try writer.print(builtin, .{"exit"}),
        .echo => try writer.print(builtin, .{"echo"}),
        .type => try writer.print(builtin, .{"type"}),
        .unknown => try writer.print(not_found, .{type_text}),
    }

    return Result{ .cont = {} };
}

fn handleUnknownCommand(writer: anytype, name: []const u8) !Result {
    try writer.print("{s}: command not found\n", .{name});
    return Result{ .cont = {} };
}

fn handleCommand(writer: anytype, command: []const u8) !Result {
    const command_name, const args = splitAtNext((command), " ");
    const command_type = parseCommandType(command_name);

    return switch (command_type) {
        .exit => handleExitCommand(args),
        .echo => handleEchoCommand(writer, args),
        .type => handleTypeCommand(writer, args),
        .unknown => handleUnknownCommand(writer, command_name),
    };
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
