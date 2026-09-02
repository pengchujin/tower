#!/usr/bin/env python3

import hashlib
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


def make_fake_mihomo(directory: Path, version: str = updater.MIHOMO_VERSION) -> Path:
    executable = directory / "mihomo"
    executable.write_text(
        f'''#!/usr/bin/env python3
import sys
from pathlib import Path

arguments = sys.argv[1:]
if arguments == ["-v"]:
    print("Mihomo Meta {version} test compiler")
    raise SystemExit(0)
if len(arguments) == 5 and arguments[0] == "convert-ruleset":
    _, behavior, input_format, input_name, output_name = arguments
    payload = Path(input_name).read_bytes()
    prefix = b"FAKE-MRS\\0" + behavior.encode() + b"\\0"
    if input_format == "text":
        Path(output_name).write_bytes(prefix + payload)
    elif input_format == "mrs" and payload.startswith(prefix):
        Path(output_name).write_bytes(payload[len(prefix):])
    else:
        raise SystemExit(2)
    raise SystemExit(0)
raise SystemExit(3)
''',
        encoding="utf-8",
    )
    executable.chmod(0o755)
    return executable


def make_fake_sing_box(
    directory: Path,
    version: str = updater.SING_BOX_VERSION,
) -> Path:
    executable = directory / "sing-box"
    executable.write_text(
        f'''#!/usr/bin/env python3
import sys
from pathlib import Path

arguments = sys.argv[1:]
if arguments == ["version"]:
    print("sing-box version {version}")
    raise SystemExit(0)
if len(arguments) == 5 and arguments[:3] == ["rule-set", "compile", "--output"]:
    output_name, input_name = arguments[3], arguments[4]
    Path(output_name).write_bytes(b"FAKE-SRS\\0" + Path(input_name).read_bytes())
    raise SystemExit(0)
if len(arguments) == 5 and arguments[:3] == ["rule-set", "decompile", "--output"]:
    output_name, input_name = arguments[3], arguments[4]
    payload = Path(input_name).read_bytes()
    if not payload.startswith(b"FAKE-SRS\\0"):
        raise SystemExit(2)
    Path(output_name).write_bytes(payload[len(b"FAKE-SRS\\0"):])
    raise SystemExit(0)
raise SystemExit(3)
''',
        encoding="utf-8",
    )
    executable.chmod(0o755)
    return executable


class UpdateACL4SSRRulesTests(unittest.TestCase):
    def test_latest_revision_resolves_the_upstream_head_sha(self) -> None:
        expected = "1234567890abcdef1234567890abcdef12345678"

        def fetcher(url: str) -> bytes:
            self.assertEqual(url, updater.LATEST_REVISION_URL)
            return json.dumps({"sha": expected}).encode()

        self.assertEqual(updater.latest_revision(fetcher=fetcher), expected)

    def test_invalid_explicit_revision_never_reaches_the_builder(self) -> None:
        calls: list[str] = []

        with self.assertRaisesRegex(SystemExit, "40 位十六进制"):
            updater.main(
                [
                    "--revision",
                    "../outside",
                    "--mihomo",
                    "/tmp/pinned-mihomo",
                    "--sing-box",
                    "/tmp/pinned-sing-box",
                ],
                builder=lambda revision, **_: calls.append(revision),
            )

        self.assertEqual(calls, [])

    def test_build_rejects_path_revision_before_touching_destinations(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            destination = root / "bundle"
            rulesets = root / "rulesets"
            sentinel = root / "outside" / "sentinel.txt"
            sentinel.parent.mkdir()
            sentinel.write_text("keep", encoding="utf-8")

            with self.assertRaisesRegex(SystemExit, "40 位十六进制"):
                updater.build(
                    "../outside",
                    destination=destination,
                    mrs_destination=rulesets,
                )

            self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")
            self.assertFalse(destination.exists())
            self.assertFalse(rulesets.exists())

    def test_directory_publication_rolls_back_both_same_parent_swaps(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            generated_artifacts = root / "generated-artifacts"
            generated_bundle = root / "generated-bundle"
            generated_artifacts.mkdir()
            generated_bundle.mkdir()
            (generated_artifacts / "artifact.srs").write_text(
                "new artifact",
                encoding="utf-8",
            )
            (generated_bundle / "manifest.json").write_text(
                "new manifest",
                encoding="utf-8",
            )

            artifact_destination = root / "Rulesets" / "revision"
            bundle_destination = root / "Resources" / "ACL4SSR"
            artifact_destination.mkdir(parents=True)
            bundle_destination.mkdir(parents=True)
            (artifact_destination / "artifact.srs").write_text(
                "old artifact",
                encoding="utf-8",
            )
            (bundle_destination / "manifest.json").write_text(
                "old manifest",
                encoding="utf-8",
            )

            real_replace = updater.os.replace
            failure_injected = False

            def failing_second_install(source: Path, destination: Path) -> None:
                nonlocal failure_injected
                source_path = Path(source)
                destination_path = Path(destination)
                self.assertEqual(source_path.parent, destination_path.parent)
                if (
                    not failure_injected
                    and source_path.name.startswith(
                        f".{bundle_destination.name}.staging-"
                    )
                ):
                    failure_injected = True
                    raise OSError("injected second-directory failure")
                real_replace(source_path, destination_path)

            with self.assertRaisesRegex(OSError, "second-directory failure"):
                updater.publish_directory_replacements(
                    (
                        (generated_artifacts, artifact_destination),
                        (generated_bundle, bundle_destination),
                    ),
                    replacer=failing_second_install,
                )

            self.assertTrue(failure_injected)
            self.assertEqual(
                (artifact_destination / "artifact.srs").read_text(encoding="utf-8"),
                "old artifact",
            )
            self.assertEqual(
                (bundle_destination / "manifest.json").read_text(encoding="utf-8"),
                "old manifest",
            )
            for parent in (artifact_destination.parent, bundle_destination.parent):
                self.assertEqual(
                    [path.name for path in parent.iterdir() if path.name.startswith(".")],
                    [],
                )

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

    def test_check_latest_cli_does_not_require_a_compiler(self) -> None:
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

    def test_verify_published_checks_every_immutable_artifact(self) -> None:
        revision = "abcdef1234567890abcdef1234567890abcdef12"
        artifact_commit = "1234567890abcdef1234567890abcdef12345678"
        base = updater.artifact_public_base(artifact_commit)
        domain_name = "ACL4SSR_Test_domain.mrs"
        srs_name = "ACL4SSR_Test_singbox.srs"
        payloads = {
            f"{base}/{revision}/{domain_name}": b"domain-mrs",
            f"{base}/{revision}/{srs_name}": b"sing-box-srs",
        }
        manifest = {
            "revision": revision,
            "artifactCommit": artifact_commit,
            "rulesets": {
                "ACL4SSR_Test.list": {
                    "mrs": {
                        "domain": {
                            "url": f"{base}/{revision}/{domain_name}",
                            "sha256": hashlib.sha256(b"domain-mrs").hexdigest(),
                        }
                    },
                    "srs": {
                        "url": f"{base}/{revision}/{srs_name}",
                        "sha256": hashlib.sha256(b"sing-box-srs").hexdigest(),
                    },
                }
            },
        }

        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            (destination / "ACL4SSR_manifest.json").write_text(
                json.dumps(manifest),
                encoding="utf-8",
            )
            requested: list[str] = []

            def fetcher(url: str) -> bytes:
                requested.append(url)
                return payloads[url]

            updater.main(
                ["--verify-published"],
                destination=destination,
                fetcher=fetcher,
            )

        self.assertEqual(set(requested), set(payloads))

    def test_verify_published_rejects_a_mutable_main_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            (destination / "ACL4SSR_manifest.json").write_text(
                json.dumps({"revision": updater.ACL4SSR_REVISION, "rulesets": {}}),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(SystemExit, "artifactCommit"):
                updater.main(
                    ["--verify-published"],
                    destination=destination,
                    fetcher=lambda _: b"",
                )

    def test_latest_cli_passes_the_pinned_compiler_to_the_builder(self) -> None:
        revision = "abcdef1234567890abcdef1234567890abcdef12"
        artifact_commit = "1234567890abcdef1234567890abcdef12345678"
        calls: list[tuple[str, dict[str, object]]] = []
        compiler = Path("/tmp/pinned-mihomo")
        sing_box = Path("/tmp/pinned-sing-box")

        def builder(built_revision: str, **kwargs: object) -> None:
            calls.append((built_revision, kwargs))

        updater.main(
            [
                "--latest",
                "--mihomo",
                str(compiler),
                "--mihomo-version",
                updater.MIHOMO_VERSION,
                "--sing-box",
                str(sing_box),
                "--sing-box-version",
                updater.SING_BOX_VERSION,
                "--artifact-commit",
                artifact_commit,
            ],
            fetcher=lambda _: json.dumps({"sha": revision}).encode(),
            builder=builder,
        )

        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0], revision)
        self.assertEqual(calls[0][1]["mihomo_path"], compiler)
        self.assertEqual(calls[0][1]["mihomo_version"], updater.MIHOMO_VERSION)
        self.assertEqual(calls[0][1]["sing_box_path"], sing_box)
        self.assertEqual(calls[0][1]["sing_box_version"], updater.SING_BOX_VERSION)
        self.assertEqual(calls[0][1]["artifact_commit"], artifact_commit)

    def test_invalid_artifact_commit_never_reaches_the_builder(self) -> None:
        calls: list[str] = []
        with self.assertRaisesRegex(SystemExit, "40 位十六进制"):
            updater.main(
                [
                    "--revision",
                    updater.ACL4SSR_REVISION,
                    "--artifact-commit",
                    "main",
                    "--mihomo",
                    "/tmp/pinned-mihomo",
                    "--sing-box",
                    "/tmp/pinned-sing-box",
                ],
                builder=lambda revision, **_: calls.append(revision),
            )
        self.assertEqual(calls, [])

    def test_checked_in_snapshot_manifest_and_binary_artifacts_are_complete(self) -> None:
        repository = SCRIPT_PATH.parents[1]
        bundle_directory = repository / "Tower" / "Resources" / "ACL4SSR"
        manifest_path = bundle_directory / "ACL4SSR_manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        revision = manifest["revision"]
        self.assertEqual(revision, updater.ACL4SSR_REVISION)
        artifact_base = updater.artifact_public_base(manifest.get("artifactCommit"))

        artifact_directory = repository / "Rulesets" / "ACL4SSR" / revision
        expected_bundle_files = {
            "ACL4SSR_NOTICE.txt",
            "ACL4SSR_manifest.json",
        }
        expected_artifact_files = {"NOTICE.txt"}

        for scheme_id, metadata in manifest["configs"].items():
            with self.subTest(config=scheme_id):
                file_name = metadata["file"]
                config_path = bundle_directory / file_name
                expected_bundle_files.add(file_name)
                self.assertEqual(
                    hashlib.sha256(config_path.read_bytes()).hexdigest(),
                    metadata["sha256"],
                )
                self.assertEqual(
                    metadata["source"],
                    updater.config_url(file_name, revision),
                )

        for ruleset_name, metadata in manifest["rulesets"].items():
            with self.subTest(ruleset=ruleset_name):
                source_path = bundle_directory / ruleset_name
                expected_bundle_files.add(ruleset_name)
                source_bytes = source_path.read_bytes()
                source_text = source_bytes.decode("utf-8")
                source_sha256 = hashlib.sha256(source_bytes).hexdigest()
                self.assertEqual(metadata["sha256"], source_sha256)
                self.assertEqual(metadata["ruleCount"], updater.count_rules(source_text))

                is_pinned_source = updater.is_pinned_acl4ssr_ruleset(
                    metadata["source"],
                    revision,
                )
                classified_mrs = updater.classify_mrs_rules(source_text)
                expected_mrs_inputs: dict[str, tuple[str, ...]] = {}
                if is_pinned_source:
                    if classified_mrs.domain and classified_mrs.domain_complete:
                        expected_mrs_inputs["domain"] = classified_mrs.domain
                    if classified_mrs.ipcidr and classified_mrs.ipcidr_complete:
                        expected_mrs_inputs["ipcidr"] = classified_mrs.ipcidr

                mrs_metadata = metadata.get("mrs", {})
                self.assertEqual(set(mrs_metadata), set(expected_mrs_inputs))
                if expected_mrs_inputs:
                    expected_residual_count = classified_mrs.residual_rule_count
                    if "domain" not in expected_mrs_inputs:
                        expected_residual_count += (
                            classified_mrs.domain_source_rule_count
                        )
                    if "ipcidr" not in expected_mrs_inputs:
                        expected_residual_count += (
                            classified_mrs.ipcidr_source_rule_count
                        )
                    self.assertEqual(
                        metadata["mrsResidualRuleCount"],
                        expected_residual_count,
                    )
                else:
                    self.assertNotIn("mrsResidualRuleCount", metadata)

                for behavior, input_rules in expected_mrs_inputs.items():
                    artifact_metadata = mrs_metadata[behavior]
                    artifact_name = updater.mrs_artifact_name(
                        ruleset_name,
                        behavior,
                    )
                    artifact_path = artifact_directory / artifact_name
                    expected_artifact_files.add(artifact_name)
                    self.assertEqual(
                        artifact_metadata["url"],
                        f"{artifact_base}/{revision}/{artifact_name}",
                    )
                    self.assertEqual(
                        artifact_metadata["sourceSha256"],
                        source_sha256,
                    )
                    self.assertEqual(
                        artifact_metadata["compilerVersion"],
                        updater.MIHOMO_VERSION,
                    )
                    self.assertEqual(
                        artifact_metadata["inputRuleCount"],
                        len(input_rules),
                    )
                    self.assertGreater(artifact_metadata["ruleCount"], 0)
                    self.assertLessEqual(
                        artifact_metadata["ruleCount"],
                        artifact_metadata["inputRuleCount"],
                    )
                    if behavior == "ipcidr":
                        self.assertIs(artifact_metadata["noResolve"], True)
                    else:
                        self.assertNotIn("noResolve", artifact_metadata)
                    self.assertEqual(
                        hashlib.sha256(artifact_path.read_bytes()).hexdigest(),
                        artifact_metadata["sha256"],
                    )

                classified_srs = updater.classify_srs_rules(source_text)
                expects_srs = bool(
                    is_pinned_source
                    and classified_srs.source_rules
                    and classified_srs.covered_rule_types
                )
                self.assertEqual("srs" in metadata, expects_srs)
                if expects_srs:
                    srs_metadata = metadata["srs"]
                    artifact_name = updater.srs_artifact_name(ruleset_name)
                    artifact_path = artifact_directory / artifact_name
                    expected_artifact_files.add(artifact_name)
                    self.assertEqual(
                        srs_metadata["url"],
                        f"{artifact_base}/{revision}/{artifact_name}",
                    )
                    self.assertEqual(srs_metadata["sourceSha256"], source_sha256)
                    self.assertEqual(
                        srs_metadata["compilerVersion"],
                        updater.SING_BOX_VERSION,
                    )
                    self.assertEqual(
                        srs_metadata["sourceFormatVersion"],
                        updater.SING_BOX_SOURCE_FORMAT_VERSION,
                    )
                    self.assertEqual(
                        srs_metadata["inputRuleCount"],
                        classified_srs.input_rule_count,
                    )
                    self.assertEqual(
                        srs_metadata["residualRuleCount"],
                        classified_srs.residual_rule_count,
                    )
                    self.assertEqual(
                        srs_metadata["inputRuleCount"]
                        + srs_metadata["residualRuleCount"],
                        metadata["ruleCount"],
                    )
                    self.assertEqual(
                        srs_metadata["coveredRuleTypes"],
                        list(classified_srs.covered_rule_types),
                    )
                    self.assertEqual(
                        len(srs_metadata["coveredRuleTypes"]),
                        len(set(srs_metadata["coveredRuleTypes"])),
                    )
                    self.assertEqual(
                        hashlib.sha256(artifact_path.read_bytes()).hexdigest(),
                        srs_metadata["sha256"],
                    )

        self.assertEqual(
            {path.name for path in bundle_directory.iterdir()},
            expected_bundle_files,
            "bundled ACL4SSR snapshot contains an orphan or is missing a file",
        )
        self.assertEqual(
            {path.name for path in artifact_directory.iterdir()},
            expected_artifact_files,
            "published Rulesets revision contains an orphan or is missing an artifact",
        )

    def test_classification_converts_only_lossless_domain_and_ip_rules(self) -> None:
        classified = updater.classify_mrs_rules(
            """
            # comment
            DOMAIN,exact.example
            DOMAIN-SUFFIX,suffix.example
            DOMAIN-SUFFIX,ready.example
            DOMAIN-WILDCARD,*.*.wild.example
            IP-CIDR,192.0.2.0/24,no-resolve
            IP-CIDR6,2001:db8::/32,no-resolve
            IP6-CIDR,2001:db8:1::/48
            DOMAIN-KEYWORD,search
            URL-REGEX,^https://example
            IP-CIDR,not-a-cidr
            GEOSITE,CN
            """
        )

        self.assertEqual(
            classified.domain,
            (
                "exact.example",
                "+.suffix.example",
                "+.ready.example",
            ),
        )
        self.assertEqual(
            classified.ipcidr,
            ("192.0.2.0/24", "2001:db8::/32", "2001:db8:1::/48"),
        )
        self.assertEqual(classified.residual_rule_count, 4)
        self.assertEqual(classified.domain_source_rule_count, 3)
        self.assertEqual(classified.ipcidr_source_rule_count, 4)
        self.assertTrue(classified.domain_complete)
        self.assertFalse(classified.ipcidr_complete)
        self.assertTrue(
            updater.mrs_rules_equivalent(
                "ipcidr",
                ("fc00::/7", "fd00::/8"),
                ("fc00::/7",),
            )
        )
        self.assertTrue(
            updater.mrs_rules_equivalent(
                "domain",
                ("+.example.com", "www.example.com"),
                ("+.example.com",),
            )
        )

    def test_classification_fails_closed_for_ambiguous_behavior_inputs(self) -> None:
        classified = updater.classify_mrs_rules(
            """
            DOMAIN,exact.example
            DOMAIN-SUFFIX,.dot-prefixed.example
            DOMAIN-SUFFIX,+.mrs-prefixed.example
            DOMAIN,parameterized.example,no-resolve
            IP-CIDR,192.0.2.0/24,no-resolve
            IP-CIDR,198.51.100.0/24,no-resolve,src
            """
        )

        self.assertEqual(classified.domain, ("exact.example",))
        self.assertNotIn("+.dot-prefixed.example", classified.domain)
        self.assertNotIn("+.mrs-prefixed.example", classified.domain)
        self.assertNotIn("parameterized.example", classified.domain)
        self.assertFalse(classified.domain_complete)
        self.assertEqual(
            classified.ipcidr,
            ("192.0.2.0/24", "198.51.100.0/24"),
        )
        self.assertFalse(classified.ipcidr_complete)

    def test_srs_classification_combines_supported_types_and_keeps_residuals(self) -> None:
        classified = updater.classify_srs_rules(
            """
            DOMAIN,Exact.Example
            DOMAIN-SUFFIX,DiskStation.Me
            DOMAIN-KEYWORD,Search
            IP-CIDR,192.0.2.1/24
            IP-CIDR6,2001:db8::/32,no-resolve
            PROCESS-NAME,Example
            """
        )

        self.assertEqual(
            classified.source_rules,
            (
                ("domain", ("exact.example",)),
                ("domain_suffix", ("diskstation.me",)),
                ("domain_keyword", ("search",)),
                ("ip_cidr", ("192.0.2.0/24", "2001:db8::/32")),
            ),
        )
        self.assertEqual(classified.input_rule_count, 5)
        self.assertEqual(classified.residual_rule_count, 1)
        self.assertEqual(
            classified.covered_rule_types,
            ("DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "IP-CIDR", "IP-CIDR6"),
        )
        self.assertEqual(
            updater.normalized_srs_source(classified.source_rules)["version"],
            updater.SING_BOX_SOURCE_FORMAT_VERSION,
        )
        self.assertEqual(
            updater.canonical_srs_source(
                {
                    "version": 2,
                    "rules": [
                        {"ip_cidr": ["192.0.2.0/25", "192.0.2.128/25"]}
                    ],
                }
            ),
            updater.canonical_srs_source(
                {"version": 2, "rules": [{"ip_cidr": "192.0.2.0/24"}]}
            ),
        )
        self.assertEqual(
            updater.canonical_srs_source(
                {
                    "version": 2,
                    "rules": [
                        {
                            "domain": ["www.example.com", "outside.test"],
                            "domain_suffix": ["sub.example.com", "example.com"],
                        }
                    ],
                }
            ),
            updater.canonical_srs_source(
                {
                    "version": 2,
                    "rules": [
                        {
                            "domain": "outside.test",
                            "domain_suffix": "example.com",
                        }
                    ],
                }
            ),
        )

    def test_srs_classification_fails_closed_per_type_and_for_the_ip_family(self) -> None:
        classified = updater.classify_srs_rules(
            """
            DOMAIN,good.example
            DOMAIN,bad.example,no-resolve
            DOMAIN-SUFFIX,suffix.example
            IP-CIDR,192.0.2.0/24
            IP-CIDR6,2001:db8::/32,no-resolve,src
            """
        )

        self.assertEqual(
            classified.source_rules,
            (("domain_suffix", ("suffix.example",)),),
        )
        self.assertEqual(classified.covered_rule_types, ("DOMAIN-SUFFIX",))
        self.assertEqual(classified.input_rule_count, 1)
        self.assertEqual(classified.residual_rule_count, 4)

    def test_snapshot_builds_tower_hosted_mrs_and_records_verifiable_metadata(self) -> None:
        revision = "abcdef1234567890abcdef1234567890abcdef12"
        artifact_commit = "1234567890abcdef1234567890abcdef12345678"
        artifact_base = updater.artifact_public_base(artifact_commit)
        config_name = "Test.ini"
        config = (
            "ruleset=测试,"
            f"{updater.RAW_BASE}/master/Clash/Ruleset/Test.list\n"
            "ruleset=外部,https://example.com/External.list\n"
        ).encode()
        source_body = (
            "DOMAIN,exact.example\n"
            "DOMAIN-SUFFIX,example.com\n"
            "DOMAIN-WILDCARD,*.wild.example\n"
            "IP-CIDR,192.0.2.0/24,no-resolve\n"
            "DOMAIN-KEYWORD,residual\n"
        )

        def fetcher(url: str) -> bytes:
            if url == updater.config_url(config_name, revision):
                return config
            if url.endswith("/Clash/Ruleset/Test.list"):
                return source_body.encode()
            if url == "https://example.com/External.list":
                return b"DOMAIN,external.example\n"
            raise AssertionError(f"unexpected URL: {url}")

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            compiler = make_fake_mihomo(root)
            sing_box = make_fake_sing_box(root)
            destination = root / "bundle"
            mrs_destination = root / "Rulesets" / "ACL4SSR"
            updater.build(
                revision,
                destination=destination,
                mrs_destination=mrs_destination,
                mihomo_path=compiler,
                sing_box_path=sing_box,
                artifact_commit=artifact_commit,
                fetcher=fetcher,
                configs={"test": (config_name, "测试", "测试规则")},
            )

            manifest_path = destination / "ACL4SSR_manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            self.assertEqual(manifest["artifactCommit"], artifact_commit)
            metadata = manifest["rulesets"]["ACL4SSR_Ruleset_Test.list"]
            source_sha256 = hashlib.sha256(source_body.encode()).hexdigest()
            self.assertEqual(metadata["sha256"], source_sha256)
            self.assertEqual(metadata["mrsResidualRuleCount"], 2)

            revision_directory = mrs_destination / revision
            for behavior, expected_count, expected_input in (
                (
                    "domain",
                    2,
                    b"exact.example\n+.example.com\n",
                ),
                ("ipcidr", 1, b"192.0.2.0/24\n"),
            ):
                artifact_name = f"ACL4SSR_Ruleset_Test_{behavior}.mrs"
                artifact = revision_directory / artifact_name
                expected_artifact = (
                    b"FAKE-MRS\0" + behavior.encode() + b"\0" + expected_input
                )
                self.assertEqual(artifact.read_bytes(), expected_artifact)
                expected_metadata = {
                    "url": f"{artifact_base}/{revision}/{artifact_name}",
                    "sha256": hashlib.sha256(expected_artifact).hexdigest(),
                    "ruleCount": expected_count,
                    "inputRuleCount": expected_count,
                    "sourceSha256": source_sha256,
                    "compilerVersion": updater.MIHOMO_VERSION,
                }
                if behavior == "ipcidr":
                    expected_metadata["noResolve"] = True
                self.assertEqual(metadata["mrs"][behavior], expected_metadata)

            srs_artifact_name = "ACL4SSR_Ruleset_Test_singbox.srs"
            srs_artifact = revision_directory / srs_artifact_name
            self.assertTrue(srs_artifact.read_bytes().startswith(b"FAKE-SRS\0"))
            self.assertEqual(
                metadata["srs"],
                {
                    "url": f"{artifact_base}/{revision}/{srs_artifact_name}",
                    "sha256": hashlib.sha256(srs_artifact.read_bytes()).hexdigest(),
                    "sourceSha256": source_sha256,
                    "inputRuleCount": 4,
                    "residualRuleCount": 1,
                    "coveredRuleTypes": [
                        "DOMAIN",
                        "DOMAIN-SUFFIX",
                        "DOMAIN-KEYWORD",
                        "IP-CIDR",
                    ],
                    "sourceFormatVersion": 2,
                    "compilerVersion": updater.SING_BOX_VERSION,
                },
            )

            external = manifest["rulesets"]["ACL4SSR_https:__example.com_External.list"]
            self.assertNotIn("mrs", external)
            self.assertNotIn("srs", external)
            serialized = manifest_path.read_text(encoding="utf-8")
            self.assertNotIn("/Clash/mrs/", serialized)
            self.assertFalse(list(destination.glob("*.mrs")))
            self.assertFalse(list(revision_directory.glob("*.json")))

            bundle_notice = (destination / "ACL4SSR_NOTICE.txt").read_text(
                encoding="utf-8"
            )
            hosted_notice = (revision_directory / "NOTICE.txt").read_text(
                encoding="utf-8"
            )
            self.assertIn("not\nbundled inside the Tower app", bundle_notice)
            self.assertIn("Compilers:   Mihomo v1.19.30", hosted_notice)
            self.assertIn("sing-box 1.14.0 (source format v2)", hosted_notice)

    def test_incomplete_behavior_is_never_partially_published(self) -> None:
        revision = "abcdef1234567890abcdef1234567890abcdef12"
        config_name = "Test.ini"
        config = (
            "ruleset=测试,"
            f"{updater.RAW_BASE}/master/Clash/Test.list\n"
        ).encode()
        source_body = (
            "DOMAIN,good.example\n"
            "DOMAIN-SUFFIX,\n"
            "IP-CIDR,192.0.2.0/24,no-resolve\n"
            "IP-CIDR,198.51.100.0/24\n"
        )

        def fetcher(url: str) -> bytes:
            if url == updater.config_url(config_name, revision):
                return config
            if url.endswith("/Clash/Test.list"):
                return source_body.encode()
            raise AssertionError(f"unexpected URL: {url}")

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            compiler = make_fake_mihomo(root)
            sing_box = make_fake_sing_box(root)
            destination = root / "bundle"
            mrs_destination = root / "rulesets"
            updater.build(
                revision,
                destination=destination,
                mrs_destination=mrs_destination,
                mihomo_path=compiler,
                sing_box_path=sing_box,
                fetcher=fetcher,
                configs={"test": (config_name, "测试", "测试规则")},
            )

            manifest = json.loads(
                (destination / "ACL4SSR_manifest.json").read_text(encoding="utf-8")
            )
            metadata = manifest["rulesets"]["ACL4SSR_Test.list"]
            self.assertNotIn("mrs", metadata)
            self.assertFalse(list((mrs_destination / revision).glob("*.mrs")))

    def test_snapshot_build_is_byte_deterministic(self) -> None:
        revision = "abcdef1234567890abcdef1234567890abcdef12"
        config_name = "Test.ini"
        config = (
            "ruleset=测试,"
            f"{updater.RAW_BASE}/master/Clash/Test.list\n"
        ).encode()

        def fetcher(url: str) -> bytes:
            if url == updater.config_url(config_name, revision):
                return config
            if url.endswith("/Clash/Test.list"):
                return b"DOMAIN-SUFFIX,example.com\nIP-CIDR,192.0.2.0/24,no-resolve\n"
            raise AssertionError(f"unexpected URL: {url}")

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            compiler = make_fake_mihomo(root)
            sing_box = make_fake_sing_box(root)
            results: list[tuple[bytes, dict[str, bytes]]] = []
            for index in range(2):
                destination = root / f"bundle-{index}"
                mrs_destination = root / f"rulesets-{index}"
                updater.build(
                    revision,
                    destination=destination,
                    mrs_destination=mrs_destination,
                    mihomo_path=compiler,
                    sing_box_path=sing_box,
                    fetcher=fetcher,
                    configs={"test": (config_name, "测试", "测试规则")},
                )
                artifacts = {
                    path.name: path.read_bytes()
                    for path in sorted((mrs_destination / revision).glob("*"))
                    if path.is_file()
                }
                results.append(
                    (
                        (destination / "ACL4SSR_manifest.json").read_bytes(),
                        artifacts,
                    )
                )

            self.assertEqual(results[0], results[1])

    def test_snapshot_rejects_an_unpinned_compiler_version(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            compiler = make_fake_mihomo(root, version="v9.9.9")
            sing_box = make_fake_sing_box(root)
            with self.assertRaisesRegex(SystemExit, "Mihomo 版本不匹配"):
                updater.build(
                    "abcdef1234567890abcdef1234567890abcdef12",
                    destination=root / "bundle",
                    mrs_destination=root / "rulesets",
                    mihomo_path=compiler,
                    sing_box_path=sing_box,
                    configs={},
                )

    def test_snapshot_rejects_an_unpinned_sing_box_version(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            compiler = make_fake_mihomo(root)
            sing_box = make_fake_sing_box(root, version="9.9.9")
            with self.assertRaisesRegex(SystemExit, "sing-box 版本不匹配"):
                updater.build(
                    "abcdef1234567890abcdef1234567890abcdef12",
                    destination=root / "bundle",
                    mrs_destination=root / "rulesets",
                    mihomo_path=compiler,
                    sing_box_path=sing_box,
                    configs={},
                )


if __name__ == "__main__":
    unittest.main()
