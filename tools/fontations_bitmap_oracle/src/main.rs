use skrifa::{
    bitmap::BitmapData,
    outline::{DrawSettings, Hinting, OutlinePen},
    prelude::{LocationRef, NormalizedCoord, Size},
    string::StringId,
    FontRef, GlyphId, MetadataProvider,
};
use std::{env, fs, hint::black_box, process, time::Instant};

fn fail(message: &str) -> ! {
    eprintln!("fontations bitmap oracle: {message}");
    process::exit(1);
}

fn main() {
    let mut args = env::args().skip(1);
    let path = args.next().unwrap_or_else(|| fail("missing font path"));
    let mode = args.next().unwrap_or_else(|| fail("missing mode"));
    let glyph_id: u32 = args
        .next()
        .unwrap_or_else(|| fail("missing glyph id"))
        .parse()
        .unwrap_or_else(|_| fail("invalid glyph id"));
    let bytes = fs::read(path).unwrap_or_else(|_| fail("cannot read font"));
    let font = FontRef::new(&bytes).unwrap_or_else(|_| fail("cannot parse font"));
    match mode.as_str() {
        "bitmap" => bitmap(&font, glyph_id, &mut args),
        "bitmap-bench" => bitmap_bench(&font, glyph_id, &mut args),
        "bitmap-summary" => bitmap_summary(&font, glyph_id, &mut args),
        "outline" => outline(&font, glyph_id, &mut args),
        "outline-at" => outline_at(&font, glyph_id, &mut args),
        "outline-reuse" => outline_reuse(&font, glyph_id, &mut args),
        "outline-reuse-at" => outline_reuse_at(&font, glyph_id, &mut args),
        "metrics" => metrics(&font, glyph_id, &mut args),
        "bounds" => bounds(&font, glyph_id, &mut args),
        "global-metrics" => global_metrics(&font, &mut args),
        "family-name" => family_name(&font, &mut args),
        "glyph-name" => glyph_name(&font, glyph_id, &mut args),
        "attributes" => attributes(&font, &mut args),
        "variations" => variations(&font, &mut args),
        "palettes" => palettes(&font, &mut args),
        "strikes" => strikes(&font, &mut args),
        "color-glyph" => color_glyph(&font, glyph_id, &mut args),
        "charmap" => charmap(&font, glyph_id, &mut args),
        _ => fail("unsupported mode"),
    }
}

fn color_glyph(font: &FontRef<'_>, glyph_id: u32, args: &mut impl Iterator<Item = String>) {
    let (iterations, samples) = repeated_args(args);
    let gid = GlyphId::new(glyph_id);
    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0_u64;
    for _ in 0..samples {
        let start = Instant::now();
        for _ in 0..iterations {
            let collection = font.color_glyphs();
            let v1 = collection
                .get_with_format(gid, skrifa::color::ColorGlyphFormat::ColrV1)
                .is_some();
            let v0 = collection
                .get_with_format(gid, skrifa::color::ColorGlyphFormat::ColrV0)
                .is_some();
            checksum = checksum
                .wrapping_add(u64::from(v1))
                .wrapping_add(u64::from(v0) << 1);
            black_box(collection.get(gid));
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
    }
    values.sort_by(f64::total_cmp);
    let collection = font.color_glyphs();
    println!(
        "engine=skrifa\tmode=color-glyph\titerations={iterations}\tsamples={samples}\tmedian_ns_per_iter={:.3}\tv1={}\tv0={}\tchecksum={checksum:016x}",
        values[values.len() / 2],
        collection
            .get_with_format(gid, skrifa::color::ColorGlyphFormat::ColrV1)
            .is_some(),
        collection
            .get_with_format(gid, skrifa::color::ColorGlyphFormat::ColrV0)
            .is_some(),
    );
}

fn strikes(font: &FontRef<'_>, args: &mut impl Iterator<Item = String>) {
    let (iterations, samples) = repeated_args(args);
    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0_u64;
    for _ in 0..samples {
        let start = Instant::now();
        for _ in 0..iterations {
            let strikes = font.bitmap_strikes();
            checksum = checksum
                .wrapping_add(match strikes.format() {
                    None => 0,
                    Some(skrifa::bitmap::BitmapFormat::Sbix) => 0,
                    Some(skrifa::bitmap::BitmapFormat::Cbdt) => 1,
                    Some(skrifa::bitmap::BitmapFormat::Ebdt) => 2,
                })
                .wrapping_add(strikes.len() as u64);
            for strike in strikes.iter() {
                checksum = checksum.wrapping_add(u64::from(strike.ppem().to_bits()));
            }
            black_box(strikes);
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
    }
    values.sort_by(f64::total_cmp);
    let strikes = font.bitmap_strikes();
    println!(
        "engine=skrifa\tmode=strikes\titerations={iterations}\tsamples={samples}\tmedian_ns_per_iter={:.3}\tformat={:?}\tstrikes={}\tchecksum={checksum:016x}",
        values[values.len() / 2],
        strikes.format(),
        strikes.len(),
    );
}

fn palettes(font: &FontRef<'_>, args: &mut impl Iterator<Item = String>) {
    let (iterations, samples) = repeated_args(args);
    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0_u64;
    for _ in 0..samples {
        let start = Instant::now();
        for _ in 0..iterations {
            let palettes = font.color_palettes();
            checksum = checksum.wrapping_add(u64::from(palettes.len()));
            for index in 0..palettes.len() {
                let palette = palettes.get(index).unwrap();
                checksum = checksum
                    .wrapping_add(u64::from(palette.index()))
                    .wrapping_add(palette.colors().len() as u64)
                    .wrapping_add(u64::from(
                        palette.palette_type().map(|v| v.bits()).unwrap_or_default(),
                    ))
                    .wrapping_add(u64::from(
                        palette.label().map(|id| id.to_u16()).unwrap_or_default(),
                    ));
                for color in palette.colors() {
                    checksum = checksum.wrapping_add(
                        u64::from(color.red())
                            | (u64::from(color.green()) << 8)
                            | (u64::from(color.blue()) << 16)
                            | (u64::from(color.alpha()) << 24),
                    );
                }
            }
            black_box(palettes);
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
    }
    values.sort_by(f64::total_cmp);
    let palettes = font.color_palettes();
    let entries = palettes
        .get(0)
        .map(|p| p.colors().len())
        .unwrap_or_default();
    println!(
        "engine=skrifa\tmode=palettes\titerations={iterations}\tsamples={samples}\tmedian_ns_per_iter={:.3}\tpalettes={}\tentries={}\tchecksum={checksum:016x}",
        values[values.len() / 2],
        palettes.len(),
        entries,
    );
}

fn variations(font: &FontRef<'_>, args: &mut impl Iterator<Item = String>) {
    let (iterations, samples) = repeated_args(args);
    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0_u64;
    for _ in 0..samples {
        let start = Instant::now();
        for _ in 0..iterations {
            let axes = font.axes();
            let instances = font.named_instances();
            checksum = checksum.wrapping_add(axes.len() as u64);
            for axis in axes.iter() {
                checksum = checksum
                    .wrapping_add(u64::from(
                        axis.tag()
                            .to_be_bytes()
                            .iter()
                            .fold(0_u32, |v, b| (v << 8) | u32::from(*b)),
                    ))
                    .wrapping_add(axis.index() as u64)
                    .wrapping_add(u64::from(axis.name_id().to_u16()))
                    .wrapping_add(u64::from(axis.is_hidden()))
                    .wrapping_add(u64::from(axis.min_value().to_bits()))
                    .wrapping_add(u64::from(axis.default_value().to_bits()))
                    .wrapping_add(u64::from(axis.max_value().to_bits()));
            }
            checksum = checksum.wrapping_add(instances.len() as u64);
            for instance in instances.iter() {
                checksum = checksum
                    .wrapping_add(u64::from(instance.subfamily_name_id().to_u16()))
                    .wrapping_add(u64::from(
                        instance
                            .postscript_name_id()
                            .map(|id| id.to_u16())
                            .unwrap_or_default(),
                    ));
                for coord in instance.user_coords() {
                    checksum = checksum.wrapping_add(u64::from(coord.to_bits()));
                }
            }
            black_box((axes, instances));
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
    }
    values.sort_by(f64::total_cmp);
    println!(
        "engine=skrifa\tmode=variations\titerations={iterations}\tsamples={samples}\tmedian_ns_per_iter={:.3}\taxes={}\tinstances={}\tchecksum={checksum:016x}",
        values[values.len() / 2],
        font.axes().len(),
        font.named_instances().len(),
    );
}

fn attributes(font: &FontRef<'_>, args: &mut impl Iterator<Item = String>) {
    let (iterations, samples) = repeated_args(args);
    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0_u64;
    for _ in 0..samples {
        let start = Instant::now();
        for _ in 0..iterations {
            let value = font.attributes();
            checksum = checksum
                .wrapping_add(u64::from(value.stretch.ratio().to_bits()))
                .wrapping_add(u64::from(value.weight.value().to_bits()))
                .wrapping_add(match value.style {
                    skrifa::attribute::Style::Normal => 0,
                    skrifa::attribute::Style::Italic => 1,
                    skrifa::attribute::Style::Oblique(angle) => 2_u64.wrapping_add(
                        angle
                            .map(|item| u64::from(item.to_bits()))
                            .unwrap_or_default(),
                    ),
                });
            black_box(value);
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
    }
    values.sort_by(f64::total_cmp);
    let value = font.attributes();
    println!(
        "engine=skrifa\tmode=attributes\titerations={iterations}\tsamples={samples}\tmedian_ns_per_iter={:.3}\tstretch={}\tstyle={:?}\tweight={}\tchecksum={checksum:016x}",
        values[values.len() / 2],
        value.stretch.ratio(),
        value.style,
        value.weight.value(),
    );
}

fn glyph_name(font: &FontRef<'_>, glyph_id: u32, args: &mut impl Iterator<Item = String>) {
    let (iterations, samples) = repeated_args(args);
    let names = font.glyph_names();
    let gid = GlyphId::new(glyph_id);
    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0_u64;
    for _ in 0..samples {
        let start = Instant::now();
        for _ in 0..iterations {
            let value = names.get(gid).unwrap_or_else(|| fail("missing glyph name"));
            for byte in value.as_bytes() {
                checksum = checksum.wrapping_mul(0x100000001b3) ^ u64::from(*byte);
            }
            black_box(&value);
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
    }
    values.sort_by(f64::total_cmp);
    let value = names.get(gid).unwrap_or_else(|| fail("missing glyph name"));
    println!(
        "engine=skrifa\tmode=glyph-name\titerations={iterations}\tsamples={samples}\tmedian_ns_per_iter={:.3}\tvalue={:?}\tsource={:?}\tsynthesized={}\tchecksum={checksum:016x}",
        values[values.len() / 2],
        value.as_str(),
        names.source(),
        value.is_synthesized(),
    );
}

fn family_name(font: &FontRef<'_>, args: &mut impl Iterator<Item = String>) {
    let (iterations, samples) = repeated_args(args);
    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0_u64;
    for _ in 0..samples {
        let start = Instant::now();
        for _ in 0..iterations {
            let value = font
                .localized_strings(StringId::FAMILY_NAME)
                .english_or_first()
                .map(|item| item.to_string())
                .unwrap_or_default();
            for byte in value.as_bytes() {
                checksum = checksum.wrapping_mul(0x100000001b3) ^ u64::from(*byte);
            }
            black_box(&value);
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
    }
    values.sort_by(f64::total_cmp);
    let value = font
        .localized_strings(StringId::FAMILY_NAME)
        .english_or_first()
        .map(|item| item.to_string())
        .unwrap_or_default();
    println!(
        "engine=skrifa\tmode=family-name\titerations={iterations}\tsamples={samples}\tmedian_ns_per_iter={:.3}\tvalue={value:?}\tchecksum={checksum:016x}",
        values[values.len() / 2],
    );
}

fn global_metrics(font: &FontRef<'_>, args: &mut impl Iterator<Item = String>) {
    let (iterations, samples) = repeated_args(args);
    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0_u64;
    for _ in 0..samples {
        let start = Instant::now();
        for _ in 0..iterations {
            let metrics = font.metrics(Size::unscaled(), LocationRef::default());
            checksum = checksum
                .wrapping_add(u64::from(metrics.units_per_em))
                .wrapping_add(u64::from(metrics.glyph_count))
                .wrapping_add(u64::from(metrics.is_monospace))
                .wrapping_add(u64::from(metrics.italic_angle.to_bits()))
                .wrapping_add(u64::from(metrics.ascent.to_bits()))
                .wrapping_add(u64::from(metrics.descent.to_bits()))
                .wrapping_add(u64::from(metrics.leading.to_bits()))
                .wrapping_add(option_bits(metrics.cap_height))
                .wrapping_add(option_bits(metrics.x_height))
                .wrapping_add(option_bits(metrics.average_width))
                .wrapping_add(option_bits(metrics.max_width))
                .wrapping_add(option_decoration_bits(metrics.underline))
                .wrapping_add(option_decoration_bits(metrics.strikeout))
                .wrapping_add(option_bounds_bits(metrics.bounds));
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
        black_box(checksum);
    }
    values.sort_by(f64::total_cmp);
    let metrics = font.metrics(Size::unscaled(), LocationRef::default());
    let bounds = metrics.bounds.unwrap_or_default();
    println!(
        "engine=skrifa\tmode=global-metrics\titerations={iterations}\tsamples={samples}\tmedian_ns_per_iter={:.3}\tupem={}\tglyphs={}\tascent={}\tdescent={}\tleading={}\tmonospace={}\titalic={}\tcap={}\txheight={}\taverage={}\tmax={}\tbounds={},{},{},{}\tchecksum={checksum:016x}",
        values[values.len() / 2],
        metrics.units_per_em,
        metrics.glyph_count,
        metrics.ascent,
        metrics.descent,
        metrics.leading,
        metrics.is_monospace,
        metrics.italic_angle,
        metrics.cap_height.unwrap_or_default(),
        metrics.x_height.unwrap_or_default(),
        metrics.average_width.unwrap_or_default(),
        metrics.max_width.unwrap_or_default(),
        bounds.x_min, bounds.y_min, bounds.x_max, bounds.y_max,
    );
}

fn option_bits(value: Option<f32>) -> u64 {
    value
        .map(|item| u64::from(item.to_bits()))
        .unwrap_or_default()
}

fn option_decoration_bits(value: Option<skrifa::metrics::Decoration>) -> u64 {
    value
        .map(|item| u64::from(item.offset.to_bits()) + u64::from(item.thickness.to_bits()))
        .unwrap_or_default()
}

fn option_bounds_bits(value: Option<skrifa::metrics::BoundingBox>) -> u64 {
    value
        .map(|item| {
            u64::from(item.x_min.to_bits())
                + u64::from(item.y_min.to_bits())
                + u64::from(item.x_max.to_bits())
                + u64::from(item.y_max.to_bits())
        })
        .unwrap_or_default()
}

fn bitmap_bench(font: &FontRef<'_>, glyph_id: u32, args: &mut impl Iterator<Item = String>) {
    let size: f32 = args
        .next()
        .and_then(|v| v.parse().ok())
        .unwrap_or_else(|| fail("invalid size"));
    let (iterations, samples) = repeated_args(args);
    let strikes = font.bitmap_strikes();
    let gid = GlyphId::new(glyph_id);
    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0_u64;
    for _ in 0..samples {
        let start = Instant::now();
        for _ in 0..iterations {
            let glyph = strikes
                .glyph_for_size(Size::new(size), gid)
                .unwrap_or_else(|| fail("missing bitmap glyph"));
            checksum = checksum.wrapping_add(u64::from(glyph.width) + u64::from(glyph.height));
            black_box(glyph.data);
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
    }
    values.sort_by(f64::total_cmp);
    println!("engine=skrifa\tmode=bitmap-bench\titerations={iterations}\tsamples={samples}\tmedian_ns_per_iter={:.3}\tchecksum={checksum:016x}", values[values.len()/2]);
}

fn bitmap_summary(font: &FontRef<'_>, glyph_id: u32, args: &mut impl Iterator<Item = String>) {
    let size: f32 = args
        .next()
        .unwrap_or_else(|| fail("missing size"))
        .parse()
        .unwrap_or_else(|_| fail("invalid size"));
    let (iterations, samples) = repeated_args(args);
    let strikes = font.bitmap_strikes();
    let gid = GlyphId::new(glyph_id);
    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0_u64;
    for _ in 0..samples {
        let start = Instant::now();
        for _ in 0..iterations {
            let glyph = strikes
                .glyph_for_size(Size::new(size), gid)
                .unwrap_or_else(|| fail("missing bitmap glyph"));
            let len = match &glyph.data {
                BitmapData::Bgra(data) | BitmapData::Png(data) => data.len(),
                BitmapData::Mask(mask) => mask.data.len(),
            };
            checksum = checksum
                .wrapping_add(u64::from(glyph.width))
                .wrapping_add(u64::from(glyph.height))
                .wrapping_add(len as u64);
            black_box(glyph.data);
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
    }
    values.sort_by(f64::total_cmp);
    println!(
        "engine=skrifa\tmode=bitmap-summary\titerations={iterations}\tsamples={samples}\tmedian_ns_per_iter={:.3}\tchecksum={checksum:016x}",
        values[values.len() / 2],
    );
}

fn repeated_args(args: &mut impl Iterator<Item = String>) -> (usize, usize) {
    let iterations = args
        .next()
        .and_then(|v| v.parse().ok())
        .unwrap_or_else(|| fail("invalid iterations"));
    let samples = args
        .next()
        .and_then(|v| v.parse().ok())
        .unwrap_or_else(|| fail("invalid samples"));
    if iterations == 0 || samples == 0 || args.next().is_some() {
        fail("invalid repeated arguments");
    }
    (iterations, samples)
}

fn varied_repeated_args(
    args: &mut impl Iterator<Item = String>,
) -> (Vec<NormalizedCoord>, usize, usize) {
    let raw_coords = args
        .next()
        .unwrap_or_else(|| fail("missing normalized coordinates"));
    let coords = raw_coords
        .split(',')
        .map(|raw| {
            let value: f32 = raw
                .trim()
                .parse()
                .unwrap_or_else(|_| fail("invalid normalized coordinate"));
            if !value.is_finite() || !(-1.0..=1.0).contains(&value) {
                fail("normalized coordinate outside [-1, 1]");
            }
            NormalizedCoord::from_f32(value)
        })
        .collect();
    let (iterations, samples) = repeated_args(args);
    (coords, iterations, samples)
}

fn metrics(font: &FontRef<'_>, glyph_id: u32, args: &mut impl Iterator<Item = String>) {
    let (iterations, samples) = repeated_args(args);
    let metrics = font.glyph_metrics(Size::unscaled(), LocationRef::default());
    let gid = GlyphId::new(glyph_id);
    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0_u64;
    for _ in 0..samples {
        let start = Instant::now();
        for _ in 0..iterations {
            let advance = metrics.advance_width(gid).unwrap_or_default();
            let lsb = metrics.left_side_bearing(gid).unwrap_or_default();
            // Match glyph-bench's integer unscaled-metrics digest so the
            // matrix can compare behavior rather than merely recording two
            // unrelated benchmark consumers. OpenType design metrics are
            // integral even though Skrifa exposes them as f32.
            checksum = checksum
                .wrapping_add(((advance as u16 as u64) << 16) | u64::from(lsb as i16 as u16));
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
        black_box(checksum);
    }
    values.sort_by(f64::total_cmp);
    println!("engine=skrifa\tmode=metrics\titerations={iterations}\tsamples={samples}\tmedian_ns_per_iter={:.3}\tchecksum={checksum:016x}", values[values.len()/2]);
}

fn bounds(font: &FontRef<'_>, glyph_id: u32, args: &mut impl Iterator<Item = String>) {
    let (iterations, samples) = repeated_args(args);
    let metrics = font.glyph_metrics(Size::unscaled(), LocationRef::default());
    let gid = GlyphId::new(glyph_id);
    let expected = metrics
        .bounds(gid)
        .unwrap_or_else(|| fail("missing glyph bounds"));
    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0_u64;
    for _ in 0..samples {
        let start = Instant::now();
        for _ in 0..iterations {
            let bounds = metrics
                .bounds(gid)
                .unwrap_or_else(|| fail("missing glyph bounds"));
            checksum = checksum
                .wrapping_add(u64::from(bounds.x_min.to_bits()))
                .wrapping_add(u64::from(bounds.y_min.to_bits()))
                .wrapping_add(u64::from(bounds.x_max.to_bits()))
                .wrapping_add(u64::from(bounds.y_max.to_bits()));
            black_box(bounds);
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
    }
    values.sort_by(f64::total_cmp);
    println!(
        "engine=skrifa\tmode=bounds\titerations={iterations}\tsamples={samples}\tmedian_ns_per_iter={:.3}\tbounds={},{},{},{}\tchecksum={checksum:016x}",
        values[values.len() / 2],
        expected.x_min,
        expected.y_min,
        expected.x_max,
        expected.y_max,
    );
}

fn charmap(font: &FontRef<'_>, codepoint: u32, args: &mut impl Iterator<Item = String>) {
    let (iterations, samples) = repeated_args(args);
    let charmap = font.charmap();
    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0_u64;
    for _ in 0..samples {
        let start = Instant::now();
        for _ in 0..iterations {
            let glyph = charmap
                .map(codepoint)
                .map(|g| g.to_u32())
                .unwrap_or_default();
            checksum = checksum.wrapping_add(u64::from(glyph));
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
        black_box(checksum);
    }
    values.sort_by(f64::total_cmp);
    println!("engine=skrifa\tmode=charmap\titerations={iterations}\tsamples={samples}\tmedian_ns_per_iter={:.3}\tchecksum={checksum:016x}", values[values.len()/2]);
}

fn bitmap(font: &FontRef<'_>, glyph_id: u32, args: &mut impl Iterator<Item = String>) {
    let size: f32 = args
        .next()
        .unwrap_or_else(|| fail("missing size"))
        .parse()
        .unwrap_or_else(|_| fail("invalid size"));
    if args.next().is_some() {
        fail("unexpected argument");
    }
    let glyph = font
        .bitmap_strikes()
        .glyph_for_size(Size::new(size), GlyphId::new(glyph_id))
        .unwrap_or_else(|| fail("missing bitmap glyph"));
    let data = match glyph.data {
        BitmapData::Bgra(data) => data,
        BitmapData::Png(_) => fail("selected PNG instead of BGRA"),
        BitmapData::Mask(_) => fail("selected mask instead of BGRA"),
    };
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in data {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    println!(
        "bgra\t{}\t{}\t{}\t{}\t{}\t{:016x}",
        glyph.width,
        glyph.height,
        glyph.inner_bearing_x,
        glyph.inner_bearing_y,
        data.len(),
        hash,
    );
}

fn outline(font: &FontRef<'_>, glyph_id: u32, args: &mut impl Iterator<Item = String>) {
    let (iterations, samples) = repeated_args(args);
    outline_at_location(font, glyph_id, &[], iterations, samples);
}

fn outline_at(font: &FontRef<'_>, glyph_id: u32, args: &mut impl Iterator<Item = String>) {
    let (coords, iterations, samples) = varied_repeated_args(args);
    outline_at_location(font, glyph_id, &coords, iterations, samples);
}

fn outline_at_location(
    font: &FontRef<'_>,
    glyph_id: u32,
    coords: &[NormalizedCoord],
    iterations: usize,
    samples: usize,
) {
    let glyph = font
        .outline_glyphs()
        .get(GlyphId::new(glyph_id))
        .unwrap_or_else(|| fail("missing outline glyph"));
    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0_u64;
    let mut commands = 0_usize;
    for _ in 0..samples {
        for _ in 0..3 {
            let mut pen = HashPen::default();
            glyph
                .draw(unscaled_settings(coords), &mut pen)
                .unwrap_or_else(|_| fail("cannot draw outline"));
            checksum = pen.hash;
            commands = pen.commands;
        }
        let start = Instant::now();
        let mut batch_hash = 0_u64;
        for _ in 0..iterations {
            let mut pen = HashPen::default();
            glyph
                .draw(unscaled_settings(coords), &mut pen)
                .unwrap_or_else(|_| fail("cannot draw outline"));
            batch_hash = batch_hash.wrapping_add(pen.hash);
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
        black_box(batch_hash);
    }
    values.sort_by(f64::total_cmp);
    println!(
        "engine=skrifa\tmode=outline\titerations={iterations}\tsamples={samples}\tmedian_ns_per_iter={:.3}\tcommands={commands}\tchecksum={checksum:016x}",
        values[values.len() / 2],
    );
}

fn outline_reuse(font: &FontRef<'_>, glyph_id: u32, args: &mut impl Iterator<Item = String>) {
    let (iterations, samples) = repeated_args(args);
    outline_reuse_at_location(font, glyph_id, &[], iterations, samples);
}

fn outline_reuse_at(font: &FontRef<'_>, glyph_id: u32, args: &mut impl Iterator<Item = String>) {
    let (coords, iterations, samples) = varied_repeated_args(args);
    outline_reuse_at_location(font, glyph_id, &coords, iterations, samples);
}

fn outline_reuse_at_location(
    font: &FontRef<'_>,
    glyph_id: u32,
    coords: &[NormalizedCoord],
    iterations: usize,
    samples: usize,
) {
    let glyph = font
        .outline_glyphs()
        .get(GlyphId::new(glyph_id))
        .unwrap_or_else(|| fail("missing outline glyph"));
    // Exercise Skrifa's documented caller-owned temporary-memory contract.
    // HashPen itself is allocation-free and is reset per iteration just like
    // Cangjie's reusable command buffer is logically cleared before a draw.
    let mut memory = vec![0_u8; glyph.draw_memory_size(Hinting::None)];
    let mut values = Vec::with_capacity(samples);
    let mut checksum = 0_u64;
    let mut commands = 0_usize;
    for _ in 0..samples {
        for _ in 0..3 {
            let mut pen = HashPen::default();
            glyph
                .draw(unscaled_settings_with_memory(coords, &mut memory), &mut pen)
                .unwrap_or_else(|_| fail("cannot draw outline"));
            checksum = pen.hash;
            commands = pen.commands;
        }
        let start = Instant::now();
        let mut batch_hash = 0_u64;
        for _ in 0..iterations {
            let mut pen = HashPen::default();
            glyph
                .draw(unscaled_settings_with_memory(coords, &mut memory), &mut pen)
                .unwrap_or_else(|_| fail("cannot draw outline"));
            batch_hash = batch_hash.wrapping_add(pen.hash);
        }
        values.push(start.elapsed().as_nanos() as f64 / iterations as f64);
        black_box(batch_hash);
    }
    values.sort_by(f64::total_cmp);
    println!(
        "engine=skrifa	mode=outline-reuse	iterations={iterations}	samples={samples}	median_ns_per_iter={:.3}	commands={commands}	checksum={checksum:016x}",
        values[values.len() / 2],
    );
}

fn unscaled_settings(coords: &[NormalizedCoord]) -> DrawSettings<'_> {
    DrawSettings::unhinted(Size::unscaled(), LocationRef::new(coords))
}

fn unscaled_settings_with_memory<'a>(
    coords: &'a [NormalizedCoord],
    memory: &'a mut [u8],
) -> DrawSettings<'a> {
    DrawSettings::unhinted(Size::unscaled(), LocationRef::new(coords)).with_memory(Some(memory))
}

#[derive(Default)]
struct HashPen {
    hash: u64,
    commands: usize,
}

impl HashPen {
    fn command(&mut self, tag: u8, values: &[f32]) {
        self.hash ^= u64::from(tag);
        self.hash = self.hash.wrapping_mul(0x100000001b3);
        for value in values {
            for byte in value.to_bits().to_le_bytes() {
                self.hash ^= u64::from(byte);
                self.hash = self.hash.wrapping_mul(0x100000001b3);
            }
        }
        self.commands += 1;
    }
}

impl OutlinePen for HashPen {
    fn move_to(&mut self, x: f32, y: f32) {
        self.command(1, &[x, y]);
    }
    fn line_to(&mut self, x: f32, y: f32) {
        self.command(2, &[x, y]);
    }
    fn quad_to(&mut self, cx: f32, cy: f32, x: f32, y: f32) {
        self.command(3, &[cx, cy, x, y]);
    }
    fn curve_to(&mut self, cx0: f32, cy0: f32, cx1: f32, cy1: f32, x: f32, y: f32) {
        self.command(4, &[cx0, cy0, cx1, cy1, x, y]);
    }
    fn close(&mut self) {
        self.command(5, &[]);
    }
}
