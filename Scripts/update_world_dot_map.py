#!/usr/bin/env python3
"""Rasterise land and country ownership into the home-screen dot map.

The map on the subscriptions tab is a flat dot-matrix world: it draws one dot
per land cell of a Web-Mercator grid. This script turns Natural Earth's
public-domain land and admin-country polygons into aligned text grids the app
reads at launch.

`WorldDotMap.txt` uses '#' for land and '.' for water.
`WorldDotCountries.txt` uses an ISO alpha-2 code or '..' for every cell.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tempfile
from pathlib import Path
from urllib.request import Request, urlopen

import numpy as np

# Natural Earth is explicitly public domain.
LAND_SOURCE_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "{revision}/geojson/ne_110m_land.geojson"
)
COUNTRY_SOURCE_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "{revision}/geojson/ne_110m_admin_0_countries.geojson"
)
# The shipped bitmap must be reproducible. Move this pin only after reviewing
# the regenerated map and country-table diffs together.
REVISION = "ca96624a56bd078437bca8184e78163e5039ad19"

ROOT = Path(__file__).resolve().parent.parent
DESTINATION = ROOT / "Tower" / "Resources" / "WorldMap"

# Antarctica is dropped: it spans the whole bottom edge and adds a heavy bar
# that no proxy node ever sits on.
MIN_LATITUDE = -60.0
MAX_LATITUDE = 84.0
# Keep the complete date-line span. Cropping the Pacific clamps real country
# label points such as Fiji and New Zealand onto the edge of the card.
MIN_LONGITUDE = -180.0
MAX_LONGITUDE = 180.0


def fetch(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": "Tower world map updater"})
    with urlopen(request, timeout=60) as response:
        return response.read()


def rings(geojson: dict) -> list[np.ndarray]:
    """Outer rings of every land polygon, as (N, 2) lon/lat arrays."""
    result: list[np.ndarray] = []
    for feature in geojson["features"]:
        geometry = feature["geometry"]
        polygons = (
            [geometry["coordinates"]]
            if geometry["type"] == "Polygon"
            else geometry["coordinates"]
        )
        for polygon in polygons:
            if polygon:
                result.append(np.asarray(polygon[0], dtype=float))
    return result


def mercator_y(latitude: float | np.ndarray) -> float | np.ndarray:
    """Web-mercator vertical coordinate."""
    radians = np.radians(latitude)
    return np.log(np.tan(np.pi / 4 + radians / 2))


def inverse_mercator_y(y: np.ndarray) -> np.ndarray:
    return np.degrees(2 * np.arctan(np.exp(y)) - np.pi / 2)


def natural_rows(columns: int) -> int:
    """Rows that keep the mercator cells square."""
    horizontal = np.radians(MAX_LONGITUDE - MIN_LONGITUDE)
    vertical = mercator_y(MAX_LATITUDE) - mercator_y(MIN_LATITUDE)
    return int(round(columns * vertical / horizontal))


def grid_centres(columns: int, rows: int) -> tuple[np.ndarray, np.ndarray]:
    """Longitude and latitude mesh for every Mercator cell centre."""
    lons = MIN_LONGITUDE + (np.arange(columns) + 0.5) * ((MAX_LONGITUDE - MIN_LONGITUDE) / columns)
    # Rows are evenly spaced in mercator space, not in degrees, so the grid
    # matches the projection the app draws with.
    top, bottom = mercator_y(MAX_LATITUDE), mercator_y(MIN_LATITUDE)
    row_y = top - (np.arange(rows) + 0.5) * ((top - bottom) / rows)
    lats = inverse_mercator_y(row_y)
    return np.meshgrid(lons, lats)


def ring_mask(ring: np.ndarray, grid_lon: np.ndarray, grid_lat: np.ndarray) -> np.ndarray:
    """Even-odd point-in-polygon mask for one ring."""
    inside = np.zeros(grid_lon.shape, dtype=bool)
    x, y = ring[:, 0], ring[:, 1]
    if y.max() < MIN_LATITUDE or y.min() > MAX_LATITUDE:
        return inside
    if x.max() < MIN_LONGITUDE or x.min() > MAX_LONGITUDE:
        return inside

    x_next, y_next = np.roll(x, -1), np.roll(y, -1)
    for index in range(len(x)):
        y0, y1 = y[index], y_next[index]
        if y0 == y1:
            continue
        straddles = (grid_lat >= np.minimum(y0, y1)) & (grid_lat < np.maximum(y0, y1))
        if not straddles.any():
            continue
        crossing_x = x[index] + (grid_lat - y0) * (x_next[index] - x[index]) / (y1 - y0)
        inside ^= straddles & (grid_lon < crossing_x)
    return inside


def rasterise(polygons: list[np.ndarray], columns: int, rows: int) -> np.ndarray:
    """Even-odd point-in-polygon test for every land polygon."""
    grid_lon, grid_lat = grid_centres(columns, rows)
    inside = np.zeros(grid_lon.shape, dtype=bool)

    for ring in polygons:
        inside ^= ring_mask(ring, grid_lon, grid_lat)
    return inside


def feature_code(feature: dict) -> str | None:
    """Natural Earth's preferred two-letter code, excluding placeholders."""
    properties = feature.get("properties", {})
    for key in ("ISO_A2_EH", "ISO_A2"):
        value = str(properties.get(key, "")).upper()
        if len(value) == 2 and value.isalpha():
            return value
    return None


def rasterise_countries(
    geojson: dict,
    land: np.ndarray,
    columns: int,
    rows: int,
) -> np.ndarray:
    """Assign each land cell to the admin-country polygon containing it."""
    grid_lon, grid_lat = grid_centres(columns, rows)
    country_codes = np.full((rows, columns), "", dtype="<U2")

    for feature in geojson["features"]:
        code = feature_code(feature)
        geometry = feature.get("geometry")
        if code is None or geometry is None:
            continue
        polygons = (
            [geometry["coordinates"]]
            if geometry["type"] == "Polygon"
            else geometry["coordinates"]
        )
        feature_mask = np.zeros((rows, columns), dtype=bool)
        for polygon in polygons:
            if not polygon:
                continue
            polygon_mask = ring_mask(np.asarray(polygon[0], dtype=float), grid_lon, grid_lat)
            for hole in polygon[1:]:
                polygon_mask &= ~ring_mask(np.asarray(hole, dtype=float), grid_lon, grid_lat)
            feature_mask |= polygon_mask
        country_codes[feature_mask & land] = code

    return country_codes


def build(columns: int, rows: int, revision: str) -> None:
    land_url = LAND_SOURCE_URL.format(revision=revision)
    country_url = COUNTRY_SOURCE_URL.format(revision=revision)
    print(f"下载 {land_url}")
    land_geojson = json.loads(fetch(land_url))
    print(f"下载 {country_url}")
    country_geojson = json.loads(fetch(country_url))

    print(f"栅格化 {columns}×{rows} …")
    grid = rasterise(rings(land_geojson), columns, rows)
    country_codes = rasterise_countries(country_geojson, grid, columns, rows)
    land = int(grid.sum())
    print(f"陆地点 {land} / {columns * rows}")
    print(f"国家/地区 {len(set(country_codes.flat) - {''})}")

    lines = ["".join("#" if cell else "." for cell in row) for row in grid]
    body = "\n".join(lines) + "\n"
    header = (
        f"# Tower world dot map\n"
        f"# source: Natural Earth 110m land (public domain)\n"
        f"# revision: {revision}\n"
        f"# projection: mercator\n"
        f"# bounds: lon {MIN_LONGITUDE}..{MAX_LONGITUDE}, lat {MIN_LATITUDE}..{MAX_LATITUDE}\n"
        f"size {columns} {rows}\n"
    )
    content = header + body
    country_lines = [" ".join(code if code else ".." for code in row) for row in country_codes]
    country_body = "\n".join(country_lines) + "\n"
    country_header = (
        f"# Tower world dot country ownership\n"
        f"# source: Natural Earth 110m admin 0 countries (public domain)\n"
        f"# revision: {revision}\n"
        f"# projection: mercator\n"
        f"# bounds: lon {MIN_LONGITUDE}..{MAX_LONGITUDE}, lat {MIN_LATITUDE}..{MAX_LATITUDE}\n"
        f"size {columns} {rows}\n"
    )
    country_content = country_header + country_body

    staging = Path(tempfile.mkdtemp(prefix="tower-worldmap-"))
    try:
        (staging / "WorldDotMap.txt").write_text(content, encoding="utf-8")
        (staging / "WorldDotCountries.txt").write_text(country_content, encoding="utf-8")
        (staging / "WorldMap-NOTICE.txt").write_text(
            "World land outlines and country ownership\n"
            "=========================================\n\n"
            "Sources:    Natural Earth, ne_110m_land and ne_110m_admin_0_countries\n"
            "Source URL: https://www.naturalearthdata.com\n"
            f"Revision:   {revision}\n"
            "License:    Public domain\n\n"
            "Natural Earth places all of its raster and vector map data in the\n"
            "public domain, so no attribution is required. It is recorded here\n"
            "anyway so the snapshot can be traced and regenerated.\n\n"
            f"Grid:   {columns} x {rows}, mercator\n"
            f"Bounds: longitude {MIN_LONGITUDE}..{MAX_LONGITUDE}, latitude {MIN_LATITUDE}..{MAX_LATITUDE}\n"
            f"WorldDotMap.txt SHA256:       {hashlib.sha256(content.encode('utf-8')).hexdigest()}\n"
            f"WorldDotCountries.txt SHA256: {hashlib.sha256(country_content.encode('utf-8')).hexdigest()}\n\n"
            "Regenerate with: python3 Scripts/update_world_dot_map.py\n",
            encoding="utf-8",
        )
        if DESTINATION.exists():
            shutil.rmtree(DESTINATION)
        DESTINATION.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(staging), str(DESTINATION))
        staging = None
    finally:
        if staging is not None and staging.exists():
            shutil.rmtree(staging, ignore_errors=True)

    print(f"完成 -> {DESTINATION}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--columns", type=int, default=220)
    parser.add_argument("--rows", type=int, default=0, help="0 表示按投影自动计算")
    parser.add_argument("--revision", default=REVISION)
    args = parser.parse_args()
    rows = args.rows if args.rows > 0 else natural_rows(args.columns)
    build(args.columns, rows, args.revision)


if __name__ == "__main__":
    main()
