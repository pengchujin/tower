#!/usr/bin/env python3

import importlib.util
import json
import unittest
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve().parents[1] / "check_upstream_updates.py"
MANIFEST_PATH = Path(__file__).resolve().parents[1] / "upstream_sources.json"
SPEC = importlib.util.spec_from_file_location("check_upstream_updates", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
upstream = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(upstream)

TELEGRAM_PAGE = b"""
<div class="tgme_widget_message" data-post="QuanXNews/442">
  <div class="tgme_widget_message_text js-message_text" dir="auto">Old &amp; <b>bold</b></div>
  <time datetime="2026-11-01T10:00:00+00:00" class="time">10:00</time>
</div>
<div class="tgme_widget_message" data-post="QuanXNews/443">
  <div class="tgme_widget_message_text js-message_text" dir="auto">#TestFlight 1.9.0<br/>line two</div>
  <time datetime="2026-11-09T08:00:00+00:00" class="time">08:00</time>
</div>
"""


class CheckUpstreamUpdatesTests(unittest.TestCase):
    def test_telegram_preview_yields_newest_post_with_plain_text(self) -> None:
        result = upstream.parse_telegram(TELEGRAM_PAGE)
        self.assertEqual(result["version"], "443")
        self.assertEqual([p["id"] for p in result["posts"]], [442, 443])
        self.assertEqual(result["posts"][0]["text"], "Old & bold")
        self.assertEqual(result["posts"][1]["text"], "#TestFlight 1.9.0 line two")
        self.assertEqual(result["posts"][1]["date"], "2026-11-09")
        self.assertEqual(result["posts"][1]["url"], "https://t.me/QuanXNews/443")

    def test_telegram_page_without_posts_is_an_error(self) -> None:
        with self.assertRaises(ValueError):
            upstream.parse_telegram(b"<html>no preview</html>")

    def test_github_reports_prerelease_only_when_newer_than_stable(self) -> None:
        releases = [
            {"tag_name": "v1.20.0-alpha", "prerelease": True, "published_at": "2026-11-05T00:00:00Z", "html_url": "a"},
            {"tag_name": "v1.19.31", "prerelease": False, "published_at": "2026-10-01T00:00:00Z", "html_url": "s"},
            {"tag_name": "draft", "draft": True, "prerelease": False, "published_at": "2026-11-08T00:00:00Z"},
        ]
        result = upstream.parse_github_releases(json.dumps(releases).encode())
        self.assertEqual(result["version"], "v1.19.31")
        self.assertEqual(result["prerelease"]["tag"], "v1.20.0-alpha")

        older_pre = [releases[1], {**releases[0], "published_at": "2026-09-01T00:00:00Z"}]
        self.assertNotIn("prerelease", upstream.parse_github_releases(json.dumps(older_pre).encode()))

    def test_appstore_lookup_without_results_is_an_error(self) -> None:
        with self.assertRaises(ValueError):
            upstream.parse_appstore(b'{"resultCount":0,"results":[]}')
        app = upstream.parse_appstore(json.dumps({"results": [{
            "version": "2.2.93", "currentVersionReleaseDate": "2026-10-29T07:00:00Z",
            "releaseNotes": "fix", "trackViewUrl": "https://apps.apple.com/us/app/x/id1?uo=4",
        }]}).encode())
        self.assertEqual((app["version"], app["date"], app["url"]), ("2.2.93", "2026-10-29", "https://apps.apple.com/us/app/x/id1"))

    def test_appcast_picks_highest_build_and_decodes_unix_dates(self) -> None:
        feed = b"""<rss><channel>
<item><title>Version 6.10.0</title><markdownDescription><![CDATA[- Old]]></markdownDescription>
<pubDate>1791818674</pubDate><enclosure sparkle:version="12500" sparkle:shortVersionString="6.10.0"/></item>
<item><title>Version 6.11.0</title><markdownDescription><![CDATA[### Dashboard
- New **Breakdown**]]></markdownDescription>
<pubDate>1794146955</pubDate><enclosure sparkle:version="12750" sparkle:shortVersionString="6.11.0"/></item>
</channel></rss>"""
        result = upstream.parse_appcast(feed)
        self.assertEqual(result["version"], "6.11.0 (12750)")
        self.assertEqual(result["date"], "2026-11-08")
        self.assertIn("Breakdown", result["notes"])

    def test_rolling_release_version_is_newest_asset_upload(self) -> None:
        release = {"tag_name": "Prerelease-Alpha", "published_at": "2024-08-12T00:00:00Z", "html_url": "u",
                   "assets": [{"name": "a", "updated_at": "2026-11-01T00:00:00Z"},
                              {"name": "b", "updated_at": "2026-11-06T03:00:00Z"}]}
        result = upstream.parse_github_rolling(json.dumps(release).encode())
        self.assertEqual(result["version"], "2026-11-06T03:00:00Z")
        self.assertEqual(result["date"], "2026-11-06")

    def test_testflight_status(self) -> None:
        self.assertEqual(upstream.parse_testflight(b"<p>This beta is full.</p>")["version"], "full")
        self.assertEqual(upstream.parse_testflight(b"<p>This beta isn't accepting any new testers right now.</p>")["version"], "closed")
        self.assertEqual(upstream.parse_testflight(b"<h1>Join the Loon beta</h1>")["version"], "open")
        self.assertEqual(upstream.parse_testflight("<title>加入 Beta 版“Karing”</title><p>此 Beta 版本的测试员已满。</p>".encode())["version"], "full")
        self.assertEqual(upstream.parse_testflight("<h1>加入 Beta 版“Hiddify”</h1>".encode())["version"], "open")
        watch = {"type": "testflight", "url": "u"}
        self.assertFalse(upstream.changed(watch, {"version": "full"}, {"version": "unknown"}))

    def test_page_hash_ignores_scripts_and_whitespace(self) -> None:
        a = upstream.parse_page(b"<p>Hello   world</p><script>var t=1</script>")
        b = upstream.parse_page(b"<p>Hello world</p>\n<script>var t=2</script>")
        self.assertEqual(a["version"], b["version"])

    def test_telegram_change_lists_only_posts_after_the_stored_id(self) -> None:
        watch = {"type": "telegram", "channel": "QuanXNews"}
        new = upstream.parse_telegram(TELEGRAM_PAGE)
        lines = upstream.describe_change(watch, {"version": "442"}, new)
        self.assertIn("1 条", lines[0])
        self.assertIn("QuanXNews/443", lines[1])

    def test_manifest_is_well_formed(self) -> None:
        manifest = json.loads(MANIFEST_PATH.read_text())
        ids = [s["id"] for s in manifest["sources"]]
        self.assertEqual(len(ids), len(set(ids)), "duplicate source id")
        required = {"appstore": "id", "github": "repo", "appcast": "url", "telegram": "channel", "testflight": "url", "page": "url"}
        keys = set()
        for source in manifest["sources"]:
            self.assertIn(source["kind"], {"client", "core", "converter", "protocol"}, source["id"])
            for watch in source.get("watch", []):
                self.assertIn(required[watch["type"]], watch, source["id"])
                key = upstream.watch_key(source, watch)
                self.assertNotIn(key, keys)
                keys.add(key)
            for url in [w.get("url") for w in source.get("watch", [])] + list(source.get("links", {}).values()):
                if url:
                    self.assertTrue(url.startswith("https://"), url)

    def test_every_client_target_is_covered(self) -> None:
        manifest = json.loads(MANIFEST_PATH.read_text())
        covered = {t for s in manifest["sources"] for t in s.get("targets", [])}
        swift = (Path(__file__).resolve().parents[2] / "Tower" / "Models" / "DomainModels.swift").read_text()
        body = swift.split("enum ClientTarget:", 1)[1].split("var id: String", 1)[0]
        import re
        cases = set()
        for name, raw in re.findall(r"case (\w+)(?: = \"([^\"]+)\")?", body):
            cases.add(raw or name)
        self.assertEqual(cases - covered, set(), "ClientTarget without an upstream source")


if __name__ == "__main__":
    unittest.main()
