#!/usr/bin/env python3
"""Generate the country table the region resolver matches node names against.

Tower decides which country a node belongs to by reading its name first — the
airport wrote it, so it is more reliable than any database — and only falls
back to the offline IP lookup when the name says nothing. That needs a table of
every country: what it is called in Chinese and English, and where to draw it
on the dot map.

Natural Earth supplies both, and is public domain. It omits a handful of small
territories that matter a lot for proxies (Hong Kong, Singapore, Macau), so
those are carried here by hand.

Output is a Swift source file rather than a bundled resource: it is a few
hundred constant lines, it wants to be diffed in review, and it saves a file
read at launch.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from urllib.request import Request, urlopen

SOURCE_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "{revision}/geojson/ne_110m_admin_0_countries.geojson"
)
REVISION = "master"

ROOT = Path(__file__).resolve().parent.parent
DESTINATION = ROOT / "Tower" / "Services" / "CountryTable.swift"

# Natural Earth's 110m set is a physical-scale map: it drops anything too small
# to draw at that scale. These are exactly the places proxy nodes cluster in,
# so they are supplied here with their own label points.
SUPPLEMENTARY = {
    "HK": ("香港", "Hong Kong", 22.3193, 114.1694, ["hong kong", "hongkong"], ["HKG"]),
    "SG": ("新加坡", "Singapore", 1.3521, 103.8198, ["singapore"], ["SGP"]),
    "MO": ("澳门", "Macau", 22.1987, 113.5439, ["macau", "macao"], ["MAC"]),
    "MT": ("马耳他", "Malta", 35.9375, 14.3754, ["malta"], ["MLT"]),
    "BH": ("巴林", "Bahrain", 26.0667, 50.5577, ["bahrain"], ["BHR"]),
    "MU": ("毛里求斯", "Mauritius", -20.3484, 57.5522, ["mauritius"], ["MUS"]),
    "SC": ("塞舌尔", "Seychelles", -4.6796, 55.4920, ["seychelles"], ["SYC"]),
    "GI": ("直布罗陀", "Gibraltar", 36.1408, -5.3536, ["gibraltar"], ["GIB"]),
    "AD": ("安道尔", "Andorra", 42.5063, 1.5218, ["andorra"], ["AND"]),
    "MC": ("摩纳哥", "Monaco", 43.7384, 7.4246, ["monaco"], ["MCO"]),
    "LI": ("列支敦士登", "Liechtenstein", 47.1660, 9.5554, ["liechtenstein"], ["LIE"]),
    "SM": ("圣马力诺", "San Marino", 43.9424, 12.4578, ["san marino"], ["SMR"]),
}


def fetch(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": "Tower country table updater"})
    with urlopen(request, timeout=60) as response:
        return response.read()


def swift_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def deduplicated(values: list[str]) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for value in values:
        if value and value not in seen:
            seen.add(value)
            ordered.append(value)
    return ordered


def names_for(properties: dict) -> list[str]:
    """Spellings that are safe to match case insensitively."""
    result: list[str] = []
    for key in ("NAME", "NAME_LONG", "NAME_EN", "NAME_CIAWF", "NAME_SORT", "FORMAL_EN"):
        value = properties.get(key)
        if isinstance(value, str) and value.strip():
            result.append(value.strip().lower())
    # NAME_ALT holds historical and alternate spellings, pipe separated. This is
    # where "Turkey" lives now that the primary name is "Türkiye".
    alternates = properties.get("NAME_ALT")
    if isinstance(alternates, str):
        result.extend(part.strip().lower() for part in alternates.split("|") if part.strip())
    for key in ("NAME_ZH", "NAME_ZHT"):
        value = properties.get(key)
        if isinstance(value, str) and value.strip():
            result.append(value.strip())
    return deduplicated(result)


def codes_for(properties: dict) -> list[str]:
    """Three-letter codes, which only count when a name shouts them.

    Half of them are ordinary English words — AND is Andorra, ARE the Emirates,
    CAN Canada, PER Peru — so matching them case insensitively files "Hong Kong
    and Tokyo" under Andorra. Airports write codes in capitals; that is the
    signal, and the same rule the two-letter tokens already use.
    """
    result: list[str] = []
    for key in ("ISO_A3_EH", "ISO_A3", "ADM0_A3"):
        value = properties.get(key)
        if isinstance(value, str) and len(value) == 3 and value.isalpha() and value != "-99":
            result.append(value.upper())
    return deduplicated(result)


def build(revision: str) -> None:
    url = SOURCE_URL.format(revision=revision)
    print(f"下载 {url}")
    geojson = json.loads(fetch(url))

    entries: dict[str, tuple[str, str, float, float, list[str], list[str]]] = {}
    for feature in geojson["features"]:
        properties = feature["properties"]
        code = (properties.get("ISO_A2_EH") or properties.get("ISO_A2") or "").upper()
        if len(code) != 2 or not code.isalpha():
            continue
        latitude = properties.get("LABEL_Y")
        longitude = properties.get("LABEL_X")
        if latitude is None or longitude is None:
            continue
        chinese = (properties.get("NAME_ZH") or properties.get("NAME") or code).strip()
        english = (properties.get("NAME") or code).strip()
        entries[code] = (
            chinese, english, float(latitude), float(longitude),
            names_for(properties), codes_for(properties)
        )

    for code, value in SUPPLEMENTARY.items():
        entries.setdefault(code, value)

    print(f"国家/地区 {len(entries)} 个")

    lines = [
        "// Generated by Scripts/update_country_table.py — do not edit by hand.",
        "//",
        "// Source: Natural Earth ne_110m_admin_0_countries (public domain),",
        f"// revision {revision}, plus the small territories that set omits.",
        "",
        "extension NodeRegionResolver {",
        "    /// Every country Tower can name and place, keyed by ISO 3166-1 alpha-2.",
        "    ///",
        "    /// `names` are lowercased spellings a node name might use — English,",
        "    /// Chinese, and historical names such as Turkey for Türkiye. They match",
        "    /// case insensitively, on whole words for the Latin ones.",
        "    ///",
        "    /// `codes` are the three-letter ISO codes, matched only when the name",
        "    /// writes them in capitals: too many of them are ordinary words.",
        "    struct CountryEntry {",
        "        let chineseName: String",
        "        let englishName: String",
        "        let latitude: Double",
        "        let longitude: Double",
        "        let names: [String]",
        "        let codes: [String]",
        "    }",
        "",
        "    static let countryTable: [String: CountryEntry] = [",
    ]

    for code in sorted(entries):
        chinese, english, latitude, longitude, names, codes = entries[code]
        name_literal = ", ".join(swift_string(name) for name in names)
        code_literal = ", ".join(swift_string(value) for value in codes)
        lines.append(
            f'        "{code}": .init('
            f"chineseName: {swift_string(chinese)}, "
            f"englishName: {swift_string(english)}, "
            f"latitude: {latitude:.4f}, longitude: {longitude:.4f}, "
            f"names: [{name_literal}], codes: [{code_literal}]),"
        )

    lines.append("    ]")
    lines.append("}")

    DESTINATION.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"完成 -> {DESTINATION}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", default=REVISION)
    build(parser.parse_args().revision)


if __name__ == "__main__":
    main()
