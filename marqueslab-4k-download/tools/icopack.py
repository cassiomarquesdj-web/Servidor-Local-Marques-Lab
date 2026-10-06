"""Build a Windows .ico from PNG files, with no third-party dependency.

The ICO container is a small index followed by the images themselves. Windows
Vista and later read PNG-compressed entries at every size, so the PNGs the macOS
iconset already contains can be reused verbatim — the artwork has a single
source and the two platforms cannot drift apart.
"""
from __future__ import annotations

import struct
from pathlib import Path

ICONDIR = "<HHH"          # reserved, type (1 = icon), image count
ICONDIRENTRY = "<BBBBHHII"  # w, h, colours, reserved, planes, bpp, size, offset
HEADER_SIZE = struct.calcsize(ICONDIR)
ENTRY_SIZE = struct.calcsize(ICONDIRENTRY)
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def png_size(data: bytes) -> tuple[int, int]:
    if not data.startswith(PNG_MAGIC):
        raise ValueError("não é um PNG")
    # IHDR is always the first chunk: 8 magic + 4 length + 4 type, then w/h.
    width, height = struct.unpack(">II", data[16:24])
    return width, height


def build_ico(sources: list[Path], target: Path) -> Path:
    images: list[tuple[int, int, bytes]] = []
    for source in sources:
        data = source.read_bytes()
        width, height = png_size(data)
        if not 1 <= width <= 256 or not 1 <= height <= 256:
            continue  # the format stores the side in a single byte
        if any(width == w and height == h for w, h, _ in images):
            continue  # the iconset holds 16@2x and 32 at the same 32px size
        images.append((width, height, data))

    if not images:
        raise SystemExit("nenhum PNG de até 256px disponível para montar o .ico")

    images.sort(key=lambda item: item[0])
    offset = HEADER_SIZE + ENTRY_SIZE * len(images)
    directory = bytearray(struct.pack(ICONDIR, 0, 1, len(images)))
    payload = bytearray()

    for width, height, data in images:
        directory += struct.pack(
            ICONDIRENTRY,
            width % 256,   # 256 is stored as 0
            height % 256,
            0, 0, 1, 32,
            len(data),
            offset + len(payload),
        )
        payload += data

    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(bytes(directory) + bytes(payload))
    return target


def describe(path: Path) -> list[tuple[int, int]]:
    """Read an .ico back and report the sizes it declares."""
    data = path.read_bytes()
    _, kind, count = struct.unpack_from(ICONDIR, data, 0)
    if kind != 1:
        raise ValueError("não é um ícone do Windows")
    sizes = []
    for index in range(count):
        entry = struct.unpack_from(ICONDIRENTRY, data, HEADER_SIZE + index * ENTRY_SIZE)
        sizes.append((entry[0] or 256, entry[1] or 256))
    return sizes


def main() -> int:
    root = Path(__file__).resolve().parents[1] / "assets"
    iconset = root / "AppIcon.iconset"
    wanted = ["16x16", "16x16@2x", "32x32", "32x32@2x", "128x128", "256x256"]
    sources = [p for name in wanted if (p := iconset / f"icon_{name}.png").is_file()]
    target = build_ico(sources, root / "AppIcon.ico")
    print(f"ICO: {target} ({target.stat().st_size} bytes)")
    print("tamanhos:", ", ".join(f"{w}x{h}" for w, h in describe(target)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
