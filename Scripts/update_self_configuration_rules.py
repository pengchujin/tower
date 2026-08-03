#!/usr/bin/env python3
"""Vendor Self-Configuration rule providers as deterministic local .list files."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
from urllib.parse import quote, unquote
from urllib.request import Request, urlopen


SELF_CONFIGURATION_REVISION = "fb658cc85802427b749a8a7da52e7b36580d6f1d"
DLER_RULES_REVISION = "1bfdc7d39e329cab2d2c50d391a3faaadb6a7e30"
BLACKMATRIX_REVISION = "dab47069a30c4ae70f7f5f4c919d639d9aaf79dc"
CONFIG_URL = (
    "https://raw.githubusercontent.com/ClashConnectRules/Self-Configuration/"
    f"{SELF_CONFIGURATION_REVISION}/Clash.yaml"
)


def fetch(url: str) -> str:
    request = Request(url, headers={"User-Agent": "Tower rule snapshot updater"})
    with urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8-sig")


def provider_urls(config: str) -> dict[str, str]:
    section = config.split("\nrule-providers:\n", 1)[1]
    current_name: str | None = None
    result: dict[str, str] = {}
    for line in section.splitlines():
        name_match = re.match(r"^  ([^#][^:]+):\s*$", line)
        if name_match:
            current_name = name_match.group(1).strip()
            continue
        url_match = re.match(r"^    url:\s*['\"]([^'\"]+)['\"]\s*$", line)
        if current_name and url_match:
            result[current_name] = pinned_url(url_match.group(1))
    return result


def pinned_url(url: str) -> str:
    dler_marker = "/gh/dler-io/Rules@main/"
    if dler_marker in url:
        path = quote(unquote(url.split(dler_marker, 1)[1]), safe="/+")
        return (
            "https://raw.githubusercontent.com/dler-io/Rules/"
            f"{DLER_RULES_REVISION}/{path}"
        )

    blackmatrix_marker = "/blackmatrix7/ios_rule_script/master/"
    if blackmatrix_marker in url:
        return url.replace(
            blackmatrix_marker,
            f"/blackmatrix7/ios_rule_script/{BLACKMATRIX_REVISION}/",
        )
    raise ValueError(f"Unsupported provider URL: {url}")


def rules_from_provider(content: str) -> list[str]:
    rules: list[str] = []
    in_payload = False
    for raw_line in content.splitlines():
        if raw_line.strip() == "payload:":
            in_payload = True
            continue
        if not in_payload:
            continue
        match = re.match(r"^\s*-\s+(.+?)\s*$", raw_line)
        if not match:
            continue
        value = match.group(1)
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        if value and not value.startswith("#"):
            rules.append(value)
    return rules


def write_snapshot(destination: Path) -> None:
    config = fetch(CONFIG_URL)
    providers = provider_urls(config)
    if len(providers) < 60:
        raise RuntimeError(f"Expected at least 60 rule providers, found {len(providers)}")

    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix="Tower-SelfConfiguration-", dir=destination.parent))
    manifest: dict[str, object] = {
        "selfConfigurationRevision": SELF_CONFIGURATION_REVISION,
        "dlerRulesRevision": DLER_RULES_REVISION,
        "blackmatrixRevision": BLACKMATRIX_REVISION,
        "providers": {},
    }
    try:
        for name, url in providers.items():
            content = fetch(url)
            rules = rules_from_provider(content)
            if not rules:
                raise RuntimeError(f"Provider {name} contained no rules")
            output = (
                f"# Source: {url}\n"
                f"# Snapshot for Self-Configuration {SELF_CONFIGURATION_REVISION[:12]}\n"
                + "\n".join(rules)
                + "\n"
            )
            (staging / f"{name}.list").write_text(output, encoding="utf-8")
            manifest["providers"][name] = {
                "source": url,
                "ruleCount": len(rules),
                "sha256": hashlib.sha256(output.encode()).hexdigest(),
            }

        (staging / "GeoIP CN.list").write_text(
            f"# Source: {CONFIG_URL}\nGEOIP,CN\n",
            encoding="utf-8",
        )
        (staging / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        (staging / "SelfConfiguration-NOTICE.txt").write_text(
            "Rules selected by ClashConnectRules/Self-Configuration.\n"
            f"Configuration revision: {SELF_CONFIGURATION_REVISION}\n"
            f"dler-io/Rules revision: {DLER_RULES_REVISION}\n"
            f"blackmatrix7/ios_rule_script revision: {BLACKMATRIX_REVISION}\n"
            "See manifest.json for the exact source of every bundled provider.\n",
            encoding="utf-8",
        )

        backup = destination.with_name(destination.name + ".previous")
        if backup.exists():
            shutil.rmtree(backup)
        if destination.exists():
            os.replace(destination, backup)
        os.replace(staging, destination)
        if backup.exists():
            shutil.rmtree(backup)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise


if __name__ == "__main__":
    workspace = Path(__file__).resolve().parents[1]
    write_snapshot(workspace / "Tower" / "Resources" / "SelfConfiguration")
