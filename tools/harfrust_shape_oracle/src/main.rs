//! Small in-process HarfRust benchmark used by Cangjie's comparison audit.
//!
//! The normal `shape-bench --engine harfrust` path intentionally drives the
//! reference CLI because that exposes its complete text output for parity
//! checks. This executable instead links HarfRust directly, keeps its font,
//! shaping data, shape plans, and Unicode buffer alive across iterations, and
//! times only library calls plus a constant-size result consumer.

use harfrust::{
    Direction, FontRef, GlyphBuffer, ShapeOptions, ShapePlan, ShapePlanKey, Shaper, ShaperData,
    UnicodeBuffer,
};
use std::{env, fs, hint::black_box, process, time::Instant};

#[derive(Clone, Copy, Debug)]
enum RequestedDirection {
    Auto,
    Explicit(Direction),
}

#[derive(Default)]
struct PlanCache {
    plans: Vec<ShapePlan>,
}

impl PlanCache {
    fn get<'a>(&'a mut self, shaper: &Shaper<'_>, buffer: &UnicodeBuffer) -> &'a ShapePlan {
        let language = buffer.language();
        let key = ShapePlanKey::new(Some(buffer.script()), buffer.direction())
            .language(language.as_ref());
        if let Some(index) = self.plans.iter().position(|plan| key.matches(plan)) {
            return &self.plans[index];
        }
        self.plans.push(ShapePlan::new(
            shaper,
            buffer.direction(),
            Some(buffer.script()),
            language.as_ref(),
            &[],
        ));
        self.plans.last().unwrap()
    }
}

fn main() {
    if let Err(error) = run() {
        eprintln!("error: {error}");
        process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let mut args = env::args().skip(1);
    let font_path = args.next().ok_or_else(usage)?;
    let text_path = args.next().ok_or_else(usage)?;
    let iterations = parse_positive(&args.next().ok_or_else(usage)?, "iterations")?;
    let sample_count = parse_positive(&args.next().ok_or_else(usage)?, "samples")?;
    let direction_text = args.next().unwrap_or_else(|| "auto".to_owned());
    let direction = parse_direction(&direction_text)?;
    if args.next().is_some() {
        return Err(usage());
    }

    let font_data = fs::read(&font_path).map_err(|error| error.to_string())?;
    let text_data = fs::read_to_string(&text_path).map_err(|error| error.to_string())?;
    let lines = split_lines(&text_data);
    if lines.is_empty() {
        return Err("text input contains no non-empty lines".to_owned());
    }
    let text_bytes = lines.iter().map(|line| line.len()).sum::<usize>();

    let font = FontRef::from_index(&font_data, 0).map_err(|error| error.to_string())?;
    let data = ShaperData::new(&font);
    let shaper = data.shaper(&font).build();
    let mut plans = PlanCache::default();
    let mut shared_buffer = Some(UnicodeBuffer::new());
    let max_line_scalars = lines
        .iter()
        .map(|line| line.chars().count())
        .max()
        .unwrap_or(0);
    assert!(shared_buffer.as_mut().unwrap().reserve(max_line_scalars));

    // Establish and then recheck the complete output outside timing. Measured
    // iterations consume only slice identities and lengths, avoiding a hash
    // implementation difference between the Rust and Zig runners.
    let (checksum, glyphs_per_iteration) =
        shape_and_checksum(&shaper, &mut plans, &mut shared_buffer, &lines, direction);
    for _ in 0..2 {
        let (warm_checksum, warm_glyphs) =
            shape_and_checksum(&shaper, &mut plans, &mut shared_buffer, &lines, direction);
        if warm_checksum != checksum || warm_glyphs != glyphs_per_iteration {
            return Err("unstable HarfRust output during warmup".to_owned());
        }
    }

    let mut samples = Vec::with_capacity(sample_count);
    for _ in 0..sample_count {
        let start = Instant::now();
        let mut sample_glyphs = 0usize;
        for _ in 0..iterations {
            for line in &lines {
                let glyphs = shape_line(
                    &shaper,
                    &mut plans,
                    shared_buffer.take().unwrap(),
                    line,
                    direction,
                );
                sample_glyphs += glyphs.len();
                black_box(glyphs.glyph_infos());
                black_box(glyphs.glyph_positions());
                shared_buffer = Some(glyphs.clear());
            }
        }
        let elapsed = start.elapsed().as_nanos();
        if sample_glyphs != glyphs_per_iteration * iterations {
            return Err("unstable HarfRust glyph count during measurement".to_owned());
        }
        samples.push(elapsed as f64 / iterations as f64);
    }
    samples.sort_by(f64::total_cmp);

    let (final_checksum, final_glyphs) =
        shape_and_checksum(&shaper, &mut plans, &mut shared_buffer, &lines, direction);
    if final_checksum != checksum || final_glyphs != glyphs_per_iteration {
        return Err("unstable HarfRust output after measurement".to_owned());
    }

    let median_ns = samples[samples.len() / 2];
    let ns_per_glyph = if glyphs_per_iteration == 0 {
        0.0
    } else {
        median_ns / glyphs_per_iteration as f64
    };
    println!(
        "engine=harfrust-library\tdirection={direction_text}\ttext_bytes={text_bytes}\tlines={}\titerations={iterations}\tsamples={sample_count}\tmedian_ns_per_iter={median_ns:.3}\tmedian_ns_per_glyph={ns_per_glyph:.3}\tglyphs={glyphs_per_iteration}\tchecksum={checksum:016x}",
        lines.len(),
    );
    Ok(())
}

fn shape_line<'a>(
    shaper: &Shaper<'a>,
    plans: &mut PlanCache,
    mut buffer: UnicodeBuffer,
    text: &str,
    direction: RequestedDirection,
) -> GlyphBuffer {
    buffer.push_str(text);
    if let RequestedDirection::Explicit(value) = direction {
        buffer.set_direction(value);
    }
    buffer.guess_segment_properties();
    let plan = plans.get(shaper, &buffer);
    shaper.shape(buffer, ShapeOptions::new().plan(Some(plan)))
}

fn shape_and_checksum(
    shaper: &Shaper<'_>,
    plans: &mut PlanCache,
    shared_buffer: &mut Option<UnicodeBuffer>,
    lines: &[&str],
    direction: RequestedDirection,
) -> (u64, usize) {
    let mut checksum = FNV_OFFSET;
    let mut glyph_count = 0usize;
    for line in lines {
        let glyphs = shape_line(
            shaper,
            plans,
            shared_buffer.take().unwrap(),
            line,
            direction,
        );
        glyph_count += glyphs.len();
        checksum = hash_glyphs(checksum, &glyphs);
        *shared_buffer = Some(glyphs.clear());
    }
    (checksum, glyph_count)
}

const FNV_OFFSET: u64 = 0xcbf2_9ce4_8422_2325;
const FNV_PRIME: u64 = 0x0000_0100_0000_01b3;

fn hash_glyphs(mut hash: u64, glyphs: &GlyphBuffer) -> u64 {
    for (info, position) in glyphs.glyph_infos().iter().zip(glyphs.glyph_positions()) {
        for value in [
            info.glyph_id,
            info.cluster,
            position.x_advance as u32,
            position.y_advance as u32,
            position.x_offset as u32,
            position.y_offset as u32,
        ] {
            for byte in value.to_le_bytes() {
                hash ^= u64::from(byte);
                hash = hash.wrapping_mul(FNV_PRIME);
            }
        }
    }
    hash
}

fn split_lines(text: &str) -> Vec<&str> {
    let trimmed = text.trim_matches(['\n', '\r']);
    let mut lines = trimmed
        .split('\n')
        .map(|line| line.trim_end_matches('\r'))
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>();
    if lines.is_empty() && !text.is_empty() {
        lines.push(text);
    }
    lines
}

fn parse_positive(value: &str, label: &str) -> Result<usize, String> {
    let parsed = value
        .parse::<usize>()
        .map_err(|_| format!("invalid {label}: {value}"))?;
    if parsed == 0 {
        return Err(format!("{label} must be positive"));
    }
    Ok(parsed)
}

fn parse_direction(value: &str) -> Result<RequestedDirection, String> {
    match value {
        "auto" => Ok(RequestedDirection::Auto),
        "ltr" => Ok(RequestedDirection::Explicit(Direction::LeftToRight)),
        "rtl" => Ok(RequestedDirection::Explicit(Direction::RightToLeft)),
        "ttb" => Ok(RequestedDirection::Explicit(Direction::TopToBottom)),
        "btt" => Ok(RequestedDirection::Explicit(Direction::BottomToTop)),
        _ => Err(format!("invalid direction: {value}")),
    }
}

fn usage() -> String {
    "usage: harfrust-shape-oracle FONT TEXT ITERATIONS SAMPLES [auto|ltr|rtl|ttb|btt]".to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn line_splitting_matches_shape_bench_corpus_rules() {
        assert_eq!(split_lines("a\r\n\nb\n"), ["a", "b"]);
        assert_eq!(split_lines("x"), ["x"]);
    }

    #[test]
    fn direction_parser_supports_all_benchmark_directions() {
        assert!(matches!(
            parse_direction("rtl"),
            Ok(RequestedDirection::Explicit(Direction::RightToLeft))
        ));
        assert!(matches!(
            parse_direction("auto"),
            Ok(RequestedDirection::Auto)
        ));
        assert!(parse_direction("sideways").is_err());
    }
}
