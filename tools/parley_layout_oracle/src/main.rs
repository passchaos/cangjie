use parley::{
    Alignment, AlignmentOptions, FontContext, FontFamily, Layout, LayoutContext,
    PositionedLayoutItem, StyleProperty,
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
    let text_file = fs::read_to_string(text_path).unwrap();
    let text = text_file.lines().next().unwrap_or("");
    let font_data = fs::read(font_path).unwrap();

    let mut collection = Collection::new(CollectionOptions {
        shared: false,
        system_fonts: false,
    });
    collection.register_fonts(Blob::new(Arc::new(font_data)), None);
    assert!(collection.family_id(&family_name).is_some());
    let mut font_cx = FontContext {
        collection,
        source_cache: SourceCache::default(),
    };
    let mut layout_cx = LayoutContext::<Brush>::new();

    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0u64;
    let mut glyphs = 0usize;
    let mut lines = 0usize;
    for _ in 0..samples {
        for _ in 0..3 {
            let result = run_once(&mut font_cx, &mut layout_cx, text, &family_name, width);
            assert!(
                checksum == 0 || checksum == result.0,
                "unstable layout output"
            );
            (checksum, glyphs, lines) = result;
        }
        let start = Instant::now();
        let mut batch_checksum = 0u64;
        for _ in 0..iterations {
            let result = run_once(&mut font_cx, &mut layout_cx, text, &family_name, width);
            assert_eq!(result, (checksum, glyphs, lines), "unstable layout output");
            batch_checksum = mix(batch_checksum, result.0);
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
        black_box(batch_checksum);
    }
    values.sort_by(f64::total_cmp);
    let median = values[values.len() / 2];
    println!(
        "engine=parley\ttext_bytes={}\twidth={width:.3}\titerations={}\tsamples={}\tmedian_ns_per_iter={median:.3}\tglyphs={glyphs}\tlines={lines}\tchecksum={checksum:016x}",
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
) -> (u64, usize, usize) {
    let mut builder = layout_cx.ranged_builder(font_cx, text, 1.0, true);
    builder.push_default(FontFamily::named(family_name));
    builder.push_default(StyleProperty::FontSize(16.0));
    let mut layout: Layout<Brush> = builder.build(text);
    layout.break_all_lines(Some(width));
    layout.align(Alignment::Start, AlignmentOptions::default());

    let mut hash = 0xcbf29ce484222325u64;
    let mut glyph_count = 0usize;
    let mut line_count = 0usize;
    for line in layout.lines() {
        line_count += 1;
        let metrics = line.metrics();
        hash = bytes(hash, &metrics.advance.to_bits().to_le_bytes());
        hash = bytes(hash, &(line.text_range().start as u64).to_le_bytes());
        hash = bytes(hash, &(line.text_range().end as u64).to_le_bytes());
        for item in line.items() {
            if let PositionedLayoutItem::GlyphRun(run) = item {
                for glyph in run.positioned_glyphs() {
                    glyph_count += 1;
                    hash = bytes(hash, &glyph.id.to_le_bytes());
                    hash = bytes(hash, &glyph.x.to_bits().to_le_bytes());
                    hash = bytes(hash, &glyph.y.to_bits().to_le_bytes());
                    hash = bytes(hash, &glyph.advance.to_bits().to_le_bytes());
                }
            }
        }
    }
    black_box(&layout);
    (hash, glyph_count, line_count)
}

fn bytes(mut hash: u64, value: &[u8]) -> u64 {
    for byte in value {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn mix(seed: u64, value: u64) -> u64 {
    bytes(seed ^ 0xcbf29ce484222325, &value.to_le_bytes())
}
