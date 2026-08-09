#!/usr/bin/env python3
"""Vendor the ACL4SSR remote configs and their rule lists as local snapshots.

The three configs offered at https://acl4ssr-sub.github.io differ mainly in how
many policy groups they declare, so each one is stored verbatim together with
every `.list` it references. Everything is pinned to one revision, hashed, and
recorded in manifest.json so a snapshot can be verified without network access.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tempfile
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ACL4SSR_REVISION = "06ff293e02565adceef9aa92321efa2603f68f32"
RAW_BASE = "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR"
# Keeps every ACL4SSR snapshot identifiable in Xcode's flat bundle namespace
# and lets RuleRepository ignore them.
RESOURCE_PREFIX = "ACL4SSR_"

# id -> (file name in the repo, display name, summary)
CONFIGS = {
    "acl4ssr-default": (
        "ACL4SSR_Online.ini",
        "ACL4SSR 默认",
        "去广告、自动测速，含国外媒体、电报、微软和苹果分流。",
    ),
    "acl4ssr-mini": (
        "ACL4SSR_Online_Mini.ini",
        "ACL4SSR 精简",
        "只保留节点选择、自动选择、直连与拦截，策略组最少。",
    ),
    "acl4ssr-full": (
        "ACL4SSR_Online_Full.ini",
        "ACL4SSR 全分组",
        "最完整的分组：流媒体、AI、游戏、音乐，并按节点名分出地区组。",
    ),
}

ROOT = Path(__file__).resolve().parent.parent
DESTINATION = ROOT / "Tower" / "Resources" / "ACL4SSR"


def fetch(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": "Tower ACL4SSR snapshot updater"})
    with urlopen(request, timeout=30) as response:
        return response.read()


def config_url(file_name: str, revision: str) -> str:
    return f"{RAW_BASE}/{revision}/Clash/config/{file_name}"


def pinned(url: str, revision: str) -> str:
    """Repoint a master URL at the pinned revision so snapshots stay reproducible."""
    master_prefix = f"{RAW_BASE}/master/"
    if url.startswith(master_prefix):
        return f"{RAW_BASE}/{revision}/" + url[len(master_prefix) :]
    return url


def ruleset_urls(config_text: str, revision: str) -> list[str]:
    urls: list[str] = []
    for raw_line in config_text.splitlines():
        line = raw_line.strip()
        if not line.startswith("ruleset="):
            continue
        _, _, value = line.partition("=")
        _, _, target = value.partition(",")
        target = target.strip()
        if target.startswith("[]"):
            continue
        if target.startswith("http"):
            resolved = pinned(target, revision)
            if resolved not in urls:
                urls.append(resolved)
    return urls


def local_name(url: str) -> str:
    """Flatten a rule list URL into a unique, filesystem-safe file name.

    Xcode copies resources into the bundle root. The prefix keeps the origin
    explicit and avoids collisions with future bundled resources.
    """
    tail = url.split("/Clash/", 1)[-1]
    return RESOURCE_PREFIX + tail.replace("/", "_")


def count_rules(text: str) -> int:
    total = 0
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if line and not line.startswith("#") and not line.startswith(";"):
            total += 1
    return total


def build(revision: str) -> None:
    staging = Path(tempfile.mkdtemp(prefix="tower-acl4ssr-"))
    manifest: dict[str, object] = {"revision": revision, "configs": {}, "rulesets": {}}

    try:
        for scheme_id, (file_name, display_name, summary) in CONFIGS.items():
            url = config_url(file_name, revision)
            print(f"config  {file_name}")
            payload = fetch(url)
            text = payload.decode("utf-8-sig")

            # Rewrite master URLs to the pinned revision so the copy that ships
            # inside the app resolves to exactly what was hashed here.
            pinned_text = text.replace(f"{RAW_BASE}/master/", f"{RAW_BASE}/{revision}/")
            (staging / file_name).write_text(pinned_text, encoding="utf-8")

            manifest["configs"][scheme_id] = {
                "file": file_name,
                "name": display_name,
                "summary": summary,
                "source": url,
                "sha256": hashlib.sha256(pinned_text.encode("utf-8")).hexdigest(),
            }

            for ruleset_url in ruleset_urls(pinned_text, revision):
                name = local_name(ruleset_url)
                if name in manifest["rulesets"]:
                    continue
                print(f"  rule  {name}")
                try:
                    body = fetch(ruleset_url).decode("utf-8-sig")
                except (HTTPError, URLError) as error:
                    raise SystemExit(f"下载失败 {ruleset_url}: {error}") from error
                (staging / name).write_text(body, encoding="utf-8")
                manifest["rulesets"][name] = {
                    "source": ruleset_url,
                    "ruleCount": count_rules(body),
                    "sha256": hashlib.sha256(body.encode("utf-8")).hexdigest(),
                }

        # Prefixed for the same reason as the rule lists: the flat bundle should
        # retain an origin-specific manifest name.
        (staging / f"{RESOURCE_PREFIX}manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        # Replace atomically so a failed download never leaves a half-written
        # snapshot behind in the app resources.
        if DESTINATION.exists():
            shutil.rmtree(DESTINATION)
        DESTINATION.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(staging), str(DESTINATION))
        staging = None  # moved
    finally:
        if staging is not None and staging.exists():
            shutil.rmtree(staging, ignore_errors=True)

    print(
        f"\n完成：{len(manifest['configs'])} 份配置，"
        f"{len(manifest['rulesets'])} 个规则文件 -> {DESTINATION}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--revision",
        default=ACL4SSR_REVISION,
        help="ACL4SSR/ACL4SSR 的提交号，默认使用脚本里固定的版本。",
    )
    build(parser.parse_args().revision)


if __name__ == "__main__":
    main()
