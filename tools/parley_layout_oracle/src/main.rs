use parley::{
    Alignment, AlignmentOptions, BaseDirection, FontContext, FontFamily, InlineBox, InlineBoxKind,
    Layout, LayoutContext, PositionedLayoutItem, StyleProperty,
    fontique::{Blob, Collection, CollectionOptions, SourceCache},
};
use std::{env, fs, hint::black_box, sync::Arc, time::Instant};

#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Brush;

fn main() {
    let mut args = env::args().skip(1);
    let font_path = args.next().expect("font path");
    let text_path = args.next().expect("text path");
    let iterations: usize = args.next().expect("iterations").parse().unwrap();
    let samples: usize = args.next().expect("samples").parse().unwrap();
    let family_name = args.next().unwrap_or_else(|| "Roboto".to_owned());
    let width: f32 = args
        .next()
        .map(|value| value.parse().unwrap())
        .unwrap_or(200.0);
    assert!(width.is_finite() && width > 0.0);
    let direction = args.next().unwrap_or_else(|| "auto".to_owned());
    let style = args.next().unwrap_or_else(|| "default".to_owned());
    let phase = args.next().unwrap_or_else(|| "layout".to_owned());
    assert!(phase == "layout" || phase == "reflow");
    let fallback_font_path = args.next();
    assert!(args.next().is_none(), "unexpected argument");
    assert_eq!(
        style == "fallback",
        fallback_font_path.is_some(),
        "fallback style requires exactly one fallback font"
    );
    let text_file = fs::read_to_string(text_path).unwrap();
    let source_text = text_file.lines().next().unwrap_or("");
    let owned_text;
    let has_inline_object = matches!(style.as_str(), "inline-object" | "out-of-flow-object");
    let text = if has_inline_object {
        let split = source_text.ceil_char_boundary(source_text.len() / 2);
        owned_text = format!("{}\u{fffc}{}", &source_text[..split], &source_text[split..]);
        owned_text.as_str()
    } else {
        source_text
    };
    let font_data = fs::read(font_path).unwrap();

    let mut collection = Collection::new(CollectionOptions {
        shared: false,
        system_fonts: false,
    });
    collection.register_fonts(Blob::new(Arc::new(font_data)), None);
    let fallback_family_name = fallback_font_path.map(|path| {
        let bytes = fs::read(path).unwrap();
        collection.register_fonts(Blob::new(Arc::new(bytes)), None);
        "Noto Sans"
    });
    assert!(collection.family_id(&family_name).is_some());
    let mut font_cx = FontContext {
        collection,
        source_cache: SourceCache::default(),
    };
    let mut layout_cx = LayoutContext::<Brush>::new();
    let mut retained = if phase == "reflow" {
        // Parley keeps shaped clusters in Layout and explicitly supports
        // line-breaking the same owner again. This matches Cangjie's retained
        // ShapedParagraph boundary instead of rebuilding through RangedBuilder.
        Some(build_layout(
            &mut font_cx,
            &mut layout_cx,
            text,
            &family_name,
            &direction,
            &style,
            fallback_family_name,
        ))
    } else {
        None
    };

    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0u64;
    let mut geometry_checksum = 0u64;
    let mut object_checksum = 0u64;
    let mut glyphs = 0usize;
    let mut lines = 0usize;
    let mut objects = 0usize;
    for _ in 0..samples {
        for _ in 0..3 {
            let result = run_once(
                &mut font_cx,
                &mut layout_cx,
                text,
                &family_name,
                width,
                &direction,
                &style,
                fallback_family_name,
                retained.as_mut(),
                true,
            );
            assert!(
                checksum == 0 || checksum == result.0,
                "unstable layout output"
            );
            (
                checksum,
                geometry_checksum,
                object_checksum,
                glyphs,
                lines,
                objects,
            ) = result;
        }
        let start = Instant::now();
        let mut batch_checksum = 0xcbf29ce484222325u64;
        for _ in 0..iterations {
            let result = run_once(
                &mut font_cx,
                &mut layout_cx,
                text,
                &family_name,
                width,
                &direction,
                &style,
                fallback_family_name,
                retained.as_mut(),
                false,
            );
            assert_eq!(result.4, lines, "unstable layout line count");
            batch_checksum = bytes(batch_checksum, &result.3.to_le_bytes());
            batch_checksum = bytes(batch_checksum, &result.4.to_le_bytes());
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
        black_box(batch_checksum);
    }
    values.sort_by(f64::total_cmp);
    let median = values[values.len() / 2];
    println!(
        "engine=parley\tphase={phase}\tdirection={direction}\tstyle={style}\ttext_bytes={}\twidth={width:.3}\titerations={}\tsamples={}\tmedian_ns_per_iter={median:.3}\tglyphs={glyphs}\tlines={lines}\tobjects={objects}\tchecksum={checksum:016x}\tgeometry_checksum={geometry_checksum:016x}\tobject_checksum={object_checksum:016x}",
        text.len(),
        iterations,
        samples
    );
}

fn run_once(
    font_cx: &mut FontContext,
    layout_cx: &mut LayoutContext<Brush>,
    text: &str,
    family_name: &str,
    width: f32,
    direction: &str,
    style: &str,
    fallback_family_name: Option<&str>,
    retained: Option<&mut Layout<Brush>>,
    summarize_output: bool,
) -> (u64, u64, u64, usize, usize, usize) {
    let mut owned;
    let layout = if let Some(layout) = retained {
        layout.break_all_lines(Some(width));
        layout.align(Alignment::Start, AlignmentOptions::default());
        layout
    } else {
        owned = build_layout(
            font_cx,
            layout_cx,
            text,
            family_name,
            direction,
            style,
            fallback_family_name,
        );
        owned.break_all_lines(Some(width));
        owned.align(Alignment::Start, AlignmentOptions::default());
        &mut owned
    };
    if summarize_output {
        summarize(layout, text)
    } else {
        // Match Cangjie's measured consumer: keep line breaking, alignment,
        // output ownership, and O(1) layout fields live, while the expensive
        // cross-engine geometry walk remains outside the timed region.
        let mut checksum = 0xcbf29ce484222325u64;
        checksum = bytes(checksum, &layout.width().to_bits().to_le_bytes());
        checksum = bytes(checksum, &layout.height().to_bits().to_le_bytes());
        // Object geometry is verified by the untimed warm-up summaries. Do
        // not make Parley enumerate every line and item inside the measured
        // loop solely to reproduce that diagnostic checksum. The count is a
        // direct consequence of this benchmark's validated style/input pair.
        (checksum, 0, 0, 0, layout.len(), object_count_hint(style))
    }
}

fn object_count_hint(style: &str) -> usize {
    usize::from(style == "inline-object" || style == "out-of-flow-object")
}

fn build_layout(
    font_cx: &mut FontContext,
    layout_cx: &mut LayoutContext<Brush>,
    text: &str,
    family_name: &str,
    direction: &str,
    style: &str,
    fallback_family_name: Option<&str>,
) -> Layout<Brush> {
    // Cangjie retains fractional layout metrics. Disable Parley's optional
    // paint-time pixel snapping so both engines expose the same coordinates.
    let mut builder = layout_cx.ranged_builder(font_cx, text, 1.0, false);
    let fallback_family_source;
    if let Some(fallback) = fallback_family_name {
        // Preserve caller order explicitly: Latin resolves in Roboto and the
        // inserted Arabic segment must continue into Noto Sans.
        fallback_family_source = format!("'{family_name}', '{fallback}'");
        builder.push_default(FontFamily::from(fallback_family_source.as_str()));
    } else {
        builder.push_default(FontFamily::named(family_name));
    }
    builder.push_default(StyleProperty::FontSize(16.0));
    match style {
        "default" => {}
        "fallback" => {}
        "spacing" => {
            builder.push_default(StyleProperty::LetterSpacing(0.75));
            builder.push_default(StyleProperty::WordSpacing(2.0));
        }
        "alternating" => {
            let split = text.ceil_char_boundary(text.len() / 2);
            builder.push(StyleProperty::FontSize(18.0), split..);
            builder.push(StyleProperty::LetterSpacing(0.75), split..);
            builder.push(StyleProperty::WordSpacing(2.0), split..);
        }
        "inline-object" | "out-of-flow-object" => builder.push_inline_box(InlineBox {
            id: 1,
            kind: if style == "inline-object" {
                InlineBoxKind::InFlow
            } else {
                InlineBoxKind::OutOfFlow
            },
            // The object source coordinate is the marker inserted into the
            // original sample, not the midpoint of the now-three-byte-longer
            // benchmark string. Recomputing the midpoint moved Latin and CJK
            // objects to a later boundary and made the workloads inequivalent.
            index: text.find('\u{fffc}').expect("inline-object marker"),
            width: 24.0,
            height: 20.0,
            baseline: Some(15.0),
        }),
        _ => panic!(
            "style must be default, spacing, alternating, fallback, inline-object, or out-of-flow-object"
        ),
    }
    builder.set_base_direction(match direction {
        "auto" => BaseDirection::Auto,
        "ltr" => BaseDirection::Ltr,
        "rtl" => BaseDirection::Rtl,
        _ => panic!("direction must be auto, ltr, or rtl"),
    });
    builder.build(text)
}

fn summarize(layout: &Layout<Brush>, text: &str) -> (u64, u64, u64, usize, usize, usize) {
    let mut hash = 0xcbf29ce484222325u64;
    let mut geometry_hash = 0xcbf29ce484222325u64;
    let mut glyph_count = 0usize;
    let mut line_count = 0usize;
    for line in layout.lines() {
        line_count += 1;
        let metrics = line.metrics();
        hash = bytes(hash, &metrics.advance.to_bits().to_le_bytes());
        hash = bytes(hash, &(line.text_range().start as u64).to_le_bytes());
        hash = bytes(hash, &(line.text_range().end as u64).to_le_bytes());
        geometry_hash = bytes(
            geometry_hash,
            &(line.text_range().start as u64).to_le_bytes(),
        );
        geometry_hash = bytes(geometry_hash, &(line.text_range().end as u64).to_le_bytes());
        let mut records = Vec::new();
        for run in line.runs() {
            for cluster in run.clusters() {
                let range = cluster.text_range();
                records.push((
                    range.start,
                    range.end - range.start,
                    cluster.visual_offset().unwrap_or_default(),
                    if text[range.start..line.text_range().end]
                        .bytes()
                        .all(|byte| byte == b' ' || byte == b'\t')
                    {
                        0.0
                    } else {
                        cluster.advance()
                    },
                ));
            }
        }
        records.sort_by_key(|record| record.0);
        let origin = records
            .iter()
            .find_map(|record| (record.3 != 0.0).then_some(record.2))
            .unwrap_or_default();
        for (start, len, position, size) in records {
            geometry_hash = bytes(geometry_hash, &(start as u64).to_le_bytes());
            geometry_hash = bytes(geometry_hash, &(len as u64).to_le_bytes());
            // Match Cangjie's logical-line normalization: discard only a
            // constant line translation and sub-1/1024 px accumulation noise.
            let logical_position = if size == 0.0 {
                0
            } else {
                ((position - origin) * 1024.0).round() as i32
            };
            geometry_hash = bytes(geometry_hash, &logical_position.to_le_bytes());
            geometry_hash = bytes(geometry_hash, &size.to_bits().to_le_bytes());
        }
        for item in line.items() {
            match item {
                PositionedLayoutItem::GlyphRun(run) => {
                    for glyph in run.positioned_glyphs() {
                        glyph_count += 1;
                        hash = bytes(hash, &glyph.id.to_le_bytes());
                        hash = bytes(hash, &glyph.x.to_bits().to_le_bytes());
                        hash = bytes(hash, &glyph.y.to_bits().to_le_bytes());
                        hash = bytes(hash, &glyph.advance.to_bits().to_le_bytes());
                    }
                }
                PositionedLayoutItem::InlineBox(_) => {}
            }
        }
    }
    let (object_hash, object_count) = summarize_objects(layout, text);
    black_box(&layout);
    (
        hash,
        geometry_hash,
        object_hash,
        glyph_count,
        line_count,
        object_count,
    )
}

fn summarize_objects(layout: &Layout<Brush>, text: &str) -> (u64, usize) {
    // This oracle inserts at most one object. Parley's positioned record keeps
    // the id and geometry but not the source index, so recover that stable
    // input coordinate from the benchmark's replacement marker.
    let object_byte_index = text.find('\u{fffc}');
    let expected_count = usize::from(object_byte_index.is_some());
    let mut object_hash = 0xcbf29ce484222325u64;
    object_hash = bytes(object_hash, &(expected_count as u64).to_le_bytes());
    let mut object_count = 0;
    for (line_index, line) in layout.lines().enumerate() {
        for item in line.items() {
            let PositionedLayoutItem::InlineBox(inline_box) = item else {
                continue;
            };
            object_count += 1;
            object_hash = bytes(object_hash, &inline_box.id.to_le_bytes());
            object_hash = bytes(
                object_hash,
                &(object_byte_index.expect("positioned object marker") as u64).to_le_bytes(),
            );
            object_hash = bytes(object_hash, &(line_index as u64).to_le_bytes());
            for coordinate in [
                inline_box.x,
                inline_box.y,
                inline_box.width,
                inline_box.height,
                inline_box.baseline.unwrap_or(inline_box.height),
            ] {
                object_hash = bytes(
                    object_hash,
                    &canonical_inline_position(coordinate).to_le_bytes(),
                );
            }
        }
    }
    assert_eq!(
        object_count, expected_count,
        "missing positioned inline object"
    );
    (object_hash, object_count)
}

fn canonical_inline_position(value: f32) -> i32 {
    // Keep the same 1/1024 px normalization as Cangjie. Rust's saturating
    // float-to-int cast also matches the explicit bounds in the Zig oracle.
    (value * 1024.0).round() as i32
}

#[cfg(test)]
mod tests {
    use super::{bytes, canonical_inline_position};

    #[test]
    fn object_hash_encoding_is_little_endian_and_quantized() {
        let mut hash = 0xcbf29ce484222325u64;
        hash = bytes(hash, &1u64.to_le_bytes());
        hash = bytes(hash, &7u64.to_le_bytes());
        hash = bytes(hash, &54u64.to_le_bytes());
        hash = bytes(hash, &2u64.to_le_bytes());
        for value in [34.804_688, 37.5, 24.0, 20.0, 15.0] {
            hash = bytes(hash, &canonical_inline_position(value).to_le_bytes());
        }
        assert_eq!(hash, 0x9c03a3dc53c000c4);
    }
}

fn bytes(mut hash: u64, value: &[u8]) -> u64 {
    for byte in value {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}
