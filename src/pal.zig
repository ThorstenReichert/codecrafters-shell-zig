const Pal = struct {
    absolute_path_prefix: []const u8,
    path_separator: []const u8,
    dir_separator: []const u8,
    trim_cr: bool,
};

const WindowsPal = Pal{
    .absolute_path_prefix = "C:\\",
    .path_separator = ";",
    .dir_separator = "\\",
    .trim_cr = true,
};
const DefaultPal = Pal{
    .absolute_path_prefix = "/",
    .path_separator = ":",
    .dir_separator = "/",
    .trim_cr = false,
};

pub const Current = if (@import("builtin").os.tag == .windows) WindowsPal else DefaultPal;
