const std = @import("std");

// ----------------------------------------------------------------------------
// Tokenizing
// ----------------------------------------------------------------------------

const TokenError = error{
    UnmatchedQuote,
    InvalidKeyword,
    // UnexpectedCharacter,
};

pub const Token = struct {
    tag: Tag,
    start: u32,
    end: u32,

    const Tag = enum {
        end_of_source,

        l_brace,
        r_brace,

        l_bracket,
        r_bracket,

        l_paren,
        r_paren,

        at,
        backtick,
        caret,
        single_quote,
        splice_unquote,
        tilde,

        minus,
        plus,
        slash,
        star,

        keyword,
        number,
        quoted_string,
        symbol,

        invalid,
    };
};

fn isSkippable(c: u8) bool {
    // NOTE: MAL skips commas but does not state why
    return std.ascii.isWhitespace(c) or c == ',';
}

fn nonSpecial(c: u8) bool {
    // TODO: this is a placeholder for non-special characters
    return switch (c) {
        '[', ']', '{', '}', '(', ')', '\'', '"', '`', ',', ';' => false,
        else => true,
    };
}

const Tokenizer = struct {
    source: []const u8,
    index: u32,

    fn char(self: *Tokenizer) ?u8 {
        if (self.index >= self.source.len) return null;
        return self.source[self.index];
    }

    fn charIs(self: *Tokenizer, check: fn (u8) bool) bool {
        const c = self.char();
        return c != null and check(c.?);
    }

    fn charIsNot(self: *Tokenizer, check: fn (u8) bool) bool {
        const c = self.char();
        return c != null and !check(c.?);
    }

    fn skipWhitespace(self: *Tokenizer) void {
        while (self.charIs(isSkippable)) self.index += 1;
    }

    fn skipComment(self: *Tokenizer) void {
        while (true) {
            const c = self.char() orelse break;
            if (c == '\n') break; // End of comment
            self.index += 1;
        }
        self.index += 1;
    }

    fn skipWhitespaceAndComments(self: *Tokenizer) void {
        self.skipWhitespace();
        while (self.char() == ';') {
            self.skipComment();
            self.skipWhitespace();
        }
    }

    fn tokenizeTilde(self: *Tokenizer) Token.Tag {
        if (self.char() == '@') {
            self.index += 1;
            return .splice_unquote;
        } else {
            return .tilde;
        }
    }

    fn tokenizeKeyword(self: *Tokenizer) TokenError!Token.Tag {
        // Check for an empty keyword
        if (self.charIsNot(std.ascii.isAlphabetic)) return error.InvalidKeyword;

        while (self.charIs(std.ascii.isAlphabetic) or self.charIs(std.ascii.isDigit)) self.index += 1;
        return .keyword;
    }

    fn tokenizeString(self: *Tokenizer) TokenError!Token.Tag {
        while (true) {
            // Check for an unmatched quote
            const c = self.char() orelse return error.UnmatchedQuote;
            if (c == '\n') return error.UnmatchedQuote;

            // The current character is part of the string
            self.index += 1;

            // End of the string
            if (c == '"') break;

            // Handle escape sequences by skipping the next character
            if (c == '\\' and self.char() != null) self.index += 1;
        }
        return .quoted_string;
    }

    // fn tokenizeNumber(self: *Tokenizer) Token.Tag {
    //     // TODO: check for valid number
    //     while (self.charIs(std.ascii.isDigit)) self.index += 1;
    //     return .number;
    // }

    // fn tokenizeIdentifier(self: *Tokenizer) Token.Tag {
    //     // TODO: check for keywords? (or maybe allow contextual reuse)
    //     while (self.charIs(std.ascii.isAlphabetic)) self.index += 1;
    //     return .symbol;
    // }

    fn tokenizeNonSpecial(self: *Tokenizer) Token.Tag {
        while (self.charIs(nonSpecial) and self.charIsNot(std.ascii.isWhitespace)) self.index += 1;
        // TODO: always returning symbol for now, but we'll want to differentiate later
        return .symbol;
    }

    fn next(self: *Tokenizer) TokenError!Token {
        self.skipWhitespaceAndComments();

        const c = self.char() orelse {
            return Token{
                .tag = .end_of_source,
                .start = self.index,
                .end = self.index,
            };
        };

        // Increment index to the next character for multi-character tokens
        const start = self.index;
        self.index += 1;

        const tag = switch (c) {
            '{' => .l_brace,
            '}' => .r_brace,
            '[' => .l_bracket,
            ']' => .r_bracket,
            '(' => .l_paren,
            ')' => .r_paren,

            '\'' => .single_quote,
            '`' => .backtick,
            '^' => .caret,
            '@' => .at,

            // '+' => .plus,
            // '-' => .minus,
            // '*' => .star,
            // '/' => .slash,

            '~' => self.tokenizeTilde(),
            ':' => try self.tokenizeKeyword(),
            '"' => try self.tokenizeString(),
            else => self.tokenizeNonSpecial(),
            // '0'...'9', 'a'...'z', 'A'...'Z', '_' => self.tokenizeNonSpecial(),
            // '0'...'9' => self.tokenizeNumber(),
            // 'a'...'z', 'A'...'Z' => self.tokenizeIdentifier(),
            // else => .invalid,
        };

        return Token{
            .tag = tag,
            .start = start,
            .end = self.index,
        };
    }
};

// ----------------------------------------------------------------------------
// Reading
// ----------------------------------------------------------------------------

const Form = struct {
    tag: Tag,
    index_into_tokens: u32,
    data: Data,

    // TODO: a list of child forms as indices

    const Tag = enum {
        empty,

        atom,

        deref,
        quasiquote,
        quote,
        splice_unquote,
        unquote,

        meta,

        list,
        vector,

        map,
    };

    const Data = union(enum) {
        empty: void,
        single: u32,
        pair: struct { u32, u32 },
        list: struct { index: u32, len: u32 },
    };
};

pub const ReaderError = error{
    NoTokensRemaining,
    UnusedTokens,

    UnexpectedToken,
    UnexpectedTokenForKey,

    UnbalancedList,
    UnbalancedMap,

    EmptyQuote,
};

const Reader = struct {
    allocator: std.mem.Allocator,
    source: []const u8,

    // tokens: []const Token,
    tokens: std.ArrayList(Token),
    token_index: u32,

    forms: std.MultiArrayList(Form),
    data: std.ArrayList(u32),

    fn deinit(self: *Reader) void {
        self.tokens.deinit();
        self.forms.deinit(self.allocator);
        self.data.deinit();
    }

    fn getToken(self: *Reader) ReaderError!Token {
        if (self.token_index >= self.tokens.items.len) return error.NoTokensRemaining;
        return self.tokens.items[self.token_index];
    }

    fn expectToken(self: *Reader, tag: Token.Tag) ReaderError!void {
        const token = try self.getToken();
        if (token.tag != tag) return error.UnexpectedToken;
    }

    fn eatToken(self: *Reader, tag: Token.Tag) ReaderError!void {
        try self.expectToken(tag);
        self.token_index += 1;
    }

    fn addForm(self: *Reader, form: Form) std.mem.Allocator.Error!u32 {
        const index: u32 = @intCast(self.forms.len);
        try self.forms.append(self.allocator, form);
        return index;
    }

    fn reserveForm(self: *Reader) std.mem.Allocator.Error!u32 {
        return @intCast(try self.forms.addOne(self.allocator));
    }

    // NOTE: keeping snake case name from mal
    fn read_form(self: *Reader) (std.mem.Allocator.Error || ReaderError)!u32 {
        const token = try self.getToken();

        const form_index = switch (token.tag) {
            // Atoms
            .end_of_source,
            .keyword,
            .number,
            .quoted_string,
            .symbol,
            => try self.read_atom(),

            // Lists, vectors, and maps
            .l_paren => try self.read_list(.list, .l_paren, .r_paren),
            .l_bracket => try self.read_list(.vector, .l_bracket, .r_bracket),
            .l_brace => try self.read_hash_map(),

            // Quotes
            .at => try self.read_quote(token.tag),
            .splice_unquote => try self.read_quote(token.tag),
            .backtick => try self.read_quote(token.tag),
            .single_quote => try self.read_quote(token.tag),
            .tilde => try self.read_quote(token.tag),

            // Meta
            .caret => try self.read_meta(),

            else => unreachable,
        };

        return form_index;
    }

    // NOTE: keeping snake case name from mal
    fn read_atom(self: *Reader) (std.mem.Allocator.Error || ReaderError)!u32 {
        const token = try self.getToken();

        const tag: Form.Tag = switch (token.tag) {
            .end_of_source => .empty,
            .keyword,
            .number,
            .quoted_string,
            .symbol,
            => .atom,
            else => unreachable,
        };

        const form = Form{
            .tag = tag,
            .index_into_tokens = self.token_index,
            .data = .{ .empty = {} },
        };

        try self.eatToken(token.tag);
        return try self.addForm(form);
    }

    // NOTE: keeping snake case name from mal
    fn read_list(self: *Reader, f_tag: Form.Tag, comptime t_tag_open: Token.Tag, comptime t_tag_close: Token.Tag) (std.mem.Allocator.Error || ReaderError)!u32 {
        const token_index = self.token_index;
        try self.eatToken(t_tag_open);

        const form_index = try self.reserveForm();

        // Create an array list for indices into the data array
        var indices = std.ArrayList(u32).init(self.allocator);
        defer indices.deinit();

        while (true) {
            const token = try self.getToken();
            switch (token.tag) {
                .end_of_source => return error.UnbalancedList,
                t_tag_close => break,
                else => try indices.append(try self.read_form()),
            }
        }

        try self.eatToken(t_tag_close);

        // Copy all list indices into the data array
        const data_idx: u32 = @intCast(self.data.items.len);
        const data_len: u32 = @intCast(indices.items.len);
        for (indices.items) |index| try self.data.append(index);

        // Set the reserved form data
        self.forms.set(form_index, Form{
            .tag = f_tag,
            .index_into_tokens = token_index,
            .data = .{ .list = .{ .index = data_idx, .len = data_len } },
        });

        return form_index;
    }

    fn read_hash_map(self: *Reader) !u32 {
        const token_index = self.token_index;
        try self.eatToken(.l_brace);

        const form_index = try self.reserveForm();

        var indices = std.ArrayList(u32).init(self.allocator);
        defer indices.deinit();

        while (true) {
            const token = try self.getToken();
            switch (token.tag) {
                .end_of_source => return error.UnbalancedMap,
                .r_brace => break,
                else => |tag| {
                    // Read the key token
                    switch (tag) {
                        .keyword, .quoted_string => try indices.append(try self.read_atom()),
                        else => return error.UnexpectedTokenForKey,
                    }

                    // Read the value form
                    try indices.append(try self.read_form());
                },
            }
        }

        try self.eatToken(.r_brace);

        // Copy all list indices into the data array
        const data_idx: u32 = @intCast(self.data.items.len);
        const data_len: u32 = @intCast(indices.items.len);
        for (indices.items) |index| try self.data.append(index);

        // Set the reserved form data
        self.forms.set(form_index, Form{
            .tag = .map,
            .index_into_tokens = token_index,
            .data = .{ .list = .{ .index = data_idx, .len = data_len } },
        });

        return form_index;
    }

    // NOTE: keeping snake case name from mal
    fn read_quote(self: *Reader, tag: Token.Tag) (std.mem.Allocator.Error || ReaderError)!u32 {
        const token_index = self.token_index;
        try self.eatToken(tag);

        const form_index = try self.reserveForm();

        const quoted_form_index = try self.read_form();

        // Check for an empty quote
        switch (self.forms.items(.tag)[quoted_form_index]) {
            .empty => return error.EmptyQuote,
            else => {},
        }

        const form_tag: Form.Tag = switch (tag) {
            .at => .deref,
            .backtick => .quasiquote,
            .single_quote => .quote,
            .splice_unquote => .splice_unquote,
            .tilde => .unquote,
            else => unreachable,
        };

        // Set the reserved form data
        self.forms.set(form_index, Form{
            .tag = form_tag,
            .index_into_tokens = token_index,
            .data = .{ .single = quoted_form_index },
        });

        return form_index;
    }

    fn read_meta(self: *Reader) (std.mem.Allocator.Error || ReaderError)!u32 {
        const token_index = self.token_index;
        try self.eatToken(.caret);

        const form_index = try self.reserveForm();

        const value_index = try self.read_form();
        const meta_index = try self.read_form();

        // Set the reserved form data
        self.forms.set(form_index, Form{
            .tag = .meta,
            .index_into_tokens = token_index,
            .data = .{ .pair = .{ value_index, meta_index } },
        });

        return form_index;
    }
};

pub const FormTreeError = error{};

pub const FormTree = struct {
    reader: Reader,
    // form_index: u32,

    pub fn deinit(self: *FormTree) void {
        self.reader.deinit();
    }

    pub fn getForm(self: *FormTree, index: u32) Form {
        // if (index >= self.reader.forms.len) return error.NoFormsRemaining;
        return self.reader.forms.get(index);
    }

    pub fn getToken(self: *FormTree, index: u32) Token {
        const form = self.getForm(index);
        return self.reader.tokens.items[form.index_into_tokens];
    }

    pub fn getData(self: *FormTree, index: u32) Form.Data {
        const form = self.getForm(index);
        return form.data;
    }

    pub fn getListItems(self: *FormTree, idx: u32, len: u32) []const u32 {
        return self.reader.data.items[idx .. idx + len];
    }
};

pub fn read_str(source: []const u8, allocator: std.mem.Allocator) (std.mem.Allocator.Error || TokenError || ReaderError)!FormTree {
    var tokenizer = Tokenizer{ .source = source, .index = 0 };

    var reader = Reader{
        .allocator = allocator,
        .source = source,
        .tokens = std.ArrayList(Token).init(allocator),
        .token_index = 0,
        .forms = .{},
        .data = std.ArrayList(u32).init(allocator),
    };
    errdefer reader.deinit();

    // Collect the tokens
    while (true) {
        const token = try tokenizer.next();
        try reader.tokens.append(token);
        if (token.tag == .end_of_source) break;
    }

    // Run the reader to parse the input
    _ = try reader.read_form();

    if (reader.token_index != (reader.tokens.items.len - 1)) return error.UnusedTokens;

    return FormTree{ .reader = reader };
}
