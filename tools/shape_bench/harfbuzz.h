#include <hb.h>
#include <hb-ft.h>
#include <hb-ot.h>
#include <ft2build.h>
#include FT_FREETYPE_H

static inline unsigned int cangjie_hb_version_at_least(
    unsigned int major,
    unsigned int minor,
    unsigned int micro)
{
    return hb_version_atleast(major, minor, micro);
}
