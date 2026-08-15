//! Cursive joining properties and resolved forms.

const unicode = @import("../../unicode.zig");

pub const Form = unicode.JoiningForm;
pub const Type = unicode.JoiningType;

pub const typeOf = unicode.joiningTypeForCodepoint;
pub const resolve = unicode.resolveJoiningForms;
