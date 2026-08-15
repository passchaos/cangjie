//! OpenType MATH constants, constructions, assemblies, and kern records.

const font = @import("../../../../font.zig");

pub const Constant = font.MathConstant;
pub const Table = font.MathInfo;
pub const Constants = font.MathConstantsInfo;
pub const Value = font.MathValueRecordInfo;
pub const GlyphValue = font.MathGlyphValueRecordInfo;
pub const Variant = font.MathVariantRecordInfo;
pub const Part = font.MathPartRecordInfo;
pub const Assembly = font.MathAssemblyInfo;
pub const Construction = font.MathConstructionInfo;
pub const Kern = font.MathKernInfo;
pub const KernRecord = font.MathKernRecordInfo;
pub const KernTable = font.MathKernTableInfo;
