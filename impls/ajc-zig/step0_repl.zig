const std = @import("std");

fn read(buffer: []const u8) []const u8 {
    return buffer;
}

fn eval(buffer: []const u8) []const u8 {
    return buffer;
}

fn print(buffer: []const u8) []const u8 {
    return buffer;
}

fn rep(buffer: []const u8) []const u8 {
    return print(eval(read(buffer)));
}

pub fn main() !void {
    var line_buffer: [1024]u8 = undefined;

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    while (true) {
        stdout.writeAll("user> ") catch unreachable;

        if (stdin.readUntilDelimiter(&line_buffer, '\n')) |line| {
            const result = rep(line);
            stdout.print("{s}\n", .{result}) catch unreachable;
        } else |err| switch (err) {
            error.EndOfStream => break,
            else => |other_error| return other_error,
        }
    }
}

test "basic string" {
    const input: []const u8 = "hello";
    try std.testing.expectEqualStrings(input, rep(input));
}

test "long string" {
    const input: []const u8 = "hello world abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789 (;:() []{}\"'* ;:() []{}\"'* ;:() []{}\"'*)";
    try std.testing.expectEqualStrings(input, rep(input));
}
