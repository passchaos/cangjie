//! GSUB FeatureList and ScriptList activation-graph validation.
//!
//! Lookup subtable grammar is validated by the executor. This module proves
//! that Feature tables name existing lookups and every LangSys entry names an
//! existing FeatureRecord, including its mandatory ReqFeatureIndex.

const selection = @import("selection.zig");
const table = @import("../table/root.zig");

pub const Error = table.view.Error;
pub const View = table.View;

/// Validate FeatureList lookup references and return its record count.
pub fn lookupReferences(view: View, lookup_count: u16) Error!u16 {
    const feature_list_offset = try requiredTopLevelOffset(view, 6);
    const feature_count = try readU16ForValidation(view, feature_list_offset);
    try view.ensure(feature_list_offset + 2, @as(usize, feature_count) * 6);

    for (0..feature_count) |feature_index| {
        const feature_record =
            feature_list_offset + 2 + feature_index * 6;
        const feature_offset = try table.offset.required16(
            view,
            feature_list_offset,
            try readU16ForValidation(view, feature_record + 4),
        );
        try view.ensure(feature_offset, 4);
        const feature_lookup_count =
            try readU16ForValidation(view, feature_offset + 2);
        try view.ensure(
            feature_offset + 4,
            @as(usize, feature_lookup_count) * 2,
        );
        for (0..feature_lookup_count) |lookup_index| {
            if (try readU16ForValidation(
                view,
                feature_offset + 4 + lookup_index * 2,
            ) >= lookup_count) {
                return error.BadGsub;
            }
        }
    }
    return feature_count;
}

/// Validate every Script/LangSys edge against one proven FeatureList count.
pub fn scriptReferences(view: View, feature_count: u16) Error!void {
    const script_list_offset = try requiredTopLevelOffset(view, 4);
    const script_count = try readU16ForValidation(view, script_list_offset);
    try view.ensure(script_list_offset + 2, @as(usize, script_count) * 6);
    try selection.validateScriptRecords(
        view,
        script_list_offset,
        script_count,
    );

    for (0..script_count) |script_index| {
        const script_record = script_list_offset + 2 + script_index * 6;
        const script_offset = try table.offset.required16(
            view,
            script_list_offset,
            try readU16ForValidation(view, script_record + 4),
        );
        try view.ensure(script_offset, 4);
        const default_language_relative =
            try readU16ForValidation(view, script_offset);
        const language_count =
            try readU16ForValidation(view, script_offset + 2);
        try view.ensure(script_offset + 4, @as(usize, language_count) * 6);
        try selection.validateLanguageRecords(
            view,
            script_offset,
            language_count,
        );

        if (try table.offset.optional16(
            view,
            script_offset,
            default_language_relative,
        )) |default_language| {
            try languageReferences(view, default_language, feature_count);
        }
        for (0..language_count) |language_index| {
            const language_record =
                script_offset + 4 + language_index * 6;
            const language_offset = try table.offset.required16(
                view,
                script_offset,
                try readU16ForValidation(view, language_record + 4),
            );
            try languageReferences(view, language_offset, feature_count);
        }
    }
}

fn languageReferences(
    view: View,
    language_offset: usize,
    feature_count: u16,
) Error!void {
    try view.ensure(language_offset, 6);
    const required_feature =
        try readU16ForValidation(view, language_offset + 2);
    if (required_feature != 0xffff and required_feature >= feature_count) {
        return error.BadGsub;
    }

    const language_feature_count =
        try readU16ForValidation(view, language_offset + 4);
    try view.ensure(
        language_offset + 6,
        @as(usize, language_feature_count) * 2,
    );
    for (0..language_feature_count) |feature_index| {
        if (try readU16ForValidation(
            view,
            language_offset + 6 + feature_index * 2,
        ) >= feature_count) {
            return error.BadGsub;
        }
    }
}

fn requiredTopLevelOffset(view: View, field_offset: usize) Error!usize {
    return table.offset.required16(
        view,
        0,
        try readU16ForValidation(view, field_offset),
    );
}

fn readU16ForValidation(view: View, relative: usize) Error!u16 {
    return view.readU16(relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}
