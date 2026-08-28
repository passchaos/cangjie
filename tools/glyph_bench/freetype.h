#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_OUTLINE_H
#include FT_MULTIPLE_MASTERS_H
#include FT_COLOR_H
#include FT_DRIVER_H
#include FT_MODULE_H

static inline FT_Error
cangjie_ft_select_interpreter(FT_Library library, FT_UInt version)
{
  return FT_Property_Set(library,
                         "truetype",
                         "interpreter-version",
                         &version);
}
