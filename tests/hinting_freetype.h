#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_DRIVER_H
#include FT_MODULE_H
#include FT_MULTIPLE_MASTERS_H

/*
 * Select the requested FreeType interpreter explicitly so the differential
 * gate cannot silently change meaning with a distribution's default.
 */
static inline FT_Error
cangjie_ft_select_interpreter(FT_Library library, FT_UInt version)
{
  return FT_Property_Set(library,
                         "truetype",
                         "interpreter-version",
                         &version);
}
