const std = @import("std");
const reader = @import("reader.zig");
const printer = @import("printer.zig");

const FormTree = reader.FormTree;
const PrintBuffer = printer.PrintBuffer;

fn read(source: []const u8, allocator: std.mem.Allocator) !FormTree {
    return try reader.read_str(source, allocator);
}

fn eval(tree: *FormTree) *FormTree {
    return tree;
}

fn print(source: []const u8, tree: *FormTree, buffer: *PrintBuffer) ![]const u8 {
    return printer.pr_str(source, tree, buffer);
}

fn rep(source: []const u8, buffer: *PrintBuffer, allocator: std.mem.Allocator) ![]const u8 {
    var tree = try read(source, allocator);
    defer tree.deinit();

    const result = eval(&tree);
    return print(source, result, buffer);
}

pub fn main() !void {
    var line_buffer: [1024]u8 = undefined;

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var da = std.heap.DebugAllocator(.{}){};
    const allocator = da.allocator();

    var buffer = PrintBuffer.init(allocator);
    defer buffer.deinit();

    while (true) {
        try stdout.writeAll("user> ");

        if (stdin.readUntilDelimiter(&line_buffer, '\n')) |line| {
            if (rep(line, &buffer, allocator)) |result| {
                try stdout.print("{s}\n", .{result});
                buffer.clearAndFree();
            } else |err| switch (err) {
                error.UnmatchedQuote => try stderr.writeAll("unbalanced\n"),
                error.UnbalancedList => try stderr.writeAll("unbalanced\n"),
                error.UnbalancedMap => try stderr.writeAll("unbalanced\n"),
                else => try stderr.print("Error: {!}\n", .{err}),
            }
        } else |err| switch (err) {
            error.EndOfStream => break,
            else => |other_error| return other_error,
        }
    }

    const leaked = da.detectLeaks();
    std.debug.print("Has memory leaked: {any}", .{leaked});
}
