const std = @import("std");
const reader = @import("reader.zig");

pub const PrintBuffer = std.ArrayList(u8);
const FormTree = reader.FormTree;
const Token = reader.Token;

// NOTE: keeping snake case name from mal
pub fn pr_str(source: []const u8, tree: *FormTree, buffer: *PrintBuffer) ![]const u8 {
    // The root form is always at index 0
    try formToStr(source, tree, 0, buffer);
    return buffer.items[0..buffer.items.len];
}

pub fn formToStr(source: []const u8, tree: *FormTree, form_index: u32, buffer: *PrintBuffer) !void {
    const form = tree.getForm(form_index);
    switch (form.tag) {
        .empty => {},
        .atom => try atomToStr(source, tree.getToken(form_index), buffer),
        .list => try listToStr(source, tree, form_index, buffer, '(', ')'),
        .vector => try listToStr(source, tree, form_index, buffer, '[', ']'),
        .map => try listToStr(source, tree, form_index, buffer, '{', '}'),
        .deref => try quoteToStr(source, tree, form_index, buffer, "deref"),
        .quasiquote => try quoteToStr(source, tree, form_index, buffer, "quasiquote"),
        .quote => try quoteToStr(source, tree, form_index, buffer, "quote"),
        .splice_unquote => try quoteToStr(source, tree, form_index, buffer, "splice-unquote"),
        .unquote => try quoteToStr(source, tree, form_index, buffer, "unquote"),
        .meta => try metaToStr(source, tree, form_index, buffer),
    }
}

fn atomToStr(source: []const u8, token: Token, buffer: *PrintBuffer) std.mem.Allocator.Error!void {
    const str = source[token.start..token.end];
    switch (token.tag) {
        .keyword, .quoted_string, .symbol => try buffer.writer().print("{s}", .{str}),
        else => unreachable,
    }
}

fn listToStr(source: []const u8, tree: *FormTree, form_index: u32, buffer: *PrintBuffer, open: u8, close: u8) std.mem.Allocator.Error!void {
    const data = tree.getData(form_index);

    var idx: u32 = undefined;
    var len: u32 = undefined;

    switch (data) {
        .list => |list| {
            idx = list.index;
            len = list.len;
        },
        else => unreachable,
    }

    try buffer.append(open);

    var firstItem = true;
    for (tree.getListItems(idx, len)) |index| {
        if (!firstItem) try buffer.append(' ');
        firstItem = false;
        try formToStr(source, tree, index, buffer);
    }

    try buffer.append(close);
}

fn quoteToStr(source: []const u8, tree: *FormTree, form_index: u32, buffer: *PrintBuffer, tag: []const u8) std.mem.Allocator.Error!void {
    try buffer.append('(');
    try buffer.appendSlice(tag);
    try buffer.append(' ');
    const quoted_form_index = tree.getData(form_index).single;
    try formToStr(source, tree, quoted_form_index, buffer);
    try buffer.append(')');
}

fn metaToStr(source: []const u8, tree: *FormTree, form_index: u32, buffer: *PrintBuffer) std.mem.Allocator.Error!void {
    const meta = tree.getData(form_index).pair;
    try buffer.appendSlice("(with-meta ");
    try formToStr(source, tree, meta[1], buffer);
    try buffer.append(' ');
    try formToStr(source, tree, meta[0], buffer);
    try buffer.append(')');
}
