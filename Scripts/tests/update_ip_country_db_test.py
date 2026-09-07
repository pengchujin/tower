#!/usr/bin/env python3
"""Offline resource integrity tests; no network or private node fixtures."""
import importlib.util
from pathlib import Path
import struct
import hashlib
import json
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("builder", Path(__file__).resolve().parents[1] / "update_ip_country_db.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class OfflineIPBuilderTests(unittest.TestCase):
    def test_country_preserves_gaps_and_merges_identical_neighbors(self):
        result = builder.build_country(b"1,2,SG\n3,4,SG\n6,6,SG\n7,8,GB\n", 4)
        self.assertEqual(list(struct.iter_unpack(">II2s", result)), [(1, 4, b"SG"), (6, 6, b"SG"), (7, 8, b"GB")])

    def test_rejects_overlap_unsorted_out_of_range_and_country(self):
        for data in [b"1,2,SG\n2,4,SG\n", b"3,4,GB\n1,2,SG\n", b"0,4294967296,SG\n", b"1,2,sg\n"]:
            with self.subTest(data=data), self.assertRaises(ValueError):
                builder.build_country(data, 4)

    def test_shared_utf8_pool_offsets_across_families(self):
        pool, offsets = bytearray(), {}
        v4 = builder.build_asn('1,2,13335,"Cloudflare, Inc."\n3,4,42,测试\n'.encode(), 4, pool, offsets)
        before = bytes(pool)
        v6 = builder.build_asn('2001:db8::,2001:db8::ff,42,测试\n'.encode(), 6, pool, offsets)
        self.assertEqual(bytes(pool), before)
        self.assertEqual(len(v4), 36)
        self.assertEqual(len(v6), 42)
        asn, offset, length = struct.unpack(">IIH", v6[32:])
        self.assertEqual(asn, 42)
        self.assertEqual(pool[offset:offset + length].decode(), '测试')
        self.assertEqual(length, 6)

    def test_country_ipv6_layout_and_boundaries(self):
        result = builder.build_country(b"2001:db8::,2001:db8::ff,SG\n", 6)
        self.assertEqual(len(result), 34)
        self.assertEqual(result[-2:], b"SG")
        self.assertEqual(int.from_bytes(result[16:32], 'big') - int.from_bytes(result[:16], 'big'), 255)

    def test_asn_invalid_and_oversized_names_rejected(self):
        for number in [0, -1, 2**32]:
            with self.subTest(number=number), self.assertRaises(ValueError):
                builder.build_asn(f"1,2,{number},Name\n".encode(), 4, bytearray(), {})
        with self.assertRaises(ValueError):
            builder.build_asn(('1,2,1,' + 'a' * 65536).encode(), 4, bytearray(), {})

    def test_hash_mismatch_does_not_accept_different_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            filename = next(iter(builder.SOURCES))
            (Path(directory) / filename).write_bytes(b"not the pinned release")
            with self.assertRaises(ValueError):
                builder.source_bytes(filename, Path(directory))

    def test_bundled_manifest_and_all_name_references(self):
        root = builder.OUTPUT_ROOT
        manifest = json.loads((root / "IPCountryManifest.json").read_text())
        for filename, expected in manifest["artifacts"].items():
            data = (root / filename).read_bytes()
            self.assertEqual(len(data), expected["bytes"])
            self.assertEqual(hashlib.sha256(data).hexdigest(), expected["sha256"])
        names = (root / "IPASNNames.bin").read_bytes()
        checked = set()
        for family, width, address_width in [(4, 18, 4), (6, 42, 16)]:
            data = (root / f"IPASNIPv{family}.bin").read_bytes()
            self.assertEqual(len(data) % width, 0)
            previous_end = -1
            for record in range(0, len(data), width):
                start = int.from_bytes(data[record:record + address_width], "big")
                end = int.from_bytes(data[record + address_width:record + 2 * address_width], "big")
                self.assertGreater(start, previous_end)
                self.assertGreaterEqual(end, start)
                previous_end = end
                number, offset, length = struct.unpack_from(">IIH", data, record + 2 * address_width)
                self.assertGreater(number, 0)
                self.assertLessEqual(offset + length, len(names))
                if (offset, length) not in checked:
                    names[offset:offset + length].decode("utf-8")
                    checked.add((offset, length))


if __name__ == '__main__':
    unittest.main()
