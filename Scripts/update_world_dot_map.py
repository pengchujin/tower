#!/usr/bin/env python3
"""Rasterise world land polygons into the dot grid the home screen draws.

The map on the subscriptions tab is a flat dot-matrix world rather than a
MapKit globe: it draws one dot per land cell of an equirectangular grid. This
script turns Natural Earth's public-domain land polygons into that grid and
stores it as a compact bitmap the app reads at launch.

Output is a text resource: a header line with the grid size, then one line per
row using '#' for land and '.' for water. It compresses well, diffs readably,
and needs no image decoding at runtime.
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
SOURCE_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "{revision}/geojson/ne_110m_land.geojson"
)
REVISION = "master"

ROOT = Path(__file__).resolve().parent.parent
DESTINATION = ROOT / "Tower" / "Resources" / "WorldMap"

# Antarctica is dropped: it spans the whole bottom edge and adds a heavy bar
# that no proxy node ever sits on.
MIN_LATITUDE = -60.0
MAX_LATITUDE = 84.0


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


def rasterise(polygons: list[np.ndarray], columns: int, rows: int) -> np.ndarray:
    """Even-odd point-in-polygon test for every cell centre."""
    lons = -180.0 + (np.arange(columns) + 0.5) * (360.0 / columns)
    lats = MAX_LATITUDE - (np.arange(rows) + 0.5) * ((MAX_LATITUDE - MIN_LATITUDE) / rows)
    grid_lon, grid_lat = np.meshgrid(lons, lats)
    inside = np.zeros(grid_lon.shape, dtype=bool)

    for ring in polygons:
        x, y = ring[:, 0], ring[:, 1]
        # Skip rings that cannot touch the visible band.
        if y.max() < MIN_LATITUDE or y.min() > MAX_LATITUDE:
            continue
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


def build(columns: int, rows: int, revision: str) -> None:
    url = SOURCE_URL.format(revision=revision)
    print(f"下载 {url}")
    payload = fetch(url)
    geojson = json.loads(payload)

    print(f"栅格化 {columns}×{rows} …")
    grid = rasterise(rings(geojson), columns, rows)
    land = int(grid.sum())
    print(f"陆地点 {land} / {columns * rows}")

    lines = ["".join("#" if cell else "." for cell in row) for row in grid]
    body = "\n".join(lines) + "\n"
    header = (
        f"# Tower world dot map\n"
        f"# source: Natural Earth 110m land (public domain)\n"
        f"# revision: {revision}\n"
        f"# bounds: lon -180..180, lat {MIN_LATITUDE}..{MAX_LATITUDE}\n"
        f"size {columns} {rows}\n"
    )
    content = header + body

    staging = Path(tempfile.mkdtemp(prefix="tower-worldmap-"))
    try:
        (staging / "WorldDotMap.txt").write_text(content, encoding="utf-8")
        (staging / "WorldMap-NOTICE.txt").write_text(
            "World land outlines\n"
            "===================\n\n"
            "Source:     Natural Earth, ne_110m_land\n"
            "Source URL: https://www.naturalearthdata.com\n"
            f"Revision:   {revision}\n"
            "License:    Public domain\n\n"
            "Natural Earth places all of its raster and vector map data in the\n"
            "public domain, so no attribution is required. It is recorded here\n"
            "anyway so the snapshot can be traced and regenerated.\n\n"
            f"Grid:   {columns} x {rows}, equirectangular\n"
            f"Bounds: longitude -180..180, latitude {MIN_LATITUDE}..{MAX_LATITUDE}\n"
            f"SHA256: {hashlib.sha256(content.encode('utf-8')).hexdigest()}\n\n"
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
    parser.add_argument("--columns", type=int, default=200)
    parser.add_argument("--rows", type=int, default=90)
    parser.add_argument("--revision", default=REVISION)
    args = parser.parse_args()
    build(args.columns, args.rows, args.revision)


if __name__ == "__main__":
    main()
