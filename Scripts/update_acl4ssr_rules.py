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
import ipaddress
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import NamedTuple
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ACL4SSR_REVISION = "a32b0cb86b8f14deb0599e99c2b29383b0a4ca6a"
RAW_BASE = "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR"
LATEST_REVISION_URL = "https://api.github.com/repos/ACL4SSR/ACL4SSR/commits/master"
MIHOMO_VERSION = "v1.19.30"
SING_BOX_VERSION = "1.14.0"
SING_BOX_SOURCE_FORMAT_VERSION = 2
ARTIFACT_REPOSITORY_RAW = "https://raw.githubusercontent.com/pengchujin/tower"
MRS_PUBLIC_BASE = f"{ARTIFACT_REPOSITORY_RAW}/main/Rulesets/ACL4SSR"
SRS_PUBLIC_BASE = MRS_PUBLIC_BASE
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
MRS_DESTINATION = ROOT / "Rulesets" / "ACL4SSR"


class MRSRuleInputs(NamedTuple):
    domain: tuple[str, ...]
    ipcidr: tuple[str, ...]
    residual_rule_count: int
    domain_source_rule_count: int
    ipcidr_source_rule_count: int
    domain_complete: bool
    ipcidr_complete: bool


class SRSRuleInputs(NamedTuple):
    source_rules: tuple[tuple[str, tuple[str, ...]], ...]
    input_rule_count: int
    residual_rule_count: int
    covered_rule_types: tuple[str, ...]


def fetch(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": "Tower ACL4SSR snapshot updater"})
    with urlopen(request, timeout=30) as response:
        return response.read()


def validated_revision(revision: str) -> str:
    """Return one normalized immutable Git commit, or fail before file writes."""
    if not isinstance(revision, str):
        raise SystemExit("ACL4SSR 提交号必须是 40 位十六进制 Git commit")
    normalized = revision.lower()
    if len(normalized) != 40 or any(
        character not in "0123456789abcdef" for character in normalized
    ):
        raise SystemExit("ACL4SSR 提交号必须是 40 位十六进制 Git commit")
    return normalized


def artifact_public_base(artifact_commit: str | None = None) -> str:
    """Return the staging or immutable Raw base for generated binaries."""
    reference = "main" if artifact_commit is None else validated_revision(artifact_commit)
    return f"{ARTIFACT_REPOSITORY_RAW}/{reference}/Rulesets/ACL4SSR"


def latest_revision(fetcher=fetch) -> str:
    """Resolve the current upstream head to an immutable Git commit."""
    try:
        payload = json.loads(fetcher(LATEST_REVISION_URL))
        revision = payload["sha"]
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit("无法解析 ACL4SSR 上游最新提交") from error
    try:
        return validated_revision(revision)
    except SystemExit as error:
        raise SystemExit("ACL4SSR 上游返回了无效的提交号") from error


def bundled_revision(destination: Path = DESTINATION) -> str:
    manifest_path = destination / f"{RESOURCE_PREFIX}manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        return manifest["revision"]
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        raise SystemExit(f"无法读取内置 ACL4SSR 清单：{manifest_path}") from error


def check_latest_snapshot(destination: Path = DESTINATION, fetcher=fetch) -> None:
    current = bundled_revision(destination)
    latest = latest_revision(fetcher=fetcher)
    if current != latest:
        raise SystemExit(
            "内置 ACL4SSR 规则不是最新版本。\n"
            "请按 docs/RELEASING.md 运行带 --mihomo 与 --sing-box 的 --latest 更新，"
            "完成测试并提交资源变更后再打包。"
        )
    print(f"ACL4SSR 内置规则已是上游最新提交：{current[:12]}")


def verify_published_artifacts(
    destination: Path = DESTINATION,
    fetcher=fetch,
) -> None:
    """Verify every released binary through its immutable public URL."""
    manifest_path = destination / f"{RESOURCE_PREFIX}manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        revision = validated_revision(manifest["revision"])
        artifact_commit = validated_revision(manifest["artifactCommit"])
        rulesets = manifest["rulesets"]
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        raise SystemExit(
            "ACL4SSR 清单尚未绑定不可变 artifactCommit，不得发布"
        ) from error

    base = artifact_public_base(artifact_commit)
    verified = 0
    for source_name, source_metadata in rulesets.items():
        artifacts: list[tuple[str, dict[str, object]]] = []
        for behavior, metadata in source_metadata.get("mrs", {}).items():
            artifacts.append((mrs_artifact_name(source_name, behavior), metadata))
        if "srs" in source_metadata:
            artifacts.append((srs_artifact_name(source_name), source_metadata["srs"]))

        for artifact_name, metadata in artifacts:
            expected_url = f"{base}/{revision}/{artifact_name}"
            expected_sha256 = metadata.get("sha256")
            if metadata.get("url") != expected_url:
                raise SystemExit(f"产物 URL 不是固定 commit 地址：{artifact_name}")
            if not isinstance(expected_sha256, str) or len(expected_sha256) != 64 or any(
                character not in "0123456789abcdef" for character in expected_sha256.lower()
            ):
                raise SystemExit(f"产物 SHA-256 无效：{artifact_name}")
            try:
                payload = fetcher(expected_url)
            except (HTTPError, URLError, OSError) as error:
                raise SystemExit(f"远程产物不可访问：{artifact_name}: {error}") from error
            actual_sha256 = hashlib.sha256(payload).hexdigest()
            if actual_sha256 != expected_sha256.lower():
                raise SystemExit(
                    f"远程产物摘要不一致：{artifact_name}\n"
                    f"期望 {expected_sha256.lower()}\n实际 {actual_sha256}"
                )
            verified += 1

    if verified == 0:
        raise SystemExit("ACL4SSR 清单中没有可验证的 MRS/SRS 产物")
    print(
        f"ACL4SSR 远程产物已全量验证：{verified} 个，"
        f"Tower commit {artifact_commit[:12]}"
    )


def config_url(file_name: str, revision: str) -> str:
    return f"{RAW_BASE}/{revision}/Clash/config/{file_name}"


def is_pinned_acl4ssr_ruleset(source_url: str, revision: str) -> bool:
    source_prefix = f"{RAW_BASE}/{revision}/Clash/"
    return source_url.startswith(source_prefix) and source_url.endswith(".list")


def classify_mrs_rules(text: str) -> MRSRuleInputs:
    """Split classical Clash rules into lossless MRS behavior inputs.

    Mihomo's ``domain`` text format does not accept classical lines verbatim:
    exact domains are bare values and suffixes use ``+.``. Its ``ipcidr`` text
    format similarly expects only the CIDR value. Types without a lossless
    domain/ipcidr representation stay residual and are emitted inline by Tower.
    One malformed rule disables that whole behavior. IP artifacts additionally
    require every source CIDR to carry exactly one ``no-resolve`` modifier so
    Tower can preserve DNS behavior without discarding other semantics.
    """
    domain: list[str] = []
    ipcidr: list[str] = []
    seen_domain: set[str] = set()
    seen_ipcidr: set[str] = set()
    residual_rule_count = 0
    domain_source_rule_count = 0
    ipcidr_source_rule_count = 0
    domain_complete = True
    ipcidr_complete = True

    def append_unique(value: str, values: list[str], seen: set[str]) -> None:
        if value not in seen:
            seen.add(value)
            values.append(value)

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue

        fields = [field.strip() for field in line.split(",")]
        rule_type = fields[0].upper()
        if rule_type in {"DOMAIN", "DOMAIN-SUFFIX"}:
            domain_source_rule_count += 1
            if len(fields) != 2 or not fields[1]:
                domain_complete = False
                continue
            value = fields[1]
        elif rule_type in {"IP-CIDR", "IP-CIDR6", "IP6-CIDR"}:
            ipcidr_source_rule_count += 1
            if len(fields) < 2 or not fields[1]:
                ipcidr_complete = False
                continue
            value = fields[1]
        else:
            residual_rule_count += 1
            continue

        if rule_type == "DOMAIN":
            append_unique(value, domain, seen_domain)
            continue
        if rule_type == "DOMAIN-SUFFIX":
            # Classical DOMAIN-SUFFIX values are bare suffixes. Accepting an
            # already-prefixed value would silently guess whether the prefix
            # belongs to the source syntax or the Mihomo behavior syntax.
            if value.startswith(".") or value.startswith("+."):
                domain_complete = False
                continue
            append_unique(f"+.{value}", domain, seen_domain)
            continue
        if rule_type in {"IP-CIDR", "IP-CIDR6", "IP6-CIDR"}:
            # Tower emits the resulting RULE-SET with no-resolve. Any missing
            # or additional parameter could change matching semantics, so the
            # whole IP behavior must remain inline instead of being guessed.
            if len(fields) != 3 or fields[2].lower() != "no-resolve":
                ipcidr_complete = False
            try:
                network = ipaddress.ip_network(value, strict=False)
            except ValueError:
                ipcidr_complete = False
            else:
                append_unique(str(network), ipcidr, seen_ipcidr)
            continue

        residual_rule_count += 1

    return MRSRuleInputs(
        domain=tuple(domain),
        ipcidr=tuple(ipcidr),
        residual_rule_count=residual_rule_count,
        domain_source_rule_count=domain_source_rule_count,
        ipcidr_source_rule_count=ipcidr_source_rule_count,
        domain_complete=domain_complete,
        ipcidr_complete=ipcidr_complete,
    )


def classify_srs_rules(text: str) -> SRSRuleInputs:
    """Build one lossless sing-box source-format rule from a classical list.

    Each source type is fail-closed independently. If one line of a type is
    malformed or has an unsupported modifier, that complete source type stays
    inline in Tower and is not named in ``coveredRuleTypes``. The three IP CIDR
    aliases share one sing-box field and therefore fail closed as one group.
    """
    type_order = (
        "DOMAIN",
        "DOMAIN-SUFFIX",
        "DOMAIN-KEYWORD",
        "IP-CIDR",
        "IP-CIDR6",
        "IP6-CIDR",
    )
    source_field = {
        "DOMAIN": "domain",
        "DOMAIN-SUFFIX": "domain_suffix",
        "DOMAIN-KEYWORD": "domain_keyword",
        "IP-CIDR": "ip_cidr",
        "IP-CIDR6": "ip_cidr",
        "IP6-CIDR": "ip_cidr",
    }
    values: dict[str, list[str]] = {rule_type: [] for rule_type in type_order}
    seen: dict[str, set[str]] = {rule_type: set() for rule_type in type_order}
    counts: dict[str, int] = {rule_type: 0 for rule_type in type_order}
    complete: dict[str, bool] = {rule_type: True for rule_type in type_order}
    total_rule_count = 0

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        total_rule_count += 1
        fields = [field.strip() for field in line.split(",")]
        rule_type = fields[0].upper()
        if rule_type not in source_field:
            continue

        counts[rule_type] += 1
        if len(fields) < 2 or not fields[1]:
            complete[rule_type] = False
            continue

        value = fields[1]
        if rule_type in {"DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD"}:
            if len(fields) != 2:
                complete[rule_type] = False
                continue
            if rule_type == "DOMAIN-SUFFIX" and (
                value.startswith(".") or value.startswith("+.")
            ):
                complete[rule_type] = False
                continue
            # sing-box matches queried domains case-insensitively but does not
            # normalize uppercase patterns while compiling source-format v2.
            value = value.lower()
        else:
            if len(fields) not in {2, 3} or (
                len(fields) == 3 and fields[2].lower() != "no-resolve"
            ):
                complete[rule_type] = False
                continue
            try:
                value = str(ipaddress.ip_network(value, strict=False))
            except ValueError:
                complete[rule_type] = False
                continue

        if value not in seen[rule_type]:
            seen[rule_type].add(value)
            values[rule_type].append(value)

    # All classical IP aliases map to the same source-format key. Publishing
    # only part of that family would make a malformed alias easy to overlook,
    # so any bad CIDR line leaves the entire IP family inline.
    ip_types = ("IP-CIDR", "IP-CIDR6", "IP6-CIDR")
    ip_complete = all(complete[rule_type] for rule_type in ip_types)
    covered_types: list[str] = []
    source_values: dict[str, list[str]] = {}
    input_rule_count = 0
    for rule_type in type_order:
        if counts[rule_type] == 0:
            continue
        if rule_type in ip_types:
            if not ip_complete:
                continue
        elif not complete[rule_type]:
            continue
        covered_types.append(rule_type)
        input_rule_count += counts[rule_type]
        field = source_field[rule_type]
        source_values.setdefault(field, []).extend(values[rule_type])

    source_rules = tuple(
        (field, tuple(source_values[field]))
        for field in ("domain", "domain_suffix", "domain_keyword", "ip_cidr")
        if source_values.get(field)
    )
    return SRSRuleInputs(
        source_rules=source_rules,
        input_rule_count=input_rule_count,
        residual_rule_count=total_rule_count - input_rule_count,
        covered_rule_types=tuple(covered_types),
    )


def verify_mihomo(
    mihomo_path: Path,
    expected_version: str,
    runner=subprocess.run,
) -> str:
    """Verify the caller-supplied compiler and return the pinned version."""
    if not mihomo_path.is_file() or not os.access(mihomo_path, os.X_OK):
        raise SystemExit(f"Mihomo 编译器不存在或不可执行：{mihomo_path}")

    try:
        result = runner(
            [str(mihomo_path), "-v"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as error:
        raise SystemExit(f"无法运行 Mihomo 编译器：{error}") from error

    version_output = "\n".join(
        part.strip() for part in (result.stdout, result.stderr) if part.strip()
    )
    if result.returncode != 0 or expected_version not in version_output.split():
        raise SystemExit(
            f"Mihomo 版本不匹配：需要 {expected_version}，实际输出 "
            f"{version_output or '<empty>'}"
        )
    return expected_version


def verify_sing_box(
    sing_box_path: Path,
    expected_version: str,
    runner=subprocess.run,
) -> str:
    """Verify the explicitly supplied sing-box compiler version."""
    if not sing_box_path.is_file() or not os.access(sing_box_path, os.X_OK):
        raise SystemExit(f"sing-box 编译器不存在或不可执行：{sing_box_path}")

    try:
        result = runner(
            [str(sing_box_path), "version"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as error:
        raise SystemExit(f"无法运行 sing-box 编译器：{error}") from error

    version_output = "\n".join(
        part.strip() for part in (result.stdout, result.stderr) if part.strip()
    )
    expected_line = f"sing-box version {expected_version}"
    if result.returncode != 0 or expected_line not in version_output.splitlines():
        raise SystemExit(
            f"sing-box 版本不匹配：需要 {expected_version}，实际输出 "
            f"{version_output or '<empty>'}"
        )
    return expected_version


def canonical_domain_rules(rules: tuple[str, ...]) -> tuple[frozenset[str], frozenset[str]]:
    exact = {rule.lower() for rule in rules if not rule.startswith("+.")}
    suffixes = {rule[2:].lower() for rule in rules if rule.startswith("+.")}
    minimal_suffixes = {
        suffix
        for suffix in suffixes
        if not any(
            suffix != other and suffix.endswith(f".{other}")
            for other in suffixes
        )
    }
    uncovered_exact = {
        domain
        for domain in exact
        if not any(
            domain == suffix or domain.endswith(f".{suffix}")
            for suffix in minimal_suffixes
        )
    }
    return frozenset(uncovered_exact), frozenset(minimal_suffixes)


def canonical_ipcidr_rules(rules: tuple[str, ...]) -> tuple[str, ...]:
    networks = [ipaddress.ip_network(rule, strict=False) for rule in rules]
    collapsed: list[ipaddress.IPv4Network | ipaddress.IPv6Network] = []
    for version in (4, 6):
        collapsed.extend(
            ipaddress.collapse_addresses(
                network for network in networks if network.version == version
            )
        )
    return tuple(
        str(network)
        for network in sorted(
            collapsed,
            key=lambda network: (network.version, int(network.network_address), network.prefixlen),
        )
    )


def mrs_rules_equivalent(
    behavior: str,
    source_rules: tuple[str, ...],
    dumped_rules: tuple[str, ...],
) -> bool:
    if behavior == "domain":
        return canonical_domain_rules(source_rules) == canonical_domain_rules(dumped_rules)
    if behavior == "ipcidr":
        try:
            return canonical_ipcidr_rules(source_rules) == canonical_ipcidr_rules(
                dumped_rules
            )
        except ValueError:
            return False
    return False


def compile_mrs(
    *,
    mihomo_path: Path,
    behavior: str,
    rules: tuple[str, ...],
    input_path: Path,
    output_path: Path,
    runner=subprocess.run,
) -> int:
    input_path.write_text("\n".join(rules) + "\n", encoding="utf-8")
    try:
        result = runner(
            [
                str(mihomo_path),
                "convert-ruleset",
                behavior,
                "text",
                str(input_path),
                str(output_path),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as error:
        raise SystemExit(f"Mihomo 生成 {output_path.name} 失败：{error}") from error

    if result.returncode != 0 or not output_path.is_file() or output_path.stat().st_size == 0:
        details = (result.stderr or result.stdout).strip()
        raise SystemExit(
            f"Mihomo 生成 {output_path.name} 失败：{details or 'no output'}"
        )

    # Mihomo can read MRS as an input format and dump its canonical text keys.
    # Round-tripping catches behavior/format mixups and malformed artifacts
    # before their URLs enter the app manifest.
    dump_path = input_path.with_suffix(input_path.suffix + ".dump")
    try:
        dump_result = runner(
            [
                str(mihomo_path),
                "convert-ruleset",
                behavior,
                "mrs",
                str(output_path),
                str(dump_path),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as error:
        raise SystemExit(f"Mihomo 验证 {output_path.name} 失败：{error}") from error

    if dump_result.returncode != 0 or not dump_path.is_file():
        details = (dump_result.stderr or dump_result.stdout).strip()
        raise SystemExit(
            f"Mihomo 验证 {output_path.name} 失败：{details or 'no dump'}"
        )
    dumped_rules = tuple(
        line.strip()
        for line in dump_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    )
    if not mrs_rules_equivalent(behavior, rules, dumped_rules):
        raise SystemExit(
            f"Mihomo 验证 {output_path.name} 失败："
            f"输入 {len(rules)} 条，回读 {len(dumped_rules)} 条，语义不一致"
        )
    return len(dumped_rules)


def normalized_srs_source(
    source_rules: tuple[tuple[str, tuple[str, ...]], ...],
) -> dict[str, object]:
    return {
        "version": SING_BOX_SOURCE_FORMAT_VERSION,
        "rules": [
            {
                field: list(values)
                for field, values in source_rules
            }
        ],
    }


def canonical_srs_source(payload: object) -> tuple[int, tuple[tuple[str, frozenset[str]], ...]] | None:
    if not isinstance(payload, dict) or payload.get("version") != SING_BOX_SOURCE_FORMAT_VERSION:
        return None
    rules = payload.get("rules")
    if not isinstance(rules, list):
        return None

    supported_fields = ("domain", "domain_suffix", "domain_keyword", "ip_cidr")
    collected: dict[str, set[str]] = {field: set() for field in supported_fields}
    for rule in rules:
        if not isinstance(rule, dict) or any(field not in supported_fields for field in rule):
            return None
        for field, raw_values in rule.items():
            values = raw_values if isinstance(raw_values, list) else [raw_values]
            if not values or not all(isinstance(value, str) and value for value in values):
                return None
            if field == "ip_cidr":
                try:
                    collected[field].update(
                        str(ipaddress.ip_network(value, strict=False)) for value in values
                    )
                except ValueError:
                    return None
            else:
                collected[field].update(value.lower() for value in values)

    try:
        collected["ip_cidr"] = set(
            canonical_ipcidr_rules(tuple(collected["ip_cidr"]))
        )
    except ValueError:
        return None
    minimal_suffixes = {
        suffix
        for suffix in collected["domain_suffix"]
        if not any(
            suffix != other and suffix.endswith(f".{other}")
            for other in collected["domain_suffix"]
        )
    }
    collected["domain_suffix"] = minimal_suffixes
    collected["domain"] = {
        domain
        for domain in collected["domain"]
        if not any(
            domain == suffix or domain.endswith(f".{suffix}")
            for suffix in minimal_suffixes
        )
    }

    return (
        SING_BOX_SOURCE_FORMAT_VERSION,
        tuple(
            (field, frozenset(collected[field]))
            for field in supported_fields
            if collected[field]
        ),
    )


def compile_srs(
    *,
    sing_box_path: Path,
    source_rules: tuple[tuple[str, tuple[str, ...]], ...],
    input_path: Path,
    output_path: Path,
    runner=subprocess.run,
) -> None:
    source = normalized_srs_source(source_rules)
    input_path.write_text(
        json.dumps(source, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    try:
        result = runner(
            [
                str(sing_box_path),
                "rule-set",
                "compile",
                "--output",
                str(output_path),
                str(input_path),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as error:
        raise SystemExit(f"sing-box 生成 {output_path.name} 失败：{error}") from error
    if result.returncode != 0 or not output_path.is_file() or output_path.stat().st_size == 0:
        details = (result.stderr or result.stdout).strip()
        raise SystemExit(
            f"sing-box 生成 {output_path.name} 失败：{details or 'no output'}"
        )

    dump_path = input_path.with_suffix(input_path.suffix + ".dump.json")
    try:
        dump_result = runner(
            [
                str(sing_box_path),
                "rule-set",
                "decompile",
                "--output",
                str(dump_path),
                str(output_path),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as error:
        raise SystemExit(f"sing-box 验证 {output_path.name} 失败：{error}") from error
    if dump_result.returncode != 0 or not dump_path.is_file():
        details = (dump_result.stderr or dump_result.stdout).strip()
        raise SystemExit(
            f"sing-box 验证 {output_path.name} 失败：{details or 'no dump'}"
        )
    try:
        dumped_source = json.loads(dump_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"sing-box 验证 {output_path.name} 失败：反编译结果无效") from error
    if canonical_srs_source(source) != canonical_srs_source(dumped_source):
        raise SystemExit(
            f"sing-box 验证 {output_path.name} 失败：编译前后语义不一致"
        )


def srs_artifact_name(local_ruleset_name: str) -> str:
    return f"{local_ruleset_name.removesuffix('.list')}_singbox.srs"


def srs_artifact_metadata(
    *,
    revision: str,
    artifact_path: Path,
    classified: SRSRuleInputs,
    source_sha256: str,
    compiler_version: str,
    artifact_commit: str | None = None,
) -> dict[str, object]:
    return {
        "url": f"{artifact_public_base(artifact_commit)}/{revision}/{artifact_path.name}",
        "sha256": hashlib.sha256(artifact_path.read_bytes()).hexdigest(),
        "sourceSha256": source_sha256,
        "inputRuleCount": classified.input_rule_count,
        "residualRuleCount": classified.residual_rule_count,
        "coveredRuleTypes": list(classified.covered_rule_types),
        "sourceFormatVersion": SING_BOX_SOURCE_FORMAT_VERSION,
        "compilerVersion": compiler_version,
    }


def mrs_artifact_name(local_ruleset_name: str, behavior: str) -> str:
    stem = local_ruleset_name.removesuffix(".list")
    return f"{stem}_{behavior}.mrs"


def mrs_artifact_metadata(
    *,
    revision: str,
    artifact_path: Path,
    rule_count: int,
    input_rule_count: int,
    source_sha256: str,
    compiler_version: str,
    artifact_commit: str | None = None,
) -> dict[str, object]:
    artifact_name = artifact_path.name
    return {
        "url": f"{artifact_public_base(artifact_commit)}/{revision}/{artifact_name}",
        "sha256": hashlib.sha256(artifact_path.read_bytes()).hexdigest(),
        "ruleCount": rule_count,
        "inputRuleCount": input_rule_count,
        "sourceSha256": source_sha256,
        "compilerVersion": compiler_version,
    }


def artifact_notice_text(
    revision: str,
    mihomo_version: str,
    sing_box_version: str,
) -> str:
    return f"""Tower-generated ACL4SSR binary rule sets
============================================

Source:      ACL4SSR/ACL4SSR
Source URL:  https://github.com/ACL4SSR/ACL4SSR
Revision:    {revision}
Compilers:   Mihomo {mihomo_version}
             sing-box {sing_box_version} (source format v{SING_BOX_SOURCE_FORMAT_VERSION})
License:     CC BY-SA 4.0
             https://creativecommons.org/licenses/by-sa/4.0/

These MRS files are derived from the pinned ACL4SSR .list snapshots bundled
with Tower. DOMAIN values are emitted as exact domains, DOMAIN-SUFFIX values as
Mihomo +. suffix expressions, and IP-CIDR, IP-CIDR6 and IP6-CIDR values as
canonical CIDRs only when every source CIDR declares no-resolve. All other rule
types, including DOMAIN-WILDCARD, remain outside the binary artifacts and are
emitted inline by Tower. IP artifacts are marked ``noResolve: true`` in the
manifest, and are omitted if a CIDR lacks no-resolve or has another modifier.

Each SRS combines the source list's losslessly convertible DOMAIN,
DOMAIN-SUFFIX, DOMAIN-KEYWORD, IP-CIDR, IP-CIDR6 and IP6-CIDR lines in one
sing-box source-format v2 rule set. CIDRs may have no modifier or exactly one
no-resolve modifier; any other modifier leaves the complete IP family inline.
Malformed source types also remain inline instead of being partially removed.
The temporary source JSON and decompiled JSON are used only for semantic
round-trip verification and are not published.

The artifacts are hosted for compatible Clash/Stash and sing-box clients but
are not bundled inside the Tower app. Source and artifact SHA-256 digests and
converted/residual rule counts are recorded in
Tower/Resources/ACL4SSR/ACL4SSR_manifest.json.

These derived MRS and SRS rule sets remain under CC BY-SA 4.0 and are not
covered by the MIT license that applies to Tower's source code.
"""


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


def notice_text(revision: str) -> str:
    return f"""ACL4SSR rules
=============

Source:      ACL4SSR/ACL4SSR
Source URL:  https://github.com/ACL4SSR/ACL4SSR
Revision:    {revision}
License:     CC BY-SA 4.0
             https://creativecommons.org/licenses/by-sa/4.0/

Bundled here: the ACL4SSR_Online, ACL4SSR_Online_Mini and ACL4SSR_Online_Full
remote configs, plus every .list rule file they reference.

ACL4SSR_manifest.json also records Tower-generated MRS and SRS derivatives for
the losslessly convertible rules. The binaries live under the repository's
Rulesets/ directory for compatible Clash/Stash and sing-box clients and are not
bundled inside the Tower app. Rules without a binary representation stay inline.

Modifications: none to the rule contents. Every file carries an "ACL4SSR_"
prefix because Xcode flattens resources into the bundle root; this keeps their
origin explicit and avoids future filename collisions. The configs' "master"
URLs were rewritten to the pinned revision above so the snapshot is reproducible.

Sources, generated MRS/SRS URLs, rule counts and SHA-256 digests:
ACL4SSR_manifest.json
Regenerate with: python3 Scripts/update_acl4ssr_rules.py --latest \\
  --mihomo <pinned Mihomo executable> --mihomo-version {MIHOMO_VERSION} \\
  --sing-box <pinned sing-box executable> --sing-box-version {SING_BOX_VERSION}

These rule files remain under CC BY-SA 4.0 and are not covered by the MIT
license that applies to this project's source code. See THIRD-PARTY-NOTICES.md
in the repository root.
"""


def _vacant_temporary_sibling(destination: Path, purpose: str) -> Path:
    """Reserve a unique, currently absent path beside ``destination``."""
    candidate = Path(
        tempfile.mkdtemp(
            prefix=f".{destination.name}.{purpose}-",
            dir=destination.parent,
        )
    )
    candidate.rmdir()
    return candidate


def publish_directory_replacements(
    replacements: tuple[tuple[Path, Path], ...],
    *,
    copytree=shutil.copytree,
    replacer=os.replace,
) -> None:
    """Publish directory replacements without deleting the previous snapshot.

    Every source is first copied into a fully populated staging directory beside
    its destination. Existing destinations are then renamed to same-parent
    backups before the staged directories are atomically renamed into place.
    Backups remain available until *all* replacements succeed, so failure while
    publishing the app bundle also restores the already-published rule artifacts.
    """
    prepared: list[tuple[Path, Path]] = []
    backups: dict[Path, Path] = {}
    installed: set[Path] = set()
    seen_destinations: set[Path] = set()

    try:
        # Complete every potentially cross-filesystem copy before changing any
        # live directory. The subsequent swaps are same-parent renames.
        for raw_source, raw_destination in replacements:
            source = Path(raw_source)
            destination = Path(raw_destination)
            if not source.is_dir():
                raise RuntimeError(f"待发布目录不存在：{source}")
            if destination in seen_destinations:
                raise RuntimeError(f"发布目标重复：{destination}")
            seen_destinations.add(destination)
            destination.parent.mkdir(parents=True, exist_ok=True)
            if destination.exists() and (
                not destination.is_dir() or destination.is_symlink()
            ):
                raise RuntimeError(f"发布目标不是普通目录：{destination}")

            sibling_staging = Path(
                tempfile.mkdtemp(
                    prefix=f".{destination.name}.staging-",
                    dir=destination.parent,
                )
            )
            try:
                copytree(source, sibling_staging, dirs_exist_ok=True)
            except BaseException:
                shutil.rmtree(sibling_staging, ignore_errors=True)
                raise
            prepared.append((sibling_staging, destination))

        for sibling_staging, destination in prepared:
            if destination.exists():
                backup = _vacant_temporary_sibling(destination, "backup")
                replacer(destination, backup)
                backups[destination] = backup
            replacer(sibling_staging, destination)
            installed.add(destination)
    except BaseException as publication_error:
        rollback_errors: list[str] = []
        for _, destination in reversed(prepared):
            backup = backups.get(destination)
            if destination in installed and destination.exists():
                discarded = _vacant_temporary_sibling(destination, "rollback")
                try:
                    replacer(destination, discarded)
                except OSError as error:
                    rollback_errors.append(f"{destination}: {error}")
                    continue

                if backup is not None and backup.exists():
                    try:
                        replacer(backup, destination)
                    except OSError as error:
                        rollback_errors.append(f"{destination}: {error}")
                        # Keep a usable published directory if restoring the
                        # backup itself fails. The original remains preserved
                        # at ``backup`` for manual recovery.
                        try:
                            replacer(discarded, destination)
                        except OSError as restore_error:
                            rollback_errors.append(
                                f"{destination} 新目录恢复失败: {restore_error}"
                            )
                        continue
                    backups.pop(destination, None)
                shutil.rmtree(discarded, ignore_errors=True)
            elif backup is not None and backup.exists():
                try:
                    replacer(backup, destination)
                except OSError as error:
                    rollback_errors.append(f"{destination}: {error}")
                else:
                    backups.pop(destination, None)

        if rollback_errors:
            details = "; ".join(rollback_errors)
            raise RuntimeError(f"发布失败且回滚不完整：{details}") from publication_error
        raise
    else:
        # Only discard old snapshots once the whole two-directory publication
        # has completed. Cleanup failure leaves a recoverable hidden backup but
        # does not invalidate the successfully published snapshot.
        for backup in backups.values():
            shutil.rmtree(backup, ignore_errors=True)
    finally:
        for sibling_staging, _ in prepared:
            shutil.rmtree(sibling_staging, ignore_errors=True)


def build(
    revision: str,
    destination: Path = DESTINATION,
    mrs_destination: Path = MRS_DESTINATION,
    mihomo_path: Path | None = None,
    mihomo_version: str = MIHOMO_VERSION,
    sing_box_path: Path | None = None,
    sing_box_version: str = SING_BOX_VERSION,
    artifact_commit: str | None = None,
    fetcher=fetch,
    configs=CONFIGS,
) -> None:
    # This value becomes a directory component that is later removed and
    # replaced. Validate it before compiler checks, downloads, or file writes
    # so branch names and path traversal can never widen the deletion target.
    revision = validated_revision(revision)
    if artifact_commit is not None:
        artifact_commit = validated_revision(artifact_commit)
    if mihomo_path is None:
        raise SystemExit("生成 ACL4SSR 快照必须显式指定 --mihomo")
    if sing_box_path is None:
        raise SystemExit("生成 ACL4SSR 快照必须显式指定 --sing-box")
    mihomo_path = Path(mihomo_path).resolve()
    sing_box_path = Path(sing_box_path).resolve()
    mrs_compiler_version = verify_mihomo(mihomo_path, mihomo_version)
    srs_compiler_version = verify_sing_box(sing_box_path, sing_box_version)

    work_root = Path(tempfile.mkdtemp(prefix="tower-acl4ssr-"))
    staging = work_root / "bundle"
    mrs_staging = work_root / "mrs"
    compiler_inputs = work_root / "inputs"
    staging.mkdir()
    mrs_staging.mkdir()
    compiler_inputs.mkdir()
    manifest: dict[str, object] = {"revision": revision, "configs": {}, "rulesets": {}}
    if artifact_commit is not None:
        manifest["artifactCommit"] = artifact_commit
    mrs_artifact_count = 0
    srs_artifact_count = 0

    try:
        for scheme_id, (file_name, display_name, summary) in configs.items():
            url = config_url(file_name, revision)
            print(f"config  {file_name}")
            payload = fetcher(url)
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
                    body = fetcher(ruleset_url).decode("utf-8-sig")
                except (HTTPError, URLError) as error:
                    raise SystemExit(f"下载失败 {ruleset_url}: {error}") from error
                (staging / name).write_text(body, encoding="utf-8")
                source_sha256 = hashlib.sha256(body.encode("utf-8")).hexdigest()
                ruleset_metadata: dict[str, object] = {
                    "source": ruleset_url,
                    "ruleCount": count_rules(body),
                    "sha256": source_sha256,
                }

                if is_pinned_acl4ssr_ruleset(ruleset_url, revision):
                    classified = classify_mrs_rules(body)
                    generated_mrs: dict[str, object] = {}
                    for behavior, rules, complete in (
                        ("domain", classified.domain, classified.domain_complete),
                        ("ipcidr", classified.ipcidr, classified.ipcidr_complete),
                    ):
                        if not rules or not complete:
                            continue
                        artifact_name = mrs_artifact_name(name, behavior)
                        artifact_path = mrs_staging / artifact_name
                        compiled_rule_count = compile_mrs(
                            mihomo_path=mihomo_path,
                            behavior=behavior,
                            rules=rules,
                            input_path=compiler_inputs / f"{artifact_name}.txt",
                            output_path=artifact_path,
                        )
                        behavior_metadata = mrs_artifact_metadata(
                            revision=revision,
                            artifact_path=artifact_path,
                            rule_count=compiled_rule_count,
                            input_rule_count=len(rules),
                            source_sha256=source_sha256,
                            compiler_version=mrs_compiler_version,
                            artifact_commit=artifact_commit,
                        )
                        if behavior == "ipcidr":
                            # The compiler only reaches this branch when every
                            # source CIDR had exactly one no-resolve modifier.
                            # Consumers must require this capability marker
                            # before emitting RULE-SET,...,no-resolve.
                            behavior_metadata["noResolve"] = True
                        generated_mrs[behavior] = behavior_metadata
                        mrs_artifact_count += 1

                    if generated_mrs:
                        ruleset_metadata["mrs"] = generated_mrs
                    inline_rule_count = classified.residual_rule_count
                    if "domain" not in generated_mrs:
                        inline_rule_count += classified.domain_source_rule_count
                    if "ipcidr" not in generated_mrs:
                        inline_rule_count += classified.ipcidr_source_rule_count
                    if generated_mrs:
                        ruleset_metadata["mrsResidualRuleCount"] = inline_rule_count

                    classified_srs = classify_srs_rules(body)
                    if classified_srs.source_rules and classified_srs.covered_rule_types:
                        artifact_name = srs_artifact_name(name)
                        artifact_path = mrs_staging / artifact_name
                        compile_srs(
                            sing_box_path=sing_box_path,
                            source_rules=classified_srs.source_rules,
                            input_path=compiler_inputs / f"{artifact_name}.json",
                            output_path=artifact_path,
                        )
                        ruleset_metadata["srs"] = srs_artifact_metadata(
                            revision=revision,
                            artifact_path=artifact_path,
                            classified=classified_srs,
                            source_sha256=source_sha256,
                            compiler_version=srs_compiler_version,
                            artifact_commit=artifact_commit,
                        )
                        srs_artifact_count += 1
                manifest["rulesets"][name] = ruleset_metadata

        (mrs_staging / "NOTICE.txt").write_text(
            artifact_notice_text(
                revision,
                mrs_compiler_version,
                srs_compiler_version,
            ),
            encoding="utf-8",
        )

        (staging / f"{RESOURCE_PREFIX}NOTICE.txt").write_text(
            notice_text(revision),
            encoding="utf-8",
        )

        # Prefixed for the same reason as the rule lists: the flat bundle should
        # retain an origin-specific manifest name.
        (staging / f"{RESOURCE_PREFIX}manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        # Prepare both replacements beside their final destinations, retain
        # same-parent backups, and roll both back if either swap fails. Artifacts
        # are still installed first so the new manifest is never visible before
        # every file it references.
        revision_destination = mrs_destination / revision
        publish_directory_replacements(
            (
                (mrs_staging, revision_destination),
                (staging, destination),
            )
        )
    finally:
        shutil.rmtree(work_root, ignore_errors=True)

    print(
        f"\n完成：{len(manifest['configs'])} 份配置，"
        f"{len(manifest['rulesets'])} 个规则文件 -> {destination}\n"
        f"      {mrs_artifact_count} 个 MRS、{srs_artifact_count} 个 SRS 文件 -> "
        f"{mrs_destination / revision}"
    )


def main(
    argv: list[str] | None = None,
    destination: Path = DESTINATION,
    fetcher=fetch,
    builder=build,
) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--check-latest",
        action="store_true",
        help="只检查随包快照是否对应上游最新提交，不修改文件。",
    )
    mode.add_argument(
        "--latest",
        action="store_true",
        help="解析上游最新提交并生成可复现的随包快照。",
    )
    mode.add_argument(
        "--verify-published",
        action="store_true",
        help="从不可变 Raw commit URL 回读并校验全部 MRS/SRS。",
    )
    mode.add_argument(
        "--revision",
        default=ACL4SSR_REVISION,
        help="ACL4SSR/ACL4SSR 的提交号，默认使用脚本里固定的版本。",
    )
    parser.add_argument(
        "--mihomo",
        type=Path,
        help="用于生成 MRS 的已固定 Mihomo 可执行文件路径。",
    )
    parser.add_argument(
        "--mihomo-version",
        default=MIHOMO_VERSION,
        help=f"必须与编译器 -v 输出匹配的版本（默认 {MIHOMO_VERSION}）。",
    )
    parser.add_argument(
        "--sing-box",
        type=Path,
        help="用于生成 SRS 的已固定 sing-box 可执行文件路径。",
    )
    parser.add_argument(
        "--sing-box-version",
        default=SING_BOX_VERSION,
        help=f"必须与编译器 version 输出匹配的版本（默认 {SING_BOX_VERSION}）。",
    )
    parser.add_argument(
        "--artifact-commit",
        help=(
            "Tower 仓库中已单独推送二进制产物的 40 位 commit。"
            "省略时只生成 main 预备清单，不得用于发布。"
        ),
    )
    arguments = parser.parse_args(argv)
    if arguments.check_latest:
        check_latest_snapshot(destination=destination, fetcher=fetcher)
        return
    if arguments.verify_published:
        verify_published_artifacts(destination=destination, fetcher=fetcher)
        return
    if arguments.mihomo is None:
        parser.error("生成快照时必须提供 --mihomo")
    if arguments.sing_box is None:
        parser.error("生成快照时必须提供 --sing-box")
    revision = validated_revision(
        latest_revision(fetcher=fetcher) if arguments.latest else arguments.revision
    )
    artifact_commit = (
        validated_revision(arguments.artifact_commit)
        if arguments.artifact_commit is not None
        else None
    )
    builder(
        revision,
        destination=destination,
        fetcher=fetcher,
        mihomo_path=arguments.mihomo,
        mihomo_version=arguments.mihomo_version,
        sing_box_path=arguments.sing_box,
        sing_box_version=arguments.sing_box_version,
        artifact_commit=artifact_commit,
    )


if __name__ == "__main__":
    main()
