use skrifa::{bitmap::BitmapData, prelude::Size, FontRef, GlyphId, MetadataProvider};
use std::{env, fs, process};

fn fail(message: &str) -> ! {
    eprintln!("fontations bitmap oracle: {message}");
    process::exit(1);
}

fn main() {
    let mut args = env::args().skip(1);
    let path = args.next().unwrap_or_else(|| fail("missing font path"));
    let glyph_id: u32 = args
        .next()
        .unwrap_or_else(|| fail("missing glyph id"))
        .parse()
        .unwrap_or_else(|_| fail("invalid glyph id"));
    let size: f32 = args
        .next()
        .unwrap_or_else(|| fail("missing size"))
        .parse()
        .unwrap_or_else(|_| fail("invalid size"));
    if args.next().is_some() {
        fail("unexpected argument");
    }

    let bytes = fs::read(path).unwrap_or_else(|_| fail("cannot read font"));
    let font = FontRef::new(&bytes).unwrap_or_else(|_| fail("cannot parse font"));
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
