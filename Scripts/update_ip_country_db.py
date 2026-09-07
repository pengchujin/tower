#!/usr/bin/env python3
"""Build offline country/ASN resources from hash-pinned sapics release assets.

Default downloads refuse a changed daily release. For exact regeneration, retain
these four source CSV files and pass --source-dir; no node addresses are sent.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import ipaddress
import json
from pathlib import Path
import struct
import tempfile
import urllib.request
import zlib

VERSION = "2026-09-06T22:31Z"
PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_ROOT = PROJECT_ROOT / "Tower" / "Resources" / "IPCountry"
SOURCES = {
    "server-country-ipv4-num.csv": (547763171, "eb2c4c86552733887c961dd6becbc656d431c5522457d3c8be50146a2c12e4be"),
    "server-country-ipv6.csv": (547763145, "f9dc817d658c76ef1a79641766000e4d1f07414629b0bf2d572fe673a75f7583"),
    "origin-asn-ipv4-num.csv": (547763211, "bb78b53c852e1bdb97c6681f27995af632c2bbcfcdd3228fc20820c1c128390e"),
    "origin-asn-ipv6.csv": (547763156, "a863695b77b7e73b8dab5cbc243e6cac011c24e82bbcdba161d2a8303ee1c8d2"),
}


def source_bytes(filename: str, source_dir: Path | None) -> bytes:
    asset_id, expected = SOURCES[filename]
    if source_dir:
        data = (source_dir / filename).read_bytes()
    else:
        # Asset IDs pin identity; upstream may remove older assets. Never silently
        # accept a newer snapshot when a pinned asset is no longer available.
        request = urllib.request.Request(
            f"https://api.github.com/repos/sapics/ip-location-db/releases/assets/{asset_id}",
            headers={"Accept": "application/octet-stream", "User-Agent": "Tower-Offline-IP-Builder"},
        )
        with urllib.request.urlopen(request, timeout=120) as response:
            data = response.read()
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError(f"Source SHA-256 mismatch: {filename}; use the pinned CSV with --source-dir")
    return data


def validated_rows(data: bytes, family: int, asn: bool):
    previous_end = -1
    for row in csv.reader(io.StringIO(data.decode("utf-8"))):
        if len(row) != (4 if asn else 3):
            raise ValueError("Unexpected CSV columns")
        start, end = (int(v) if family == 4 else int(ipaddress.IPv6Address(v)) for v in row[:2])
        if not 0 <= start <= end < 2 ** (32 if family == 4 else 128) or start <= previous_end:
            raise ValueError("Ranges must be ordered, non-overlapping and valid")
        previous_end = end
        if asn:
            number = int(row[2])
            if not 0 < number < 2**32:
                raise ValueError("Invalid ASN")
            value = (number, row[3])
        else:
            if len(row[2]) != 2 or not row[2].isascii() or not row[2].isalpha() or not row[2].isupper():
                raise ValueError("Invalid country code")
            value = row[2]
        yield start, end, value


def merged_rows(rows):
    pending = None
    for start, end, value in rows:
        if pending and start == pending[1] + 1 and value == pending[2]:
            pending = pending[0], end, value
        else:
            if pending:
                yield pending
            pending = start, end, value
    if pending:
        yield pending


def build_country(data: bytes, family: int) -> bytes:
    width = 4 if family == 4 else 16
    return b"".join(start.to_bytes(width, "big") + end.to_bytes(width, "big") + code.encode("ascii")
                    for start, end, code in merged_rows(validated_rows(data, family, False)))


def build_asn(data: bytes, family: int, names: bytearray, offsets: dict[str, tuple[int, int]]) -> bytes:
    result = bytearray()
    width = 4 if family == 4 else 16
    for start, end, (number, name) in merged_rows(validated_rows(data, family, True)):
        if name not in offsets:
            encoded = name.encode("utf-8")
            if len(encoded) > 65535 or len(names) + len(encoded) >= 2**32:
                raise ValueError("Organization name pool exceeds format capacity")
            offsets[name] = len(names), len(encoded)
            names.extend(encoded)
        offset, length = offsets[name]
        result.extend(start.to_bytes(width, "big") + end.to_bytes(width, "big"))
        result.extend(struct.pack(">IIH", number, offset, length))
    return bytes(result)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, help="Directory containing the four hash-pinned source CSVs")
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_ROOT)
    args = parser.parse_args()
    sources = {filename: source_bytes(filename, args.source_dir) for filename in SOURCES}
    names = bytearray()
    offsets: dict[str, tuple[int, int]] = {}
    products = {
        "IPCountryIPv4.bin": build_country(sources["server-country-ipv4-num.csv"], 4),
        "IPCountryIPv6.bin": build_country(sources["server-country-ipv6.csv"], 6),
        "IPASNIPv4.bin": build_asn(sources["origin-asn-ipv4-num.csv"], 4, names, offsets),
        "IPASNIPv6.bin": build_asn(sources["origin-asn-ipv6.csv"], 6, names, offsets),
        "IPASNNames.bin": bytes(names),
        "IPCountryVersion.txt": (VERSION + "\n").encode("ascii"),
    }
    manifest = {
        "version": VERSION,
        "license": "PDDL-1.0",
        "licenseURL": "https://opendatacommons.org/licenses/pddl/1-0/",
        "sources": [dict(filename=n, assetID=a, url=f"https://api.github.com/repos/sapics/ip-location-db/releases/assets/{a}", sha256=h) for n, (a, h) in SOURCES.items()],
        "format": {"endianness": "big", "countryIPv4RecordBytes": 10, "countryIPv6RecordBytes": 34,
                   "asnIPv4RecordBytes": 18, "asnIPv6RecordBytes": 42,
                   "asnFields": "start IP, end IP, uint32 ASN, uint32 name offset, uint16 name byte length",
                   "names": "shared UTF-8 pool, no terminators"},
        "artifacts": {n: dict(bytes=len(d), sha256=hashlib.sha256(d).hexdigest(), zlib9Bytes=len(zlib.compress(d, 9))) for n, d in products.items()},
        "uniqueOrganizationNames": len(offsets),
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    # Fully validate all sources and build all products before replacing resources.
    with tempfile.TemporaryDirectory(dir=args.output_dir) as temporary:
        for filename, data in products.items():
            staged = Path(temporary) / filename
            staged.write_bytes(data)
        for filename in products:
            (Path(temporary) / filename).replace(args.output_dir / filename)
    (args.output_dir / "IPCountryManifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest["artifacts"], indent=2))


if __name__ == "__main__":
    main()
