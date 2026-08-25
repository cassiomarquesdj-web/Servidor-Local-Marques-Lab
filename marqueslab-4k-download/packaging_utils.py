"""Helpers shared by the packaging scripts and their tests."""
from __future__ import annotations

from pathlib import Path
from typing import Iterator

MACH_O_MAGIC = {
    b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce",
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
}


def is_macho(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            return handle.read(4) in MACH_O_MAGIC
    except OSError:
        return False


def iter_macho(root: Path) -> Iterator[Path]:
    """Yield every Mach-O file inside `root`, deepest path first."""
    found = [p for p in root.rglob("*") if p.is_file() and not p.is_symlink() and is_macho(p)]
    yield from sorted(found, key=lambda p: (len(p.parts), str(p)), reverse=True)
