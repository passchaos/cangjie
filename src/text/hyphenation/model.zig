//! Internal immutable hyphenation dictionary storage.

const std = @import("std");

pub const Mapping = struct {
    from: u21,
    to: u21,
};

pub const Options = struct {
    /// Minimum Unicode scalars retained before a generated hyphen.
    left_min: u8 = 2,
    /// Minimum Unicode scalars retained after a generated hyphen.
    right_min: u8 = 2,
    /// Optional one-to-one Unicode normalization/case mappings.
    ///
    /// These are copied during dictionary construction. ASCII A–Z folding is
    /// always built in; language data can add mappings such as Ä→ä without
    /// introducing runtime callbacks.
    mappings: []const Mapping = &.{},
};

pub const Edge = struct {
    codepoint: u21,
    child: u32,
};

pub const Weight = struct {
    position: u16,
    value: u8,
};

pub const Node = struct {
    edges: std.ArrayList(Edge) = .empty,
    weights: std.ArrayList(Weight) = .empty,
};

pub const Exception = struct {
    word: []u21,
    boundaries: []u16,
};

pub const Storage = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(Node) = .empty,
    exceptions: std.ArrayList(Exception) = .empty,
    mappings: []Mapping,
    left_min: u8,
    right_min: u8,

    pub fn deinit(self: *Storage) void {
        for (self.exceptions.items) |exception| {
            self.allocator.free(exception.boundaries);
            self.allocator.free(exception.word);
        }
        self.exceptions.deinit(self.allocator);
        self.allocator.free(self.mappings);
        for (self.nodes.items) |*node| {
            node.weights.deinit(self.allocator);
            node.edges.deinit(self.allocator);
        }
        self.nodes.deinit(self.allocator);
        self.* = undefined;
    }
};

pub fn findEdge(edges: []const Edge, codepoint: u21) ?Edge {
    var low: usize = 0;
    var high: usize = edges.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const edge = edges[mid];
        if (codepoint < edge.codepoint) {
            high = mid;
        } else if (codepoint > edge.codepoint) {
            low = mid + 1;
        } else {
            return edge;
        }
    }
    return null;
}

pub fn findWeight(weights: []const Weight, position: u16) ?usize {
    for (weights, 0..) |weight, index| {
        if (weight.position == position) return index;
    }
    return null;
}

pub fn edgeLessThan(_: void, lhs: Edge, rhs: Edge) bool {
    return lhs.codepoint < rhs.codepoint;
}

pub fn weightLessThan(_: void, lhs: Weight, rhs: Weight) bool {
    return lhs.position < rhs.position;
}

pub fn exceptionLessThan(_: void, lhs: Exception, rhs: Exception) bool {
    return scalarSliceOrder(lhs.word, rhs.word) == .lt;
}

pub fn scalarSliceOrder(
    lhs: []const u21,
    rhs: []const u21,
) std.math.Order {
    const shared_len = @min(lhs.len, rhs.len);
    for (lhs[0..shared_len], rhs[0..shared_len]) |left, right| {
        if (left < right) return .lt;
        if (left > right) return .gt;
    }
    return std.math.order(lhs.len, rhs.len);
}

pub fn scalarSlicesEqual(lhs: []const u21, rhs: []const u21) bool {
    return scalarSliceOrder(lhs, rhs) == .eq;
}

/// Pattern resources are conventionally lowercase. Apply the locale-neutral
/// ASCII fold used by English and many Latin pattern sets. Applications using
/// language-specific Unicode case mapping should normalize their word and
/// pattern resources consistently before dictionary construction.
pub fn normalizedCodepoint(
    mappings: []const Mapping,
    codepoint: u21,
) u21 {
    if (codepoint >= 'A' and codepoint <= 'Z') {
        return codepoint + ('a' - 'A');
    }
    var low: usize = 0;
    var high: usize = mappings.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const mapping = mappings[mid];
        if (codepoint < mapping.from) {
            high = mid;
        } else if (codepoint > mapping.from) {
            low = mid + 1;
        } else {
            return mapping.to;
        }
    }
    return codepoint;
}

pub fn mappingLessThan(_: void, lhs: Mapping, rhs: Mapping) bool {
    return lhs.from < rhs.from;
}

pub fn isAsciiWhitespace(codepoint: u21) bool {
    return codepoint == ' ' or codepoint == '\t' or
        codepoint == '\r' or codepoint == '\n';
}
