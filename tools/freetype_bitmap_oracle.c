// Reference reader for the synthetic EBDT compound fixture exported by
// cangjie.testing.test_font.buildCompoundEbdtTtf. Expected output:
// mode=1 width=4 rows=2 left=0 top=2 pitch=1, then 1000 and 0010.
// Passing any third argument selects glyph 1 instead; the 32-bpp format 2/5/7
// fixtures all produce mode 7, 2x1, bearing (2,13), and bytes
// 070d40800a141eff.
// Build with pkg-config's freetype2 cflags and libraries.
#include <stdio.h>
#include <stdlib.h>
#include <ft2build.h>
#include FT_FREETYPE_H

int main(int argc, char **argv) {
  FT_Library library;
  FT_Face face;
  FT_Bitmap *bitmap;
  unsigned int x, y;

  if ((argc != 2 && argc != 3) || FT_Init_FreeType(&library) ||
      FT_New_Face(library, argv[1], 0, &face) ||
      FT_Set_Pixel_Sizes(face, 0, 16) ||
      FT_Load_Glyph(face, (argc == 3) ? 1 : 2,
                    FT_LOAD_RENDER | FT_LOAD_NO_HINTING | FT_LOAD_COLOR))
    return EXIT_FAILURE;
  bitmap = &face->glyph->bitmap;
  printf("mode=%u width=%u rows=%u left=%d top=%d pitch=%d\n",
         bitmap->pixel_mode, bitmap->width, bitmap->rows,
         face->glyph->bitmap_left, face->glyph->bitmap_top, bitmap->pitch);
  if (bitmap->pixel_mode == FT_PIXEL_MODE_BGRA) {
    const unsigned int byte_count = bitmap->width * bitmap->rows * 4;
    for (x = 0; x < byte_count; x++) printf("%02x", bitmap->buffer[x]);
    putchar('\n');
    FT_Done_Face(face);
    FT_Done_FreeType(library);
    return EXIT_SUCCESS;
  }
  if (bitmap->pixel_mode != FT_PIXEL_MODE_MONO || bitmap->pitch <= 0)
    return EXIT_FAILURE;
  for (y = 0; y < bitmap->rows; y++) {
    const unsigned char *row = bitmap->buffer + y * bitmap->pitch;
    for (x = 0; x < bitmap->width; x++)
      putchar('0' + ((row[x >> 3] >> (7 - (x & 7))) & 1));
    putchar('\n');
  }
  FT_Done_Face(face);
  FT_Done_FreeType(library);
  return EXIT_SUCCESS;
}
