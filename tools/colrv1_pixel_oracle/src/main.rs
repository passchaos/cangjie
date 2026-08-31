use skrifa::{
    color::{Brush, ColorGlyphFormat, ColorPainter, CompositeMode, Extend, Transform},
    instance::{LocationRef, NormalizedCoord, Size},
    outline::{DrawSettings, OutlinePen},
    raw::types::BoundingBox,
    FontRef, GlyphId, MetadataProvider,
};
use std::{env, fs, hint::black_box, process, time::Instant};
use tiny_skia::{
    BlendMode, Color, ColorSpace, FillRule, GradientStop, LinearGradient, Mask, Paint, Path,
    PathBuilder, Pixmap, PixmapPaint, Point, RadialGradient, Rect, SpreadMode, SweepGradient,
    Transform as SkTransform,
};

const FNV_OFFSET: u64 = 0xcbf29ce484222325;
const FNV_PRIME: u64 = 0x100000001b3;
const MAX_DEPTH: usize = 64;
fn fail(m: impl std::fmt::Display) -> ! {
    eprintln!("colrv1 pixel oracle: {m}");
    process::exit(1)
}
fn p<T: std::str::FromStr>(v: Option<String>, n: &str) -> T {
    v.unwrap_or_else(|| fail(format!("missing {n}")))
        .parse()
        .unwrap_or_else(|_| fail(format!("invalid {n}")))
}
struct Opt {
    font: String,
    gid: u32,
    size: f32,
    w: u32,
    h: u32,
    x: f32,
    y: f32,
    palette: u16,
    coords: Vec<NormalizedCoord>,
    iters: usize,
    samples: usize,
    out: Option<String>,
}
fn options() -> Opt {
    let mut a = env::args().skip(1);
    let font = a.next().unwrap_or_else(|| fail("missing font"));
    let gid = p(a.next(), "gid");
    let size = p(a.next(), "size");
    let w = p(a.next(), "width");
    let h = p(a.next(), "height");
    let x = p(a.next(), "x");
    let y = p(a.next(), "baseline");
    let palette = p(a.next(), "palette");
    let cs = a.next().unwrap_or_else(|| fail("missing coords"));
    let coords = if cs == "-" {
        vec![]
    } else {
        cs.split(',')
            .map(|v| {
                let x: f32 = v.parse().unwrap_or_else(|_| fail("bad coord"));
                if !(-1.0..=1.0).contains(&x) {
                    fail("coord outside [-1,1]")
                }
                NormalizedCoord::from_f32(x)
            })
            .collect()
    };
    let iters = p(a.next(), "iterations");
    let samples = p(a.next(), "samples");
    let out = a.next();
    if a.next().is_some() || w == 0 || h == 0 || iters == 0 || samples == 0 {
        fail("invalid arguments")
    }
    Opt {
        font,
        gid,
        size,
        w,
        h,
        x,
        y,
        palette,
        coords,
        iters,
        samples,
        out,
    }
}
fn main() {
    let o = options();
    let bytes = fs::read(&o.font).unwrap_or_else(|e| fail(e));
    let font = FontRef::new(&bytes).unwrap_or_else(|e| fail(e));
    let glyph = font
        .color_glyphs()
        .get_with_format(GlyphId::new(o.gid), ColorGlyphFormat::ColrV1)
        .unwrap_or_else(|| fail("missing COLRv1 glyph"));
    let upem = font
        .metrics(Size::unscaled(), LocationRef::default())
        .units_per_em;
    let palettes = font.color_palettes();
    let palette = palettes
        .get(o.palette)
        .unwrap_or_else(|| fail("missing palette"));
    let colors = palette.colors();
    let mut times = Vec::with_capacity(o.samples);
    let mut output = vec![];
    for _ in 0..o.samples {
        let start = Instant::now();
        for i in 0..o.iters {
            let mut painter = Painter::new(
                &font,
                colors,
                &o.coords,
                o.w,
                o.h,
                o.size / upem as f32,
                o.x,
                o.y,
            );
            glyph
                .paint(o.coords.as_slice(), &mut painter)
                .unwrap_or_else(|e| fail(e));
            let pixels = painter.finish().unwrap_or_else(|e| fail(e));
            black_box(hash(&pixels));
            if i + 1 == o.iters {
                output = pixels
            }
        }
        times.push(start.elapsed().as_nanos() as f64 / o.iters as f64)
    }
    times.sort_by(f64::total_cmp);
    if let Some(path) = o.out {
        fs::write(path, &output).unwrap_or_else(|e| fail(e))
    }
    let b = bounds(&output, o.w, o.h).unwrap_or((0, 0, 0, 0));
    println!("engine=skrifa-tiny-skia\tformat=premul-rgba8\twidth={}\theight={}\tleft={}\ttop={}\tright={}\tbottom={}\tchecksum={:016x}\tmedian_ns_per_iter={:.3}",o.w,o.h,b.0,b.1,b.2,b.3,hash(&output),times[times.len()/2]);
}
struct Layer {
    pixmap: Pixmap,
    blend: BlendMode,
}
struct Painter<'a> {
    font: &'a FontRef<'a>,
    palette: &'a [skrifa::color::Color],
    location: &'a [NormalizedCoord],
    w: u32,
    h: u32,
    root: SkTransform,
    transforms: Vec<SkTransform>,
    clips: Vec<Mask>,
    layers: Vec<Layer>,
    error: Option<String>,
}
impl<'a> Painter<'a> {
    fn new(
        font: &'a FontRef<'a>,
        palette: &'a [skrifa::color::Color],
        location: &'a [NormalizedCoord],
        w: u32,
        h: u32,
        s: f32,
        x: f32,
        y: f32,
    ) -> Self {
        Self {
            font,
            palette,
            location,
            w,
            h,
            root: SkTransform::from_row(s, 0., 0., -s, x, y),
            transforms: vec![SkTransform::identity()],
            clips: vec![],
            layers: vec![Layer {
                pixmap: Pixmap::new(w, h).unwrap(),
                blend: BlendMode::SourceOver,
            }],
            error: None,
        }
    }
    fn finish(mut self) -> Result<Vec<u8>, String> {
        if let Some(e) = self.error.take() {
            return Err(e);
        }
        if self.transforms.len() != 1 || !self.clips.is_empty() || self.layers.len() != 1 {
            return Err("unbalanced stack".into());
        }
        Ok(self.layers.pop().unwrap().pixmap.take())
    }
    fn new_layer(&self, blend: BlendMode) -> Layer {
        Layer {
            pixmap: Pixmap::new(self.w, self.h).unwrap(),
            blend,
        }
    }
    fn source_over_byte_domain(dst: &mut [u8], src: &[u8]) {
        // The oracle output is premultiplied RGBA8. Keep isolated SrcOver
        // group merges in byte space: tiny-skia's generic pixmap compositor
        // otherwise applies a color-space conversion not requested by the
        // ColorPainter layer contract.
        for (d, s) in dst.chunks_exact_mut(4).zip(src.chunks_exact(4)) {
            let inverse_alpha = 255 - s[3] as u32;
            for channel in 0..4 {
                d[channel] =
                    (s[channel] as u32 + (d[channel] as u32 * inverse_alpha) / 255).min(255) as u8;
            }
        }
    }
    fn local(&self) -> SkTransform {
        *self.transforms.last().unwrap()
    }
    fn ctm(&self) -> SkTransform {
        self.root.pre_concat(self.local())
    }
    fn err(&mut self, s: impl Into<String>) {
        if self.error.is_none() {
            self.error = Some(s.into())
        }
    }
    fn outline(&mut self, gid: GlyphId) -> Option<Path> {
        let Some(g) = self.font.outline_glyphs().get(gid) else {
            self.err("missing outline");
            return None;
        };
        let mut pen = Pen::default();
        if let Err(e) = g.draw(
            DrawSettings::unhinted(Size::unscaled(), self.location),
            &mut pen,
        ) {
            self.err(format!("outline: {e:?}"));
            return None;
        }
        pen.b.finish()
    }
    fn push_path_clip(&mut self, path: &Path) {
        if self.clips.len() >= MAX_DEPTH {
            self.err("clip depth");
            return;
        }
        let mut m = Mask::new(self.w, self.h).unwrap();
        m.fill_path(path, FillRule::Winding, true, self.ctm());
        if let Some(parent) = self.clips.last() {
            for (a, b) in m.data_mut().iter_mut().zip(parent.data()) {
                *a = ((*a as u16 * *b as u16 + 127) / 255) as u8
            }
        }
        self.clips.push(m)
    }
    fn color(&mut self, i: u16, alpha: f32) -> Option<Color> {
        let (r, g, b, a) = if i == u16::MAX {
            (255, 255, 255, 255)
        } else {
            let Some(c) = self.palette.get(i as usize) else {
                self.err("bad palette index");
                return None;
            };
            (c.red(), c.green(), c.blue(), c.alpha())
        };
        Some(Color::from_rgba8(
            r,
            g,
            b,
            ((a as f32 * alpha.clamp(0., 1.)).round() as u16).min(255) as u8,
        ))
    }
    fn stops(&mut self, s: &[skrifa::color::ColorStop]) -> Option<Vec<GradientStop>> {
        let mut v = Vec::with_capacity(s.len());
        for x in s {
            v.push(GradientStop::new(
                x.offset,
                self.color(x.palette_index, x.alpha)?,
            ))
        }
        Some(v)
    }
    fn paint(&mut self, b: Brush<'_>, brush_transform: SkTransform) -> Option<Paint<'static>> {
        let mut p = Paint::default();
        p.force_hq_pipeline = true;
        // COLRv1 gradients interpolate premultiplied colors in linear-light
        // sRGB, while solid source-over painting remains byte-domain sRGB.
        // Applying tiny-skia's gamma pipeline to solids would also gamma-blend
        // their antialiased edges and composite overlaps.
        p.colorspace = match b {
            Brush::Solid { .. } => ColorSpace::Linear,
            _ => ColorSpace::FullSRGBGamma,
        };
        p.shader = match b {
            Brush::Solid {
                palette_index,
                alpha,
            } => tiny_skia::Shader::SolidColor(self.color(palette_index, alpha)?),
            Brush::LinearGradient {
                p0,
                p1,
                color_stops,
                extend,
            } => LinearGradient::new(
                Point::from_xy(p0.x, p0.y),
                Point::from_xy(p1.x, p1.y),
                self.stops(color_stops)?,
                spread(extend),
                brush_transform,
            )?,
            Brush::RadialGradient {
                c0,
                r0,
                c1,
                r1,
                color_stops,
                extend,
            } => {
                if r0 < 0. {
                    self.err("negative radial start unsupported in bounded corpus");
                    return None;
                }
                RadialGradient::new(
                    Point::from_xy(c0.x, c0.y),
                    r0,
                    Point::from_xy(c1.x, c1.y),
                    r1,
                    self.stops(color_stops)?,
                    spread(extend),
                    brush_transform,
                )?
            }
            Brush::SweepGradient {
                c0,
                start_angle,
                end_angle,
                color_stops,
                extend,
            } => {
                // SweepGradient's unit-angle stage interprets y in its input
                // coordinate space. Reflect around the authored center before
                // the normal brush transform so clockwise Skrifa angles stay
                // clockwise after the y-up font-to-device transform.
                let flip_y = SkTransform::from_row(1.0, 0.0, 0.0, -1.0, 0.0, 2.0 * c0.y);
                SweepGradient::new(
                    Point::from_xy(c0.x, c0.y),
                    start_angle,
                    end_angle,
                    self.stops(color_stops)?,
                    spread(extend),
                    brush_transform.pre_concat(flip_y),
                )?
            }
        };
        Some(p)
    }
    fn fill_path(&mut self, path: &Path, bt: SkTransform, b: Brush<'_>) {
        let Some(p) = self.paint(b, bt) else {
            if self.error.is_none() {
                self.err("bad brush")
            }
            return;
        };
        let transform = self.ctm();
        let clip = self.clips.last();
        self.layers.last_mut().unwrap().pixmap.fill_path(
            path,
            &p,
            FillRule::Winding,
            transform,
            clip,
        )
    }
    fn fill_canvas(&mut self, b: Brush<'_>) {
        // `fill` means the current (device-space) clip, not a font-space
        // rectangle. Attach the full CTM to the brush and cover the canvas.
        let Some(p) = self.paint(b, self.ctm()) else {
            if self.error.is_none() {
                self.err("bad brush")
            }
            return;
        };
        let r = Rect::from_xywh(0., 0., self.w as f32, self.h as f32).unwrap();
        let clip = self.clips.last();
        self.layers
            .last_mut()
            .unwrap()
            .pixmap
            .fill_rect(r, &p, SkTransform::identity(), clip)
    }
}
impl ColorPainter for Painter<'_> {
    fn push_transform(&mut self, t: Transform) {
        let x = SkTransform::from_row(t.xx, t.yx, t.xy, t.yy, t.dx, t.dy);
        self.transforms.push(self.local().pre_concat(x))
    }
    fn pop_transform(&mut self) {
        if self.transforms.len() > 1 {
            self.transforms.pop();
        } else {
            self.err("transform underflow")
        }
    }
    fn push_clip_glyph(&mut self, g: GlyphId) {
        if let Some(p) = self.outline(g) {
            self.push_path_clip(&p)
        } else {
            self.clips.push(Mask::new(self.w, self.h).unwrap())
        }
    }
    fn push_clip_box(&mut self, b: BoundingBox<f32>) {
        if let Some(r) = Rect::from_ltrb(b.x_min, b.y_min, b.x_max, b.y_max) {
            self.push_path_clip(&PathBuilder::from_rect(r))
        } else {
            self.err("bad clip box")
        }
    }
    fn pop_clip(&mut self) {
        if self.clips.pop().is_none() {
            self.err("clip underflow")
        }
    }
    fn fill(&mut self, b: Brush<'_>) {
        self.fill_canvas(b)
    }
    fn fill_glyph(&mut self, g: GlyphId, t: Option<Transform>, b: Brush<'_>) {
        let Some(path) = self.outline(g) else { return };
        // tiny-skia applies the path CTM to the shader too. The constructor
        // transform therefore contains only PaintGlyph's optional additional
        // brush transform; including the current CTM here would apply it twice.
        let bt = t
            .map(|t| SkTransform::from_row(t.xx, t.yx, t.xy, t.yy, t.dx, t.dy))
            .unwrap_or_else(SkTransform::identity);
        self.fill_path(&path, bt, b)
    }
    fn push_layer(&mut self, m: CompositeMode) {
        self.layers.push(self.new_layer(blend(m)))
    }
    fn pop_layer(&mut self) {
        if self.layers.len() <= 1 {
            self.err("layer underflow");
            return;
        }
        let s = self.layers.pop().unwrap();
        if s.blend == BlendMode::SourceOver {
            Self::source_over_byte_domain(
                self.layers.last_mut().unwrap().pixmap.data_mut(),
                s.pixmap.data(),
            );
        } else {
            let p = PixmapPaint {
                blend_mode: s.blend,
                ..Default::default()
            };
            self.layers.last_mut().unwrap().pixmap.draw_pixmap(
                0,
                0,
                s.pixmap.as_ref(),
                &p,
                SkTransform::identity(),
                None,
            )
        }
    }

    fn pop_layer_with_mode(&mut self, _composite_mode: CompositeMode) {
        self.pop_layer();
    }
}
#[derive(Default)]
struct Pen {
    b: PathBuilder,
}
impl OutlinePen for Pen {
    fn move_to(&mut self, x: f32, y: f32) {
        self.b.move_to(x, y)
    }
    fn line_to(&mut self, x: f32, y: f32) {
        self.b.line_to(x, y)
    }
    fn quad_to(&mut self, cx: f32, cy: f32, x: f32, y: f32) {
        self.b.quad_to(cx, cy, x, y)
    }
    fn curve_to(&mut self, a: f32, b: f32, c: f32, d: f32, x: f32, y: f32) {
        self.b.cubic_to(a, b, c, d, x, y)
    }
    fn close(&mut self) {
        self.b.close()
    }
}
fn spread(x: Extend) -> SpreadMode {
    match x {
        Extend::Pad => SpreadMode::Pad,
        Extend::Repeat => SpreadMode::Repeat,
        Extend::Reflect => SpreadMode::Reflect,
        _ => fail("unknown extend"),
    }
}
fn blend(x: CompositeMode) -> BlendMode {
    match x {
        CompositeMode::Clear => BlendMode::Clear,
        CompositeMode::Src => BlendMode::Source,
        CompositeMode::Dest => BlendMode::Destination,
        CompositeMode::SrcOver => BlendMode::SourceOver,
        CompositeMode::DestOver => BlendMode::DestinationOver,
        CompositeMode::SrcIn => BlendMode::SourceIn,
        CompositeMode::DestIn => BlendMode::DestinationIn,
        CompositeMode::SrcOut => BlendMode::SourceOut,
        CompositeMode::DestOut => BlendMode::DestinationOut,
        CompositeMode::SrcAtop => BlendMode::SourceAtop,
        CompositeMode::DestAtop => BlendMode::DestinationAtop,
        CompositeMode::Xor => BlendMode::Xor,
        CompositeMode::Plus => BlendMode::Plus,
        CompositeMode::Screen => BlendMode::Screen,
        CompositeMode::Overlay => BlendMode::Overlay,
        CompositeMode::Darken => BlendMode::Darken,
        CompositeMode::Lighten => BlendMode::Lighten,
        CompositeMode::ColorDodge => BlendMode::ColorDodge,
        CompositeMode::ColorBurn => BlendMode::ColorBurn,
        CompositeMode::HardLight => BlendMode::HardLight,
        CompositeMode::SoftLight => BlendMode::SoftLight,
        CompositeMode::Difference => BlendMode::Difference,
        CompositeMode::Exclusion => BlendMode::Exclusion,
        CompositeMode::Multiply => BlendMode::Multiply,
        CompositeMode::HslHue => BlendMode::Hue,
        CompositeMode::HslSaturation => BlendMode::Saturation,
        CompositeMode::HslColor => BlendMode::Color,
        CompositeMode::HslLuminosity => BlendMode::Luminosity,
        _ => fail("unknown composite"),
    }
}
fn hash(x: &[u8]) -> u64 {
    x.iter()
        .fold(FNV_OFFSET, |h, b| (h ^ *b as u64).wrapping_mul(FNV_PRIME))
}
fn bounds(d: &[u8], w: u32, h: u32) -> Option<(u32, u32, u32, u32)> {
    let (mut l, mut t, mut r, mut b, mut f) = (w, h, 0, 0, false);
    for y in 0..h {
        for x in 0..w {
            if d[((y * w + x) * 4 + 3) as usize] != 0 {
                f = true;
                l = l.min(x);
                t = t.min(y);
                r = r.max(x + 1);
                b = b.max(y + 1)
            }
        }
    }
    f.then_some((l, t, r, b))
}
