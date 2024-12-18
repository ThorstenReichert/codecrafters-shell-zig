const std = @import("std");
const mem = std.mem;
const expect = std.testing.expect;

const debug = true;

const Pal = if (@import("builtin").os.tag == .windows)
    .{ .path_separator = ";", .dir_separator = "\\", .trim_cr = true }
else
    .{ .path_separator = ":", .dir_separator = "/", .trim_cr = false };

const Result = union(enum) { exit: u8, cont };
const SplitResult = struct { []const u8, []const u8 };
const CommandType = enum { exit, echo, type, exec, unknown };
const CommandContext = struct {
    allocator: std.mem.Allocator,
    env_map: std.process.EnvMap,
    writer: std.fs.File.Writer,
};
const ExecCommand = struct {
    name: []const u8,
    path: []const u8,
};
const Command = union(CommandType) {
    exit,
    echo,
    type,
    exec: ExecCommand,
    unknown,
};

fn trace(comptime format: []const u8, args: anytype) void {
    if (debug) {
        const writer = std.io.getStdOut().writer();
        writer.print("  TRACE | ", .{}) catch unreachable;
        writer.print(format, args) catch unreachable;
        writer.print("\n", .{}) catch unreachable;
    }
}

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

fn join(allocator: mem.Allocator, parts: []const []const u8) []u8 {
    var total_length: usize = 0;
    for (parts) |part| {
        total_length += part.len;
    }

    const result = allocator.alloc(u8, total_length) catch unreachable;
    var index: usize = 0;
    for (parts) |part| {
        @memcpy(result[index .. index + part.len], part);
        index += part.len;
    }

    return result;
}

fn nextCommand(reader: anytype, buffer: []u8) ?[]const u8 {
    const line = reader.readUntilDelimiterOrEof(buffer, '\n') catch {
        return null;
    };

    if (line) |l| {
        if (Pal.trim_cr) {
            return mem.trimRight(u8, l, "\r");
        } else {
            return l;
        }
    } else {
        return null;
    }
}

fn resolveCommand(ctx: CommandContext, command_name: []const u8) Command {
    if (mem.eql(u8, command_name, "exit")) {
        return .exit;
    } else if (mem.eql(u8, command_name, "echo")) {
        return .echo;
    } else if (mem.eql(u8, command_name, "type")) {
        return .type;
    } else {
        const path = ctx.env_map.get("PATH") orelse "";
        const cwd = std.fs.cwd();

        var search_dirs = std.mem.split(u8, path, Pal.path_separator);
        while (search_dirs.next()) |dir_path| {
            const dir = cwd.openDir(dir_path, .{ .iterate = true }) catch continue;

            var files = dir.iterate();
            while (files.next() catch null) |entry| {
                if (@as(?std.fs.Dir.Entry, entry)) |file| {
                    if (mem.eql(u8, file.name, command_name)) {
                        const program_path = join(ctx.allocator, &[_]([]const u8){ mem.trimRight(u8, dir_path, Pal.dir_separator), Pal.dir_separator, command_name });

                        return Command{ .exec = ExecCommand{ .name = command_name, .path = program_path } };
                    }
                }
            }
        }

        return .unknown;
    }
}

fn handleExitCommand(args: []const u8) !Result {
    const code_text, _ = splitAtNext(args, " ");
    const code = try std.fmt.parseInt(u8, code_text, 10);

    return Result{ .exit = code };
}

fn handleEchoCommand(ctx: CommandContext, args: []const u8) !Result {
    try ctx.writer.print("{s}\n", .{args});

    return Result{ .cont = {} };
}

fn handleTypeCommand(ctx: CommandContext, args: []const u8) !Result {
    const type_text, _ = splitAtNext(args, " ");
    const command_type = resolveCommand(ctx, type_text);

    const builtin = "{s} is a shell builtin\n";
    const is_program = "{s} is {s}\n";
    const not_found = "{s}: not found\n";
    switch (command_type) {
        .exit => try ctx.writer.print(builtin, .{"exit"}),
        .echo => try ctx.writer.print(builtin, .{"echo"}),
        .type => try ctx.writer.print(builtin, .{"type"}),
        .exec => |exec_cmd| try ctx.writer.print(is_program, .{ exec_cmd.name, exec_cmd.path }),
        .unknown => try ctx.writer.print(not_found, .{type_text}),
    }

    return Result{ .cont = {} };
}

fn handleExecCommand(ctx: CommandContext, cmd: ExecCommand, args: []const u8) !Result {
    _ = ctx;
    _ = cmd;
    _ = args;

    return Result{ .cont = {} };
}

fn handleUnknownCommand(ctx: CommandContext, name: []const u8) !Result {
    try ctx.writer.print("{s}: command not found\n", .{name});
    return Result{ .cont = {} };
}

fn handleCommand(ctx: CommandContext, command: []const u8) !Result {
    const command_name, const args = splitAtNext((command), " ");
    const command_type = resolveCommand(ctx, command_name);

    return switch (command_type) {
        .exit => handleExitCommand(args),
        .echo => handleEchoCommand(ctx, args),
        .type => handleTypeCommand(ctx, args),
        .exec => |process| handleExecCommand(ctx, process, args),
        .unknown => handleUnknownCommand(ctx, command_name),
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

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const env_map = try std.process.getEnvMap(arena.allocator());
    const ctx = CommandContext{ .allocator = arena.allocator(), .env_map = env_map, .writer = stdout };

    var buffer: [1024]u8 = undefined;

    while (true) {
        try stdout.print("$ ", .{});

        @memset(&buffer, 0);
        const user_input = nextCommand(stdin, &buffer);

        // TODO: Handle user input
        if (user_input) |command| {
            const result = try handleCommand(ctx, command);

            switch (result) {
                .cont => {},
                .exit => |code| return code,
            }
        }
    }
}
