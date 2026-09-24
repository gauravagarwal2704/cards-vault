#!/bin/sh
set -eu

if ! command -v hb-subset >/dev/null 2>&1; then
  echo "hb-subset is required (install HarfBuzz)." >&2
  exit 1
fi

unicodes='U+0020-007E,U+00A0-00FF,U+0100-017F,U+02BC,U+02C6,U+02DA,U+02DC,U+0300-0304,U+0308,U+2013-2014,U+2018-201A,U+201C-201E,U+2022,U+2026,U+2039-203A,U+2044,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215'

for font in \
  assets/fonts/Outfit-Light.ttf \
  assets/fonts/Outfit-Regular.ttf \
  assets/fonts/Outfit-Medium.ttf \
  assets/fonts/Outfit-SemiBold.ttf \
  assets/fonts/Outfit-Bold.ttf
do
  subset_file="${font}.subset"
  hb-subset "$font" --unicodes="$unicodes" --output-file="$subset_file"
  mv "$subset_file" "$font"
done
