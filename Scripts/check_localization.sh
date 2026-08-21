#!/usr/bin/env bash

# Reports strings the app can show but the string catalog cannot translate.
#
# `LocalizationTests` checks that every entry *in* the catalog carries all
# fifteen languages. It cannot see the opposite gap — a literal in the source
# that never reached the catalog at all — and that gap is silent: the string
# simply renders in Chinese for every other language. Forty-two of them had
# accumulated before this script existed.
#
# This script only *detects* the gap. `Scripts/generate_localizations.py` is the
# tool that fills it, from a catalog exported out of Xcode.
#
# Extraction is delegated to Xcode rather than reimplemented with grep. A
# hand-written scan misses most localizable positions (`Text`, `Label`,
# `.navigationTitle`, alert titles, `Section`, `TextField` placeholders …) and
# cannot resolve interpolations into the `%@` / `%lld` forms the catalog keys
# use.
#
# Note the deliberate false-positive blind spot in the other direction: entries
# Xcode marks `stale` are NOT reported as removable. The bundled ACL4SSR scheme
# names and summaries come from a manifest and are localized at runtime through
# `String(localized: String.LocalizationValue(name))`, which no static extractor
# can see. Deleting what looks unused would silently untranslate them.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CATALOG="$REPO_ROOT/Tower/Localizable.xcstrings"

work_dir="$(mktemp -d)"
backup_dir="$work_dir/catalogs"
mkdir -p "$backup_dir"

# `-exportLocalizations` writes newly discovered keys straight into the
# catalogs, stamps `extractionState` on entries it no longer finds, and
# rewrites the whole file in its own JSON style. That is a report, not an edit
# anyone asked for, so *every* catalog is put back either way — InfoPlist as
# well as Localizable, since the export touches both.
catalogs=()
while IFS= read -r catalog; do
    catalogs+=("$catalog")
    cp "$catalog" "$backup_dir/$(basename "$catalog")"
done < <(find "$REPO_ROOT/Tower" -name '*.xcstrings' -maxdepth 2 | sort)

restore_catalogs() {
    for catalog in "${catalogs[@]}"; do
        cp "$backup_dir/$(basename "$catalog")" "$catalog"
    done
    rm -rf "$work_dir"
}
trap restore_catalogs EXIT

printf 'Extracting localizable strings with Xcode…\n'
xcodebuild -exportLocalizations \
    -project "$REPO_ROOT/Tower.xcodeproj" \
    -localizationPath "$work_dir" \
    -exportLanguage zh-Hans > "$work_dir/export.log" 2>&1 || {
    printf 'xcodebuild -exportLocalizations failed. Log: %s\n' "$work_dir/export.log" >&2
    cp "$work_dir/export.log" /tmp/tower-export-localizations.log
    printf 'A copy is at /tmp/tower-export-localizations.log\n' >&2
    exit 1
}

python3 - "$work_dir" "$backup_dir/$(basename "$CATALOG")" <<'PYTHON'
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

work_dir, catalog_path = Path(sys.argv[1]), Path(sys.argv[2])
namespace = {'x': 'urn:oasis:names:tc:xliff:document:1.2'}

xliff = next(work_dir.rglob('*.xliff'), None)
if xliff is None:
    sys.exit('No xliff produced by xcodebuild -exportLocalizations.')

extracted = set()
for file_node in ET.parse(xliff).getroot().findall('x:file', namespace):
    if 'Localizable.xcstrings' not in (file_node.get('original') or ''):
        continue
    for unit in file_node.findall('.//x:trans-unit', namespace):
        extracted.add(unit.get('id'))

catalog = json.loads(catalog_path.read_text())['strings']
missing = sorted(extracted - set(catalog))

print(f'Extracted {len(extracted)} strings; catalog holds {len(catalog)}.')
if not missing:
    print('check_localization: PASS')
    sys.exit(0)

print(f'\n{len(missing)} string(s) can be shown but are not in the catalog.')
print('Untranslated, they render in Chinese in every other language:\n')
for key in missing:
    print(f'  {key!r}')
print(
    '\nEach one needs all fifteen languages in Tower/Localizable.xcstrings.'
    '\nTo fill them, export the source catalog from Xcode'
    '\n(Product > Export Localizations) and run:'
    '\n'
    '\n  python3 Scripts/generate_localizations.py --source-catalog <exported Localizable.xcstrings>'
    '\n'
    '\nThat generator is the maintained path; review its output before committing,'
    '\nsince it machine-translates and short UI labels often need a human pass.'
)
sys.exit(1)
PYTHON
