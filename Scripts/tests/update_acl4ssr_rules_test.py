#!/usr/bin/env python3

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "update_acl4ssr_rules.py"
SPEC = importlib.util.spec_from_file_location("update_acl4ssr_rules", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
updater = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updater)


class UpdateACL4SSRRulesTests(unittest.TestCase):
    def test_latest_revision_resolves_the_upstream_head_sha(self) -> None:
        expected = "1234567890abcdef1234567890abcdef12345678"

        def fetcher(url: str) -> bytes:
            self.assertEqual(url, updater.LATEST_REVISION_URL)
            return json.dumps({"sha": expected}).encode()

        self.assertEqual(updater.latest_revision(fetcher=fetcher), expected)

    def test_release_check_rejects_a_stale_snapshot_without_rewriting_it(self) -> None:
        current = "1234567890abcdef1234567890abcdef12345678"
        latest = "abcdef1234567890abcdef1234567890abcdef12"
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            manifest = destination / "ACL4SSR_manifest.json"
            manifest.write_text(json.dumps({"revision": current}), encoding="utf-8")
            original = manifest.read_bytes()

            with self.assertRaisesRegex(SystemExit, "内置 ACL4SSR 规则不是最新版本"):
                updater.check_latest_snapshot(
                    destination=destination,
                    fetcher=lambda _: json.dumps({"sha": latest}).encode(),
                )

            self.assertEqual(manifest.read_bytes(), original)

    def test_check_latest_cli_accepts_the_current_snapshot_without_building(self) -> None:
        revision = "1234567890abcdef1234567890abcdef12345678"
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            (destination / "ACL4SSR_manifest.json").write_text(
                json.dumps({"revision": revision}),
                encoding="utf-8",
            )

            updater.main(
                ["--check-latest"],
                destination=destination,
                fetcher=lambda _: json.dumps({"sha": revision}).encode(),
            )

    def test_latest_cli_builds_an_immutable_snapshot_of_upstream_head(self) -> None:
        revision = "abcdef1234567890abcdef1234567890abcdef12"
        built_revisions: list[str] = []

        updater.main(
            ["--latest"],
            fetcher=lambda _: json.dumps({"sha": revision}).encode(),
            builder=built_revisions.append,
        )

        self.assertEqual(built_revisions, [revision])

    def test_snapshot_build_keeps_the_license_notice_with_the_new_revision(self) -> None:
        revision = "abcdef1234567890abcdef1234567890abcdef12"
        config_name = "Test.ini"
        config = (
            "ruleset=测试,"
            f"{updater.RAW_BASE}/master/Clash/Test.list\n"
            "custom_proxy_group=测试`select`[]DIRECT\n"
        ).encode()

        def fetcher(url: str) -> bytes:
            if url == updater.config_url(config_name, revision):
                return config
            if url.endswith("/Clash/Test.list"):
                return b"DOMAIN-SUFFIX,example.com\n"
            raise AssertionError(f"unexpected URL: {url}")

        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "ACL4SSR"
            updater.build(
                revision,
                destination=destination,
                fetcher=fetcher,
                configs={"test": (config_name, "测试", "测试规则")},
            )

            notice = (destination / "ACL4SSR_NOTICE.txt").read_text(encoding="utf-8")
            self.assertIn("License:     CC BY-SA 4.0", notice)
            self.assertIn(f"Revision:    {revision}", notice)


if __name__ == "__main__":
    unittest.main()
