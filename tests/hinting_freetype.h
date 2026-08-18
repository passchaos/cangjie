#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_DRIVER_H
#include FT_MODULE_H
#include FT_MULTIPLE_MASTERS_H

/*
 * Cangjie's current point VM implements the classic TrueType interpreter.
 * Select FreeType v35 explicitly so the differential gate cannot silently
 * change meaning with a distribution's default v40 configuration.
 */
static inline FT_Error
cangjie_ft_select_classic_interpreter(FT_Library library)
{
  FT_UInt version = TT_INTERPRETER_VERSION_35;

  return FT_Property_Set(library,
                         "truetype",
                         "interpreter-version",
                         &version);
}
