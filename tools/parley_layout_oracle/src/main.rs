use parley::{
    Alignment, AlignmentOptions, BaseDirection, FontContext, FontFamily, InlineBox, InlineBoxKind,
    Layout, LayoutContext, PositionedLayoutItem, StyleProperty,
    fontique::{Blob, Collection, CollectionOptions, SourceCache},
};
use std::{env, fs, hint::black_box, sync::Arc, time::Instant};

#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Brush;

#[derive(Clone, Copy, Debug)]
struct GeometryRecord {
    start: usize,
    len: usize,
    is_rtl: bool,
    position: f32,
    size: f32,
    discarded_size: f32,
}

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
    let has_inline_object = matches!(
        style.as_str(),
        "inline-object" | "out-of-flow-object" | "custom-out-of-flow-object"
    );
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
        "Noto Sans Devanagari"
    });
    assert!(collection.family_id(&family_name).is_some());
    let mut font_cx = FontContext {
        collection,
        source_cache: SourceCache::default(),
    };
    let mut layout_cx = LayoutContext::<Brush>::new();
    // Match Cangjie's reusable Engine output boundary for construction.
    // `build_into` still performs fresh text analysis and shaping, but retains
    // Layout-owned allocation capacity across timed iterations.
    let mut rebuild_layout = Layout::<Brush>::default();
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
    let mut placement_checksum = 0u64;
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
                &mut rebuild_layout,
                true,
            );
            assert!(
                checksum == 0 || checksum == result.0,
                "unstable layout output"
            );
            (
                checksum,
                geometry_checksum,
                placement_checksum,
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
                &mut rebuild_layout,
                false,
            );
            assert_eq!(result.5, lines, "unstable layout line count");
            batch_checksum = bytes(batch_checksum, &result.4.to_le_bytes());
            batch_checksum = bytes(batch_checksum, &result.5.to_le_bytes());
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
        black_box(batch_checksum);
    }
    values.sort_by(f64::total_cmp);
    let median = values[values.len() / 2];
    println!(
        "engine=parley\tphase={phase}\tdirection={direction}\tstyle={style}\ttext_bytes={}\twidth={width:.3}\titerations={}\tsamples={}\tmedian_ns_per_iter={median:.3}\tglyphs={glyphs}\tlines={lines}\tobjects={objects}\tchecksum={checksum:016x}\tgeometry_checksum={geometry_checksum:016x}\tplacement_checksum={placement_checksum:016x}\tobject_checksum={object_checksum:016x}",
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
    rebuild_layout: &mut Layout<Brush>,
    summarize_output: bool,
) -> (u64, u64, u64, u64, usize, usize, usize) {
    let alignment = alignment_for_style(style);
    let layout = if let Some(layout) = retained {
        break_layout(layout, width, style);
        layout.align(alignment, AlignmentOptions::default());
        layout
    } else {
        build_layout_into(
            font_cx,
            layout_cx,
            rebuild_layout,
            text,
            family_name,
            direction,
            style,
            fallback_family_name,
        );
        break_layout(rebuild_layout, width, style);
        rebuild_layout.align(alignment, AlignmentOptions::default());
        rebuild_layout
    };
    if summarize_output {
        summarize(layout, text, style)
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
        (checksum, 0, 0, 0, 0, layout.len(), object_count_hint(style))
    }
}

fn alignment_for_style(style: &str) -> Alignment {
    if style == "center" {
        Alignment::Center
    } else {
        Alignment::Start
    }
}

fn object_count_hint(style: &str) -> usize {
    usize::from(matches!(
        style,
        "inline-object" | "out-of-flow-object" | "custom-out-of-flow-object"
    ))
}

fn break_layout(layout: &mut Layout<Brush>, width: f32, style: &str) {
    if style != "custom-out-of-flow-object" {
        layout.break_all_lines(Some(width));
        return;
    }

    let mut breaker = layout.break_lines();
    breaker.state_mut().set_layout_max_advance(width);
    breaker.state_mut().set_line_max_advance(width);
    while let Some(yield_data) = breaker.break_next() {
        if let parley::YieldData::InlineBoxBreak(object) = yield_data {
            // The matched workload supplies absolute paint geometry outside
            // the breaker, so the custom marker contributes no line occupancy.
            breaker
                .state_mut()
                .append_inline_box_to_line(object.advance, 0.0, 0.0, false);
        }
    }
    breaker.finish();
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
    let mut layout = Layout::default();
    build_layout_into(
        font_cx,
        layout_cx,
        &mut layout,
        text,
        family_name,
        direction,
        style,
        fallback_family_name,
    );
    layout
}

fn build_layout_into(
    font_cx: &mut FontContext,
    layout_cx: &mut LayoutContext<Brush>,
    layout: &mut Layout<Brush>,
    text: &str,
    family_name: &str,
    direction: &str,
    style: &str,
    fallback_family_name: Option<&str>,
) {
    // Cangjie retains fractional layout metrics. Disable Parley's optional
    // paint-time pixel snapping so both engines expose the same coordinates.
    let mut builder = layout_cx.ranged_builder(font_cx, text, 1.0, false);
    let fallback_family_source;
    if let Some(fallback) = fallback_family_name {
        // Preserve caller order explicitly: Latin resolves in Roboto and the
        // inserted Devanagari segment must continue into Noto Sans Devanagari.
        fallback_family_source = format!("'{family_name}', '{fallback}'");
        builder.push_default(FontFamily::from(fallback_family_source.as_str()));
    } else {
        builder.push_default(FontFamily::named(family_name));
    }
    builder.push_default(StyleProperty::FontSize(16.0));
    match style {
        "default" | "center" => {}
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
        "inline-object" | "out-of-flow-object" | "custom-out-of-flow-object" => builder
            .push_inline_box(InlineBox {
                id: 1,
                kind: match style {
                    "inline-object" => InlineBoxKind::InFlow,
                    "out-of-flow-object" => InlineBoxKind::OutOfFlow,
                    _ => InlineBoxKind::CustomOutOfFlow,
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
            "style must be default, center, spacing, alternating, fallback, inline-object, out-of-flow-object, or custom-out-of-flow-object"
        ),
    }
    builder.set_base_direction(match direction {
        "auto" => BaseDirection::Auto,
        "ltr" => BaseDirection::Ltr,
        "rtl" => BaseDirection::Rtl,
        _ => panic!("direction must be auto, ltr, or rtl"),
    });
    builder.build_into(layout, text);
}

fn summarize(
    layout: &Layout<Brush>,
    text: &str,
    style: &str,
) -> (u64, u64, u64, u64, usize, usize, usize) {
    let mut hash = 0xcbf29ce484222325u64;
    let mut geometry_hash = 0xcbf29ce484222325u64;
    let mut placement_hash = 0xcbf29ce484222325u64;
    let mut glyph_count = 0usize;
    let mut line_count = 0usize;
    // `Layout::is_rtl` is the resolved paragraph level even when the builder
    // request was Auto. It is the authority for deciding which physical edge
    // contains logical trailing whitespace.
    let paragraph_is_rtl = layout.is_rtl();
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
        let mut trailing_advance = 0.0;
        for run in line.runs() {
            for cluster in run.clusters() {
                let range = cluster.text_range();
                let trailing = text[range.start..line.text_range().end]
                    .bytes()
                    .all(|byte| byte == b' ' || byte == b'\t');
                let advance = cluster.advance();
                if trailing {
                    trailing_advance += advance;
                }
                records.push(GeometryRecord {
                    start: range.start,
                    len: range.end - range.start,
                    // This is the resolved cluster/run direction, not the
                    // paragraph base direction exposed by Layout::is_rtl.
                    // Discarded wrapping whitespace has no visible direction.
                    // Match the zero-position/zero-size normalization below.
                    is_rtl: !trailing && cluster.is_rtl(),
                    position: cluster.visual_offset().unwrap_or_default(),
                    size: if trailing { 0.0 } else { advance },
                    discarded_size: if trailing { advance } else { 0.0 },
                });
            }
        }
        records.sort_by_key(|record| record.start);
        let logical_origin = records
            .iter()
            .find(|record| record.size != 0.0)
            .map(|record| collapsed_inline_position(&records, record));
        // Preserve absolute physical placement while excluding wrapping
        // whitespace. In an RTL paragraph the logical suffix is the physical
        // prefix, so advance past it using the resolved base direction.
        let placement = visible_line_origin(
            metrics.inline_min_coord,
            metrics.offset,
            trailing_advance,
            paragraph_is_rtl,
            logical_origin.is_some(),
        );
        placement_hash = hash_line_placement(
            placement_hash,
            line.text_range().start,
            line.text_range().end,
            placement,
        );
        for record in &records {
            geometry_hash = bytes(geometry_hash, &(record.start as u64).to_le_bytes());
            geometry_hash = bytes(geometry_hash, &(record.len as u64).to_le_bytes());
            geometry_hash = bytes(geometry_hash, &[u8::from(record.is_rtl)]);
            // Match Cangjie's logical-line normalization: discard only a
            // constant line translation and sub-1/1024 px accumulation noise.
            let logical_position = if record.size == 0.0 {
                0
            } else {
                ((collapsed_inline_position(&records, record) - logical_origin.unwrap_or_default())
                    * 1024.0)
                    .round() as i32
            };
            geometry_hash = bytes(geometry_hash, &logical_position.to_le_bytes());
            geometry_hash = bytes(geometry_hash, &record.size.to_bits().to_le_bytes());
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
    let (object_hash, object_count) = summarize_objects(layout, text, style);
    black_box(&layout);
    (
        hash,
        geometry_hash,
        placement_hash,
        object_hash,
        glyph_count,
        line_count,
        object_count,
    )
}

fn collapsed_inline_position(records: &[GeometryRecord], record: &GeometryRecord) -> f32 {
    let discarded_before = records
        .iter()
        .filter(|discarded| discarded.discarded_size != 0.0 && discarded.position < record.position)
        .map(|discarded| discarded.discarded_size)
        .sum::<f32>();
    record.position - discarded_before
}

fn visible_line_origin(
    inline_min_coord: f32,
    alignment_offset: f32,
    trailing_advance: f32,
    paragraph_is_rtl: bool,
    has_visible_content: bool,
) -> f32 {
    inline_min_coord
        + alignment_offset
        + if paragraph_is_rtl && has_visible_content {
            trailing_advance
        } else {
            0.0
        }
}

fn summarize_objects(layout: &Layout<Brush>, text: &str, style: &str) -> (u64, usize) {
    // This oracle inserts at most one object. Parley's positioned record keeps
    // the id and geometry but not the source index, so recover that stable
    // input coordinate from the benchmark's replacement marker.
    let object_byte_index = text.find('\u{fffc}');
    let expected_count = usize::from(object_byte_index.is_some());
    let mut object_hash = 0xcbf29ce484222325u64;
    object_hash = bytes(object_hash, &(expected_count as u64).to_le_bytes());
    if style == "custom-out-of-flow-object" {
        const CUSTOM_X: f32 = 11.0;
        const CUSTOM_Y: f32 = 13.0;
        const CUSTOM_WIDTH: f32 = 24.0;
        const CUSTOM_HEIGHT: f32 = 20.0;
        const CUSTOM_BASELINE: f32 = 15.0;
        let byte_index = object_byte_index.expect("custom object marker");
        let line_index = layout
            .lines()
            .enumerate()
            .find_map(|(line_index, line)| {
                let range = line.text_range();
                (byte_index >= range.start && byte_index < range.end).then_some(line_index)
            })
            .expect("custom object line");
        object_hash = bytes(object_hash, &1u64.to_le_bytes());
        object_hash = bytes(object_hash, &(byte_index as u64).to_le_bytes());
        object_hash = bytes(object_hash, &(line_index as u64).to_le_bytes());
        for coordinate in [
            CUSTOM_X,
            CUSTOM_Y,
            CUSTOM_WIDTH,
            CUSTOM_HEIGHT,
            CUSTOM_BASELINE,
        ] {
            object_hash = bytes(
                object_hash,
                &canonical_inline_position(coordinate).to_le_bytes(),
            );
        }
        return (object_hash, 1);
    }
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
    (f64::from(value) * 1024.0).round() as i32
}

fn hash_line_placement(mut hash: u64, start: usize, end: usize, x: f32) -> u64 {
    hash = bytes(hash, &(start as u64).to_le_bytes());
    hash = bytes(hash, &(end as u64).to_le_bytes());
    bytes(hash, &canonical_placement_position(x).to_le_bytes())
}

fn canonical_placement_position(value: f32) -> i32 {
    // Preserve subpixel placement while absorbing one-ULP differences caused
    // by the engines accumulating full-line advances in different orders.
    (f64::from(value) * 256.0).round() as i32
}

#[cfg(test)]
mod tests {
    use super::{
        Alignment, alignment_for_style, bytes, canonical_inline_position, hash_line_placement,
        visible_line_origin,
    };

    #[test]
    fn center_style_selects_center_alignment_only() {
        assert_eq!(alignment_for_style("center"), Alignment::Center);
        assert_eq!(alignment_for_style("default"), Alignment::Start);
    }

    #[test]
    fn placement_hash_encoding_is_absolute_and_quantized() {
        let placement_hash = |x| hash_line_placement(0xcbf29ce484222325, 2, 7, x);
        assert_eq!(placement_hash(12.25), 0x64a39f74d2658244);
        assert_ne!(placement_hash(12.25), placement_hash(12.25 + 1.0 / 256.0),);
    }

    #[test]
    fn visible_origin_uses_resolved_direction_for_trailing_whitespace() {
        assert_eq!(visible_line_origin(2.0, -3.0, 5.0, true, true), 4.0);
        assert_eq!(visible_line_origin(2.0, -3.0, 5.0, false, true), -1.0);
        // Empty or zero-advance lines have no visible edge to move past.
        assert_eq!(visible_line_origin(2.0, -3.0, 5.0, true, false), -1.0);
        assert_eq!(visible_line_origin(2.0, -3.0, 0.0, true, true), -1.0);
    }

    #[test]
    fn visible_origin_resolves_auto_rtl_and_survives_reflow() {
        use super::{BaseDirection, FontContext, LayoutContext, StyleProperty};

        let mut font_cx = FontContext::default();
        let mut layout_cx = LayoutContext::new();
        let text = "مرحبا ";
        let mut builder = layout_cx.ranged_builder(&mut font_cx, text, 1.0, false);
        builder.push_default(StyleProperty::FontSize(16.0));
        builder.set_base_direction(BaseDirection::Auto);
        let mut layout = builder.build(text);
        assert!(layout.is_rtl());

        let origin = |layout: &parley::Layout<super::Brush>| {
            let line = layout.lines().next().expect("one line");
            let metrics = line.metrics();
            visible_line_origin(
                metrics.inline_min_coord,
                metrics.offset,
                0.0,
                layout.is_rtl(),
                true,
            )
        };
        layout.break_all_lines(Some(200.0));
        layout.align(Alignment::Start, parley::AlignmentOptions::default());
        let first = origin(&layout);
        assert!(first > 0.0);

        layout.break_all_lines(Some(200.0));
        layout.align(Alignment::Start, parley::AlignmentOptions::default());
        assert_eq!(origin(&layout), first);
    }

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
