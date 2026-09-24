# Outfit runtime subset

CardVault bundles only the five Outfit weights reachable from production UI:
300, 400, 500, 600, and 700. The former 800 face was referenced only by an
unreachable prototype widget and is intentionally not shipped.

The retained Unicode set covers printable ASCII, Latin-1, the Latin Extended-A
glyphs present in the source, combining accents, common typographic punctuation,
the euro sign, arrows, and arithmetic symbols. This preserves the prior Outfit
coverage for app copy, bank names, and Latin-script user-entered names; the
platform font fallback continues to render scripts Outfit does not contain.

Run `tool/subset_fonts.sh` after replacing or upgrading an Outfit source file.
The script is idempotent and requires HarfBuzz's `hb-subset` executable. Review
the glyph policy before adding a locale, and extend both the script and
`test/font_asset_optimization_test.dart` when that locale needs new scripts.
