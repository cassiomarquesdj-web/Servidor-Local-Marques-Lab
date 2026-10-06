"""Print every Mach-O file inside a bundle, deepest path first.

Used by the signing step so nested binaries are signed before their containers
(`codesign --deep` is unreliable and deprecated for distribution).
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from packaging_utils import iter_macho  # noqa: E402


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: list_macho.py <bundle>", file=sys.stderr)
        return 2
    for path in iter_macho(Path(sys.argv[1])):
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
