const std = @import("std");
const mem = std.mem;
const util = @import("util.zig");
const Pal = @import("pal.zig").Current;

const debug = true;

fn trace(comptime format: []const u8, args: anytype) void {
    if (debug) {
        const writer = std.io.getStdOut().writer();
        writer.print("  TRACE | ", .{}) catch unreachable;
        writer.print(format, args) catch unreachable;
        writer.print("\n", .{}) catch unreachable;
    }
}

const Result = union(enum) { exit: u8, cont };
const CommandType = enum { exit, echo, type, exec, unknown };
const Context = struct {
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

const BuiltinSymbolKind = enum { exit, echo, type };
const BuiltinSymbol = struct { name: []const u8, kind: BuiltinSymbolKind };
const FileSymbol = struct { name: []const u8, path: []const u8 };
const UnknownSymbol = struct { name: []const u8 };
const SymbolType = enum { builtin, file, unknown };
const Symbol = union(SymbolType) {
    builtin: BuiltinSymbol,
    file: FileSymbol,
    unknown: UnknownSymbol,
};

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

fn resolveBuiltinSymbol(symbol_name: []const u8) ?BuiltinSymbol {
    if (mem.eql(u8, symbol_name, "exit")) {
        return BuiltinSymbol{ .name = symbol_name, .kind = .exit };
    } else if (mem.eql(u8, symbol_name, "echo")) {
        return BuiltinSymbol{ .name = symbol_name, .kind = .echo };
    } else if (mem.eql(u8, symbol_name, "type")) {
        return BuiltinSymbol{ .name = symbol_name, .kind = .type };
    } else {
        return null;
    }
}

fn resolveFileSymbol(ctx: Context, symbol_name: []const u8) ?FileSymbol {
    const path = ctx.env_map.get("PATH") orelse "";
    const cwd = std.fs.cwd();

    var search_dirs = std.mem.split(u8, path, Pal.path_separator);
    while (search_dirs.next()) |dir_path| {
        const dir = cwd.openDir(dir_path, .{ .iterate = true }) catch continue;

        var files = dir.iterate();
        while (files.next() catch null) |entry| {
            if (@as(?std.fs.Dir.Entry, entry)) |file| {
                if (mem.eql(u8, file.name, symbol_name)) {
                    const program_path = util.join_path(ctx.allocator, dir_path, symbol_name);

                    return FileSymbol{ .name = symbol_name, .path = program_path };
                }
            }
        }
    }

    return null;
}

fn resolveSymbol(ctx: Context, symbol_name: []const u8) Symbol {
    if (resolveBuiltinSymbol(symbol_name)) |builtin| {
        return Symbol{ .builtin = builtin };
    } else if (resolveFileSymbol(ctx, symbol_name)) |file| {
        return Symbol{ .file = file };
    } else {
        return Symbol{ .unknown = UnknownSymbol{ .name = symbol_name } };
    }
}

fn resolveCommand(ctx: Context, command_name: []const u8) Command {
    _ = ctx;

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
    const code_text, _ = util.splitAtNext(args, " ");
    const code = try std.fmt.parseInt(u8, code_text, 10);

    return Result{ .exit = code };
}

fn handleEchoCommand(ctx: Context, args: []const u8) !Result {
    try ctx.writer.print("{s}\n", .{args});

    return Result{ .cont = {} };
}

fn handleTypeCommand(ctx: Context, args: []const u8) !Result {
    const type_text, _ = util.splitAtNext(args, " ");
    const symbol = resolveSymbol(ctx, type_text);

    const builtin = "{s} is a shell builtin\n";
    const is_program = "{s} is {s}\n";
    const not_found = "{s}: not found\n";
    switch (symbol) {
        .builtin => |builtin_symbol| try ctx.writer.print(builtin, .{builtin_symbol.name}),
        .file => |file_symbol| try ctx.writer.print(is_program, .{ file_symbol.name, file_symbol.path }),
        .unknown => try ctx.writer.print(not_found, .{type_text}),
    }

    return Result{ .cont = {} };
}

fn handleExecCommand(ctx: Context, cmd: ExecCommand, args: []const u8) !Result {
    _ = ctx;
    _ = cmd;
    _ = args;

    return Result{ .cont = {} };
}

fn handleUnknownCommand(ctx: Context, name: []const u8) !Result {
    try ctx.writer.print("{s}: command not found\n", .{name});
    return Result{ .cont = {} };
}

fn handleCommand(ctx: Context, command: []const u8) !Result {
    const command_name, const args = util.splitAtNext((command), " ");
    const command_type = resolveCommand(ctx, command_name);

    return switch (command_type) {
        .exit => handleExitCommand(args),
        .echo => handleEchoCommand(ctx, args),
        .type => handleTypeCommand(ctx, args),
        .exec => |process| handleExecCommand(ctx, process, args),
        .unknown => handleUnknownCommand(ctx, command_name),
    };
}

pub fn main() !u8 {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const env_map = try std.process.getEnvMap(arena.allocator());
    const ctx = Context{ .allocator = arena.allocator(), .env_map = env_map, .writer = stdout };

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
