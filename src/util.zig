const std = @import("std");
const mem = std.mem;
const expect = std.testing.expect;
const pal = @import("pal.zig").Current;

pub const SplitResult = struct { []const u8, []const u8 };

pub fn splitAtNext(text: []const u8, separator: []const u8) SplitResult {
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

pub fn join(allocator: mem.Allocator, parts: []const []const u8) []u8 {
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

pub fn join_path(allocator: mem.Allocator, path1: []const u8, path2: []const u8) []u8 {
    const left = mem.trimRight(u8, path1, pal.dir_separator);
    const separator = pal.dir_separator;
    const right = path2;

    return join(allocator, &[_]([]const u8){ left, separator, right });
}
