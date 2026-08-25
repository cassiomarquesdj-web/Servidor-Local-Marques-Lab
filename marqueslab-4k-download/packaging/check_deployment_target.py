"""Fail the build when Info.plist promises support for an older macOS than the
binaries actually require.

Every Mach-O file in the bundle records the minimum OS it was built for. If any
of them is newer than LSMinimumSystemVersion the application would install on a
machine where it simply cannot launch.
"""
from __future__ import annotations

import plistlib
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from packaging_utils import iter_macho  # noqa: E402

MINOS = re.compile(r"^\s*minos (\d+(?:\.\d+)*)", re.MULTILINE)
VERSION_MIN = re.compile(r"^\s*version (\d+(?:\.\d+)*)", re.MULTILINE)


def as_tuple(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in value.split("."))


def required_version(path: Path) -> tuple[int, ...] | None:
    output = subprocess.run(["otool", "-l", str(path)], capture_output=True, text=True).stdout
    versions = [as_tuple(v) for v in MINOS.findall(output)]
    if not versions:
        if "LC_VERSION_MIN_MACOSX" in output:
            versions = [as_tuple(v) for v in VERSION_MIN.findall(output)]
    return max(versions) if versions else None


def main() -> int:
    bundle = Path(sys.argv[1])
    plist_path = bundle / "Contents" / "Info.plist"
    declared = as_tuple(plistlib.loads(plist_path.read_bytes())["LSMinimumSystemVersion"])

    worst = (0,)
    worst_file = None
    for binary in iter_macho(bundle):
        version = required_version(binary)
        if version and version > worst:
            worst, worst_file = version, binary

    declared_text = ".".join(str(p) for p in declared)
    worst_text = ".".join(str(p) for p in worst)
    print(f"LSMinimumSystemVersion declarado: {declared_text}")
    print(f"Maior requisito real encontrado:   {worst_text} ({worst_file.name if worst_file else '—'})")

    if worst > declared:
        print(
            f"ERRO: {worst_file} exige macOS {worst_text}, mas o Info.plist promete "
            f"{declared_text}. Ajuste branding.MINIMUM_MACOS.",
            file=sys.stderr,
        )
        return 1
    print("DEPLOYMENT_TARGET: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
