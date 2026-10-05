#!/bin/bash
set -euo pipefail
project=$(cd "$(dirname "$0")/../../mobile/coaching" && pwd)
font="$project/build/web/assets/assets/fonts/roboto/v32"
mkdir -p "$font"
curl --fail --retry 3 --location 'https://fonts.gstatic.com/s/roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2' -o "$font/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2"
flutter_bin=$(dirname "$(readlink -f "$(command -v flutter)")")
cp "$flutter_bin/cache/artifacts/material_fonts/roboto_license.txt" "$font/LICENSE.txt"
cd "$project"
node browser/scripts/build-offline.mjs
