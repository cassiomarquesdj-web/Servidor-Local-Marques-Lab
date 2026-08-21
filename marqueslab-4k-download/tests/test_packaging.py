"""Guards on the macOS distribution contract.

These tests fail the build if the packaging pipeline could ever produce an
unsigned, un-notarized or mislabelled artifact.
"""
from __future__ import annotations

import plistlib
import re
import stat
from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml", reason="pyyaml só é necessário para validar os workflows")

import branding

ROOT = Path(__file__).resolve().parents[1]
PACKAGING = ROOT / "packaging"
WORKFLOWS = ROOT.parent / ".github" / "workflows"
RELEASE_WORKFLOW = WORKFLOWS / "marqueslab-4k-download-release.yml"
CI_WORKFLOW = WORKFLOWS / "marqueslab-4k-download-ci.yml"

SCRIPTS = [
    "build_app.sh", "sign_app.sh", "make_dmg.sh", "notarize.sh",
    "verify_release.sh", "release_macos.sh", "check_apple_credentials.sh",
]


def test_branding_is_consistent():
    assert branding.APP_NAME == "Marques Lab 4K Download"
    assert re.fullmatch(r"\d+\.\d+\.\d+", branding.VERSION)
    assert re.fullmatch(r"[A-Za-z0-9.-]+", branding.BUNDLE_ID)
    assert branding.BUNDLE_ID.startswith("com.marqueslab.")


def test_icon_is_committed():
    icon = ROOT / "assets" / "AppIcon.icns"
    assert icon.is_file(), "o ícone do aplicativo precisa estar versionado"
    assert icon.stat().st_size > 10_000
    assert icon.read_bytes()[:4] == b"icns"


def test_spec_declares_bundle_metadata():
    spec = (ROOT / "MarquesLab4KDownload.spec").read_text(encoding="utf-8")
    assert "BUNDLE(" in spec
    assert "bundle_identifier=BUNDLE_ID" in spec
    assert "LSMinimumSystemVersion" in spec
    assert "NSHighResolutionCapable" in spec
    assert "console=False" in spec, "o aplicativo não pode abrir uma janela de Terminal"
    assert "AppIcon.icns" in spec


def test_spec_bundles_ffmpeg_under_a_predictable_name():
    spec = (ROOT / "MarquesLab4KDownload.spec").read_text(encoding="utf-8")
    assert 'stage(resolve_ffmpeg(), "ffmpeg")' in spec
    assert 'binaries = [(FFMPEG, ".")]' in spec


def test_entitlements_enable_hardened_runtime_requirements():
    data = plistlib.loads((PACKAGING / "entitlements.plist").read_bytes())
    assert data["com.apple.security.cs.disable-library-validation"] is True
    assert "com.apple.security.cs.allow-unsigned-executable-memory" in data


@pytest.mark.parametrize("script", SCRIPTS)
def test_packaging_scripts_are_executable(script):
    path = PACKAGING / script
    assert path.is_file(), f"{script} ausente"
    assert path.stat().st_mode & stat.S_IXUSR, f"{script} precisa ser executável"
    assert path.read_text(encoding="utf-8").startswith("#!/bin/bash")


def test_signing_refuses_anything_other_than_developer_id():
    script = (PACKAGING / "sign_app.sh").read_text(encoding="utf-8")
    assert "--options runtime" in script, "Hardened Runtime é obrigatório"
    assert "--timestamp" in script, "timestamp seguro é obrigatório para notarizar"
    assert "Developer ID Application" in script
    assert "--entitlements" in script


def test_release_pipeline_runs_every_gate_in_order():
    pipeline = (PACKAGING / "release_macos.sh").read_text(encoding="utf-8")
    order = [
        "build_app.sh", "check_apple_credentials.sh", "sign_app.sh",
        "notarize.sh", "make_dmg.sh", "verify_release.sh",
    ]
    positions = [pipeline.index(step) for step in order]
    assert positions == sorted(positions), "as etapas do release estão fora de ordem"


def test_final_verification_checks_gatekeeper_and_staple():
    verify = (PACKAGING / "verify_release.sh").read_text(encoding="utf-8")
    for command in ["codesign --verify", "spctl --assess", "stapler validate", "--self-test"]:
        assert command in verify, f"a validação final não executa: {command}"


def test_release_workflow_requires_credentials_before_building():
    workflow = yaml.safe_load(RELEASE_WORKFLOW.read_text(encoding="utf-8"))
    jobs = workflow["jobs"]
    assert "preflight" in jobs
    assert jobs["build"]["needs"] == "preflight"
    assert jobs["universal"]["needs"] == "preflight"
    steps = jobs["preflight"]["steps"]
    assert any("check_apple_credentials.sh" in str(step.get("run", "")) for step in steps)


def test_release_workflow_builds_both_architectures():
    workflow = yaml.safe_load(RELEASE_WORKFLOW.read_text(encoding="utf-8"))
    arches = {entry["arch"] for entry in workflow["jobs"]["build"]["strategy"]["matrix"]["include"]}
    assert arches == {"arm64", "x86_64"}
    assert "universal" in workflow["jobs"]


def test_release_workflow_passes_every_apple_secret():
    text = RELEASE_WORKFLOW.read_text(encoding="utf-8")
    for secret in [
        "APPLE_CERTIFICATE_BASE64", "APPLE_CERTIFICATE_PASSWORD", "APPLE_TEAM_ID",
        "APPLE_ID", "APPLE_APP_PASSWORD",
    ]:
        assert f"secrets.{secret}" in text, f"o workflow não repassa {secret}"


def test_release_workflow_publishes_a_github_release():
    workflow = yaml.safe_load(RELEASE_WORKFLOW.read_text(encoding="utf-8"))
    publish = workflow["jobs"]["publish"]
    assert set(publish["needs"]) == {"build", "universal"}
    assert "gh release create" in str(publish["steps"])


def test_ci_workflow_never_publishes_unsigned_artifacts():
    text = CI_WORKFLOW.read_text(encoding="utf-8")
    assert "gh release" not in text
    assert "sign_app.sh" not in text
    assert "self-test-download" in text, "o CI precisa provar um download real no app empacotado"


def test_credential_check_names_every_required_secret():
    text = (PACKAGING / "check_apple_credentials.sh").read_text(encoding="utf-8")
    for secret in ["APPLE_CERTIFICATE_BASE64", "APPLE_CERTIFICATE_PASSWORD", "APPLE_TEAM_ID"]:
        assert secret in text
    assert "DISTRIBUICAO.md" in text, "a mensagem de erro deve apontar a documentação"


def test_documentation_explains_the_secrets():
    doc = (ROOT / "DISTRIBUICAO.md").read_text(encoding="utf-8")
    for secret in [
        "APPLE_CERTIFICATE_BASE64", "APPLE_CERTIFICATE_PASSWORD", "APPLE_TEAM_ID",
        "APPLE_ID", "APPLE_APP_PASSWORD",
    ]:
        assert secret in doc
    assert "Developer ID Application" in doc


def test_ytdlp_tracks_the_nightly_channel():
    """Stable yt-dlp lags weeks behind and ships broken YouTube extractors.

    The stable 2026.7.4 returns "HTTP Error 403: Forbidden" on ordinary videos.
    The specifier must keep accepting pre-releases so every build picks up the
    newest extractor fixes.
    """
    text = (ROOT / "requirements.txt").read_text(encoding="utf-8")
    line = next(l for l in text.splitlines() if l.strip().startswith("yt-dlp"))
    assert ".dev" in line, (
        "o especificador do yt-dlp precisa aceitar pré-lançamentos "
        f"(canal nightly); encontrado: {line!r}"
    )
    assert "nightly" in text.lower(), "explique no arquivo por que o canal nightly é usado"
