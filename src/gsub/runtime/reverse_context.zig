//! Exact reverse-chaining context lookup.

const model = @import("../accelerator/model.zig");

pub fn find(
    entries: []const model.ReverseChainingContextEntry,
    key: model.ReverseChainingContextKey,
) ?model.ReverseChainingContextEntry {
    var low: usize = 0;
    var high: usize = entries.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (!entries[middle].key.lessThan(key)) {
            high = middle;
        } else {
            low = middle + 1;
        }
    }
    if (low < entries.len and entries[low].key.eql(key)) return entries[low];
    return null;
}
