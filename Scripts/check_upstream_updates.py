#!/usr/bin/env python3
"""Check Tower's upstream clients, cores and protocols for new releases.

The source list lives in ``Scripts/upstream_sources.json`` (see
``docs/UPSTREAM_SOURCES.md``). Each source has watch entries of these types:

- ``appstore``: iTunes lookup API (version, release date, release notes)
- ``github``: GitHub Releases (latest stable and latest prerelease); with
  ``"tag"`` it watches one rolling release (e.g. mihomo ``Prerelease-Alpha``)
  by its newest asset upload, because such releases keep an old date; list
  that tag in ``"exclude"`` on the plain watch of the same repo
- ``appcast``: Sparkle feed (Surge Mac stable / beta)
- ``telegram``: public channel preview ``https://t.me/s/<channel>``
- ``testflight``: public join page (open / full / closed)
- ``page``: hash of a docs or changelog page's visible text

The script only reads public pages. It sends no subscriptions, nodes or
configurations anywhere. The previous result is kept in
``.artifacts/upstream-state.json`` (ignored by git), and the report lists only
what changed since then. Use ``--all`` to list every current value.

Set GITHUB_TOKEN (or log in with ``gh``) to avoid the 60 requests/hour
unauthenticated GitHub limit.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import hashlib
import html
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

PROJECT_ROOT = Path(__file__).resolve().parents[1]
MANIFEST = PROJECT_ROOT / "Scripts" / "upstream_sources.json"
STATE = PROJECT_ROOT / ".artifacts" / "upstream-state.json"
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) TowerUpstreamCheck/1.0"
TIMEOUT = 20
SNIPPET = 160


# ---------------------------------------------------------------- fetching


def fetch(url: str, headers: dict[str, str] | None = None) -> bytes:
    request = urllib.request.Request(url, headers={
        "User-Agent": USER_AGENT,
        "Accept-Language": "en-US,en;q=0.9",
        **(headers or {}),
    })
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return response.read()


def github_token() -> str | None:
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        return token
    try:
        result = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout.strip() or None


def plain_text(fragment: str) -> str:
    fragment = re.sub(r"<br\s*/?>", "\n", fragment, flags=re.I)
    fragment = re.sub(r"<[^>]+>", "", fragment)
    return re.sub(r"[ \t\r\f\v]+", " ", html.unescape(fragment)).strip()


def snippet(text: str | None) -> str:
    text = " ".join((text or "").split())
    return text if len(text) <= SNIPPET else text[: SNIPPET - 1] + "…"


# ---------------------------------------------------------------- parsers (pure, tested offline)


def parse_appstore(payload: bytes) -> dict[str, Any]:
    results = json.loads(payload).get("results") or []
    if not results:
        raise ValueError("App Store lookup returned no result (removed or not sold in this country)")
    app = results[0]
    return {
        "version": app.get("version"),
        "date": (app.get("currentVersionReleaseDate") or "")[:10],
        "notes": snippet(app.get("releaseNotes")),
        "url": app.get("trackViewUrl", "").split("?")[0],
    }


def parse_github_releases(payload: bytes, exclude: tuple[str, ...] = ()) -> dict[str, Any]:
    releases = [r for r in json.loads(payload) if not r.get("draft") and r.get("tag_name") not in exclude]
    stable = next((r for r in releases if not r.get("prerelease")), None)
    pre = next((r for r in releases if r.get("prerelease")), None)

    def describe(release: dict[str, Any] | None) -> dict[str, Any] | None:
        if not release:
            return None
        return {
            "tag": release.get("tag_name"),
            "date": (release.get("published_at") or "")[:10],
            "url": release.get("html_url"),
        }

    result = {"version": (stable or {}).get("tag_name"), "stable": describe(stable)}
    # Only report a prerelease that is newer than the stable release.
    if pre and (not stable or (pre.get("published_at") or "") > (stable.get("published_at") or "")):
        result["prerelease"] = describe(pre)
    return result


def parse_github_rolling(payload: bytes) -> dict[str, Any]:
    release = json.loads(payload)
    updated = max((a.get("updated_at") or "" for a in release.get("assets", [])), default="")
    return {
        "version": updated or release.get("published_at"),
        "tag": release.get("tag_name"),
        "date": (updated or "")[:10],
        "url": release.get("html_url"),
        "assets": [a.get("name") for a in release.get("assets", [])][:6],
    }


_SPARKLE_ITEM = re.compile(r"<item>(?P<item>.*?)</item>", re.S)


def parse_appcast(payload: bytes) -> dict[str, Any]:
    text = payload.decode("utf-8", "replace")
    items = []
    for match in _SPARKLE_ITEM.finditer(text):
        item = match.group("item")
        short = re.search(r'sparkle:shortVersionString(?:="([^"]*)"|>([^<]*)<)', item)
        build = re.search(r'sparkle:version(?:="([^"]*)"|>([^<]*)<)', item)
        date = re.search(r"<pubDate>\s*([^<]*?)\s*</pubDate>", item)
        notes = re.search(r"<(?:markdownDescription|description)>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</", item, re.S)
        if not short and not build:
            continue
        raw_date = date.group(1) if date else ""
        if raw_date.isdigit():  # Surge writes a Unix timestamp instead of RFC 822
            raw_date = dt.datetime.fromtimestamp(int(raw_date), dt.timezone.utc).date().isoformat()
        items.append({
            "version": (short.group(1) or short.group(2)) if short else None,
            "build": int((build.group(1) or build.group(2)) or 0) if build else 0,
            "date": raw_date[:16],
            "notes": snippet(plain_text(notes.group(1))) if notes else "",
        })
    if not items:
        raise ValueError("appcast has no versioned items")
    newest = max(items, key=lambda i: i["build"])
    return {**newest, "version": f"{newest['version']} ({newest['build']})"}


def parse_github_tags(payload: bytes) -> dict[str, Any]:
    tags = json.loads(payload)
    return {"version": tags[0]["name"] if tags else None}


_TG_MESSAGE = re.compile(
    r'data-post="(?P<post>[^"]+/(?P<id>\d+))"(?P<body>.*?)(?=data-post="|\Z)', re.S
)
_TG_TEXT = re.compile(r'<div class="tgme_widget_message_text[^"]*"[^>]*>(?P<text>.*?)</div>', re.S)
_TG_TIME = re.compile(r'<time[^>]*datetime="(?P<time>[^"]+)"')


def parse_telegram(page: bytes) -> dict[str, Any]:
    posts = []
    for match in _TG_MESSAGE.finditer(page.decode("utf-8", "replace")):
        body = match.group("body")
        text = _TG_TEXT.search(body)
        time = _TG_TIME.search(body)
        posts.append({
            "id": int(match.group("id")),
            "url": "https://t.me/" + match.group("post"),
            "date": time.group("time")[:10] if time else "",
            "text": snippet(plain_text(text.group("text"))) if text else "",
        })
    if not posts:
        raise ValueError("no public posts (channel missing, private, or preview disabled)")
    posts.sort(key=lambda p: p["id"])
    return {"version": str(posts[-1]["id"]), "posts": posts}


def parse_testflight(page: bytes) -> dict[str, Any]:
    text = page.decode("utf-8", "replace")
    # Apple localizes the page by region, so match English and Chinese.
    if "This beta is full" in text or "测试员已满" in text:
        status = "full"
    elif ("isn't accepting any new testers" in text or "is not accepting any new testers" in text
          or "不接受任何新测试员" in text or "不接受新的测试员" in text):
        status = "closed"
    elif "Join the" in text or "To join the" in text or "加入 Beta 版" in text:
        status = "open"
    else:
        status = "unknown"
    title = re.search(r"<title>(.*?)</title>", text, re.S)
    return {"version": status, "title": snippet(plain_text(title.group(1))) if title else ""}


def parse_page(page: bytes) -> dict[str, Any]:
    text = page.decode("utf-8", "replace")
    text = re.sub(r"<(script|style|noscript)\b.*?</\1>", "", text, flags=re.S | re.I)
    visible = " ".join(plain_text(text).split())
    return {"version": hashlib.sha256(visible.encode()).hexdigest()[:12], "length": len(visible)}


# ---------------------------------------------------------------- checks


def check(watch: dict[str, Any], token: str | None) -> dict[str, Any]:
    kind = watch["type"]
    if kind == "appstore":
        country = watch.get("country", "us")
        return parse_appstore(fetch(f"https://itunes.apple.com/lookup?id={watch['id']}&country={country}"))
    if kind == "github":
        headers = {"Accept": "application/vnd.github+json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if watch.get("tag"):
            return parse_github_rolling(fetch(f"https://api.github.com/repos/{watch['repo']}/releases/tags/{watch['tag']}", headers))
        if watch.get("tags"):
            return parse_github_tags(fetch(f"https://api.github.com/repos/{watch['repo']}/tags?per_page=1", headers))
        return parse_github_releases(
            fetch(f"https://api.github.com/repos/{watch['repo']}/releases?per_page=10", headers),
            tuple(watch.get("exclude", ())),
        )
    if kind == "appcast":
        return parse_appcast(fetch(watch["url"]))
    if kind == "telegram":
        return parse_telegram(fetch(f"https://t.me/s/{watch['channel']}"))
    if kind == "testflight":
        return parse_testflight(fetch(watch["url"]))
    if kind == "page":
        return parse_page(fetch(watch["url"]))
    raise ValueError(f"unknown watch type {kind!r}")


def watch_key(source: dict[str, Any], watch: dict[str, Any]) -> str:
    target = watch.get("id") or watch.get("repo") or watch.get("channel") or watch.get("url")
    suffix = f"@{watch['country']}" if watch.get("country") else ""
    if watch.get("tag"):
        suffix += f"#{watch['tag']}"
    return f"{source['id']}:{watch['type']}:{target}{suffix}"


def describe_change(watch: dict[str, Any], old: dict[str, Any] | None, new: dict[str, Any]) -> list[str]:
    kind = watch["type"]
    lines: list[str] = []
    if kind == "appstore":
        lines.append(f"App Store {old.get('version') if old else '—'} → **{new['version']}** ({new['date']})")
        if new.get("notes"):
            lines.append(f"  > {new['notes']}")
    elif kind == "github" and watch.get("tag"):
        lines.append(f"GitHub `{watch['repo']}` 滚动发布 `{watch['tag']}` 重新构建（{new['date']}）{new['url']}")
    elif kind == "appcast":
        lines.append(f"{watch.get('label', 'Appcast')} {old.get('version') if old else '—'} → **{new['version']}** ({new['date']})")
        if new.get("notes"):
            lines.append(f"  > {new['notes']}")
    elif kind == "github":
        stable = new.get("stable")
        if stable:
            lines.append(f"GitHub `{watch['repo']}` {old.get('version') if old else '—'} → **{stable['tag']}** ({stable['date']}) {stable['url']}")
        elif new.get("version"):
            lines.append(f"GitHub `{watch['repo']}` tag {old.get('version') if old else '—'} → **{new['version']}**")
        pre = new.get("prerelease")
        if pre and pre != (old or {}).get("prerelease"):
            lines.append(f"  预发布 **{pre['tag']}** ({pre['date']}) {pre['url']}")
    elif kind == "telegram":
        last = int(old["version"]) if old and str(old.get("version", "")).isdigit() else 0
        fresh = [p for p in new["posts"] if p["id"] > last][-5:]
        lines.append(f"Telegram @{watch['channel']} 新消息 {len(fresh)} 条")
        lines += [f"  - [{p['date']}]({p['url']}) {p['text']}" for p in fresh]
    elif kind == "testflight":
        lines.append(f"TestFlight {old.get('version') if old else '—'} → **{new['version']}** {watch['url']}")
    elif kind == "page":
        lines.append(f"页面内容变化：{watch.get('label', '')} {watch['url']}")
    return lines


def changed(watch: dict[str, Any], old: dict[str, Any] | None, new: dict[str, Any]) -> bool:
    if old is None:
        return True
    # An unrecognized TestFlight page is not a status change.
    if watch["type"] == "testflight" and new.get("version") == "unknown":
        return False
    if watch["type"] == "github" and not watch.get("tag"):
        return old.get("version") != new.get("version") or old.get("prerelease") != new.get("prerelease")
    return old.get("version") != new.get("version")


def compact(watch: dict[str, Any], result: dict[str, Any]) -> dict[str, Any]:
    """Keep the state file small: Telegram only needs the newest id."""
    if watch["type"] == "telegram":
        return {"version": result["version"], "date": result["posts"][-1]["date"]}
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--manifest", type=Path, default=MANIFEST)
    parser.add_argument("--state", type=Path, default=STATE)
    parser.add_argument("--only", action="append", default=[], help="source id or kind (client/core/protocol/converter); repeatable")
    parser.add_argument("--type", action="append", default=[], help="watch type to run (appstore/github/appcast/telegram/testflight/page); repeatable")
    parser.add_argument("--all", action="store_true", help="list every value, not only changes")
    parser.add_argument("--dry-run", action="store_true", help="do not update the state file")
    parser.add_argument("--report", type=Path, help="also write the Markdown report to this file")
    parser.add_argument("--jobs", type=int, default=8)
    args = parser.parse_args(argv)

    manifest = json.loads(args.manifest.read_text())
    state = json.loads(args.state.read_text()) if args.state.exists() else {}
    first_run = not state
    token = github_token()

    jobs = []
    for source in manifest["sources"]:
        if args.only and source["id"] not in args.only and source.get("kind") not in args.only:
            continue
        for watch in source.get("watch", []):
            if args.type and watch["type"] not in args.type:
                continue
            jobs.append((source, watch))

    results: dict[str, tuple[dict, dict, dict[str, Any] | Exception]] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(check, watch, token): (source, watch) for source, watch in jobs}
        for future in concurrent.futures.as_completed(futures):
            source, watch = futures[future]
            try:
                outcome: dict[str, Any] | Exception = future.result()
            except (OSError, ValueError, KeyError) as error:  # OSError covers URLError and socket timeouts
                outcome = error
            results[watch_key(source, watch)] = (source, watch, outcome)

    today = dt.date.today().isoformat()
    sections: dict[str, list[str]] = {}
    failures: list[str] = []
    for key in sorted(results, key=lambda k: [s["id"] for s, _ in jobs].index(results[k][0]["id"])):
        source, watch, outcome = results[key]
        label = f"{source['name']}"
        if isinstance(outcome, Exception):
            failures.append(f"- {label} `{watch['type']}` {watch_key(source, watch).split(':', 2)[2]}: {outcome}")
            continue
        old = state.get(key)
        if changed(watch, old, outcome) or args.all:
            if not (first_run and not args.all):
                sections.setdefault(label, []).extend(describe_change(watch, old, outcome))
        if watch["type"] == "testflight" and outcome.get("version") == "unknown" and old:
            continue  # keep the last recognized status
        state[key] = {**compact(watch, outcome), "checked": today}

    out = [f"# 上游更新检查 {today}", ""]
    if first_run and not args.all:
        out.append(f"首次运行，已记录 {len(results) - len(failures)} 项基线；下次运行只列出变化。用 `--all` 查看当前全部版本。")
    elif not sections:
        out.append("没有变化。")
    for label, lines in sections.items():
        out.append(f"## {label}")
        out += lines
        out.append("")
    if failures:
        out += ["## 检查失败", *failures, ""]
    report = "\n".join(out).rstrip() + "\n"
    print(report)
    if args.report:
        args.report.write_text(report)
    if not args.dry_run:
        args.state.parent.mkdir(parents=True, exist_ok=True)
        args.state.write_text(json.dumps(state, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
