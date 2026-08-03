#!/usr/bin/env python3
"""Build compact, fixed-record IP-to-country databases for the iOS bundle."""

from __future__ import annotations

import csv
import io
import ipaddress
import pathlib
import struct
import urllib.request


VERSION = "2.3.2026061719"
PACKAGE_ROOT = f"https://cdn.jsdelivr.net/npm/@ip-location-db/geo-whois-asn-country@{VERSION}"
PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]
OUTPUT_ROOT = PROJECT_ROOT / "Tower" / "Resources" / "IPCountry"


def rows(filename: str):
    request = urllib.request.Request(
        f"{PACKAGE_ROOT}/{filename}",
        headers={"User-Agent": "Tower-IPCountry-Builder/1.0"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        text = io.TextIOWrapper(response, encoding="utf-8", newline="")
        yield from csv.reader(text)


def build_ipv4() -> int:
    count = 0
    destination = OUTPUT_ROOT / "IPCountryIPv4.bin"
    with destination.open("wb") as output:
        for start, end, country_code in rows("geo-whois-asn-country-ipv4-num.csv"):
            output.write(struct.pack(">II2s", int(start), int(end), country_code.encode("ascii")))
            count += 1
    return count


def build_ipv6() -> int:
    count = 0
    destination = OUTPUT_ROOT / "IPCountryIPv6.bin"
    with destination.open("wb") as output:
        for start, end, country_code in rows("geo-whois-asn-country-ipv6.csv"):
            output.write(
                ipaddress.IPv6Address(start).packed
                + ipaddress.IPv6Address(end).packed
                + country_code.encode("ascii")
            )
            count += 1
    return count


def main() -> None:
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    ipv4_count = build_ipv4()
    ipv6_count = build_ipv6()
    print(f"Built {ipv4_count} IPv4 ranges and {ipv6_count} IPv6 ranges from {VERSION}")


if __name__ == "__main__":
    main()
