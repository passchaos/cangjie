#!/usr/bin/env python3
"""Verify the version-pinned Fontations coverage evidence manifest."""

import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "docs/fontations-coverage.json"
EXPECTED_REFERENCE = {
    "repository": "https://github.com/googlefonts/fontations",
    "commit": "bb6f87166aa8bac93ff9df5ea67d58b7091b3e2a",
    "read_fonts_version": "0.42.2",
    "skrifa_version": "0.45.2",
    "excluded_read_fonts_helper_modules": ["aat", "bitmap", "layout", "variations"],
}

# These are the public table modules in read-fonts 0.42.2, excluding its four
# shared implementation modules (aat, bitmap, layout, and variations). Keeping
# this list independent of the manifest makes removal of a coverage row fail.
EXPECTED_TABLE_MODULES = {
    "ankr", "avar", "base", "cbdt", "cblc", "cff", "cff2", "cmap",
    "colr", "cpal", "cvar", "dsig", "ebdt", "eblc", "feat", "fvar",
    "gasp", "gdef", "glyf", "gpos", "gsub", "gvar", "hdmx", "head",
    "hhea", "hmtx", "hvar", "ift", "kern", "kerx", "loca", "ltag",
    "maxp", "meta", "morx", "mvar", "name", "os2", "post", "sbix",
    "stat", "svg", "trak", "varc", "vhea", "vmtx", "vorg", "vvar",
}
EXPECTED_SKRIFA_APIS = {
    "MetadataProvider::attributes",
    "MetadataProvider::axes",
    "MetadataProvider::named_instances",
    "MetadataProvider::localized_strings",
    "MetadataProvider::glyph_names",
    "MetadataProvider::metrics",
    "MetadataProvider::glyph_metrics",
    "MetadataProvider::charmap",
    "MetadataProvider::outline_glyphs",
    "MetadataProvider::color_glyphs",
    "MetadataProvider::color_palettes",
    "MetadataProvider::bitmap_strikes",
    "outline::HintingInstance",
}
ZIG_TEST_DECLARATION = re.compile(r'^\s*test(?:\s+"|\s*\{)', re.MULTILINE)


def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key {key!r}")
        result[key] = value
    return result


def repository_file(value, location, errors):
    """Return a regular in-repository file, recording a schema error otherwise."""
    if not isinstance(value, str) or not value:
        errors.append(f"{location}: expected a nonempty path")
        return None
    path = (ROOT / value).resolve()
    try:
        path.relative_to(ROOT)
    except ValueError:
        errors.append(f"{location}: path escapes repository: {value!r}")
        return None
    if not path.is_file():
        errors.append(f"{location}: missing file {value!r}")
        return None
    return path


def verify_rows(manifest, section, identity_field, upstream_field, errors):
    rows = manifest.get(section)
    if not isinstance(rows, list) or not rows:
        errors.append(f"{section}: expected a nonempty row list")
        return set()

    identities = set()
    upstream_items = set()
    for index, row in enumerate(rows):
        location = f"{section}[{index}]"
        if not isinstance(row, dict):
            errors.append(f"{location}: expected an object")
            continue

        identity = row.get(identity_field)
        if not isinstance(identity, str) or not identity:
            errors.append(f"{location}.{identity_field}: expected a nonempty string")
        elif identity in identities:
            errors.append(f"{location}.{identity_field}: duplicate {identity!r}")
        else:
            identities.add(identity)

        claimed = row.get(upstream_field)
        if not isinstance(claimed, list) or not claimed:
            errors.append(f"{location}.{upstream_field}: expected a nonempty list")
        else:
            for item in claimed:
                if not isinstance(item, str) or not item:
                    errors.append(f"{location}.{upstream_field}: invalid item {item!r}")
                elif item in upstream_items:
                    errors.append(f"{location}.{upstream_field}: duplicate claim {item!r}")
                else:
                    upstream_items.add(item)

        artifact = repository_file(row.get("artifact"), f"{location}.artifact", errors)
        test = repository_file(row.get("test"), f"{location}.test", errors)
        if artifact is not None and artifact.stat().st_size == 0:
            errors.append(f"{location}.artifact: empty file")
        if test is not None:
            source = test.read_text(encoding="utf-8")
            if not ZIG_TEST_DECLARATION.search(source):
                relative = test.relative_to(ROOT)
                errors.append(f"{location}.test: no Zig test declaration in {relative}")

    return upstream_items


def main():
    errors = []
    try:
        manifest = json.loads(
            MANIFEST_PATH.read_text(encoding="utf-8"),
            object_pairs_hook=reject_duplicate_keys,
        )
    except (OSError, ValueError) as error:
        print(f"fontations coverage verification failed: {error}", file=sys.stderr)
        return 1
    if not isinstance(manifest, dict):
        print("fontations coverage verification failed: root must be an object", file=sys.stderr)
        return 1

    reference = manifest.get("reference")
    if reference != EXPECTED_REFERENCE:
        errors.append("reference: expected the pinned Fontations source revision")

    table_modules = verify_rows(
        manifest, "tables", "tag", "upstream_modules", errors
    )
    skrifa_apis = verify_rows(
        manifest, "skrifa", "capability", "upstream_apis", errors
    )
    if table_modules != EXPECTED_TABLE_MODULES:
        missing = sorted(EXPECTED_TABLE_MODULES - table_modules)
        extra = sorted(table_modules - EXPECTED_TABLE_MODULES)
        errors.append(f"tables: upstream module mismatch; missing={missing}, extra={extra}")
    if skrifa_apis != EXPECTED_SKRIFA_APIS:
        missing = sorted(EXPECTED_SKRIFA_APIS - skrifa_apis)
        extra = sorted(skrifa_apis - EXPECTED_SKRIFA_APIS)
        errors.append(f"skrifa: upstream API mismatch; missing={missing}, extra={extra}")

    if errors:
        print("fontations coverage verification failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print(
        f"fontations coverage verified: {len(manifest['tables'])} table families "
        f"covering {len(table_modules)} public modules, "
        f"{len(manifest['skrifa'])} high-level capabilities"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
