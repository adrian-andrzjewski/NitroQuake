#!/usr/bin/env python3
"""Create a small DOS-friendly ISO-9660 image without external ISO tools."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import stat
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

SECTOR = 2048
ALLOWED = re.compile(r"^[A-Z0-9_!$%&'()@^`{}~-]+$")


@dataclass
class Entry:
    path: Path
    name: str
    directory: bool
    parent: "Entry | None" = None
    children: list["Entry"] = field(default_factory=list)
    size: int = 0
    extent: int = 0
    path_index: int = 0

    @property
    def iso_name(self) -> bytes:
        if self.directory:
            return self.name.encode("ascii")
        return (self.name + ";1").encode("ascii")


def sectors(size: int) -> int:
    return (size + SECTOR - 1) // SECTOR


def both16(value: int) -> bytes:
    return value.to_bytes(2, "little") + value.to_bytes(2, "big")


def both32(value: int) -> bytes:
    return value.to_bytes(4, "little") + value.to_bytes(4, "big")


def disk_name(name: str, is_directory: bool) -> str:
    if not name or name in {".", ".."} or name != name.upper():
        raise ValueError(f"ISO names must be uppercase DOS names: {name!r}")
    if not name.isascii():
        raise ValueError(f"ISO name is not ASCII: {name!r}")
    if is_directory:
        if "." in name or len(name) > 8 or not ALLOWED.fullmatch(name):
            raise ValueError(f"Directory is not ISO level-1 / DOS 8.3 compatible: {name!r}")
        return name
    stem, dot, extension = name.partition(".")
    if (not stem or len(stem) > 8 or (dot and (not extension or len(extension) > 3))
            or "." in extension or not ALLOWED.fullmatch(stem)
            or (extension and not ALLOWED.fullmatch(extension))):
        raise ValueError(f"File is not ISO level-1 / DOS 8.3 compatible: {name!r}")
    return name


def reject_redirected(path: Path) -> None:
    info = path.lstat()
    attrs = getattr(info, "st_file_attributes", 0)
    reparse = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
    if stat.S_ISLNK(info.st_mode) or attrs & reparse:
        raise ValueError(f"ISO staging tree contains a link or reparse point: {path}")


def collect_tree(root_path: Path) -> tuple[Entry, list[Entry], list[Entry]]:
    root_path = root_path.resolve(strict=True)
    if not root_path.is_dir():
        raise ValueError(f"ISO tree is not a directory: {root_path}")
    reject_redirected(root_path)
    root = Entry(root_path, "", True)
    directories = [root]
    files: list[Entry] = []

    def add_children(parent: Entry) -> None:
        seen: set[str] = set()
        for path in sorted(parent.path.iterdir(), key=lambda item: item.name.upper()):
            reject_redirected(path)
            is_directory = path.is_dir()
            name = disk_name(path.name.upper(), is_directory)
            folded = name.casefold()
            if folded in seen:
                raise ValueError(f"Duplicate ISO name in {parent.path}: {name}")
            seen.add(folded)
            child = Entry(path, name, is_directory, parent)
            if is_directory:
                parent.children.append(child)
                directories.append(child)
                add_children(child)
            elif path.is_file():
                child.size = path.stat().st_size
                parent.children.append(child)
                files.append(child)
            else:
                raise ValueError(f"Unsupported staging entry: {path}")

    add_children(root)
    for index, directory in enumerate(directories, 1):
        directory.path_index = index
    return root, directories, files


def path_table_size(directories: list[Entry]) -> int:
    total = 0
    for directory in directories:
        length = 1 if directory is directories[0] else len(directory.name)
        total += 8 + length + (length & 1)
    return total


def path_table(directories: list[Entry], big_endian: bool) -> bytes:
    out = bytearray()
    for directory in directories:
        name = b"\0" if directory is directories[0] else directory.name.encode("ascii")
        extent = directory.extent.to_bytes(4, "big" if big_endian else "little")
        parent_index = 1 if directory.parent is None else directory.parent.path_index
        parent = parent_index.to_bytes(2, "big" if big_endian else "little")
        out.extend((len(name), 0))
        out.extend(extent)
        out.extend(parent)
        out.extend(name)
        if len(name) & 1:
            out.append(0)
    return bytes(out)


def directory_record(name: bytes, extent: int, size: int, is_directory: bool) -> bytes:
    record_length = 33 + len(name) + (1 if not (len(name) & 1) else 0)
    record = bytearray(record_length)
    record[0] = record_length
    record[1] = 0
    record[2:10] = both32(extent)
    record[10:18] = both32(size)
    record[18:25] = bytes((126, 1, 1, 0, 0, 0, 0))  # fixed 2026-01-01 UTC
    record[25] = 2 if is_directory else 0
    record[26] = 0
    record[27] = 0
    record[28:32] = both16(1)
    record[32] = len(name)
    record[33:33 + len(name)] = name
    return bytes(record)


def directory_bytes(directory: Entry) -> bytes:
    entries = [
        directory_record(b"\0", directory.extent, directory.size, True),
        directory_record(
            b"\1",
            directory.extent if directory.parent is None else directory.parent.extent,
            directory.size if directory.parent is None else directory.parent.size,
            True,
        ),
    ]
    for child in directory.children:
        entries.append(directory_record(child.iso_name, child.extent, child.size, child.directory))

    out = bytearray()
    for record in entries:
        remaining = SECTOR - (len(out) % SECTOR)
        if len(record) > remaining:
            out.extend(bytes(remaining))
        out.extend(record)
    if len(out) % SECTOR:
        out.extend(bytes(SECTOR - len(out) % SECTOR))
    return bytes(out)


def pvd(root: Entry, volume_id: str, total_sectors: int, table_size: int,
        l_table_sector: int, m_table_sector: int) -> bytes:
    descriptor = bytearray(SECTOR)
    descriptor[0:7] = b"\x01CD001\x01"
    descriptor[8:40] = b"NITROQUAKE".ljust(32, b" ")
    descriptor[40:72] = volume_id.encode("ascii").ljust(32, b" ")
    descriptor[80:88] = both32(total_sectors)
    descriptor[120:124] = both16(1)
    descriptor[124:128] = both16(1)
    descriptor[128:132] = both16(SECTOR)
    descriptor[132:140] = both32(table_size)
    descriptor[140:144] = l_table_sector.to_bytes(4, "little")
    descriptor[144:148] = (0).to_bytes(4, "little")
    descriptor[148:152] = m_table_sector.to_bytes(4, "big")
    descriptor[152:156] = (0).to_bytes(4, "big")
    descriptor[156:190] = directory_record(b"\0", root.extent, root.size, True)
    descriptor[190:318] = b"NITROQUAKE".ljust(128, b" ")
    descriptor[318:446] = b"NITROQUAKE DOS BENCHMARK".ljust(128, b" ")
    descriptor[446:574] = b"NITROQUAKE DOS BENCHMARK BUILDER".ljust(128, b" ")
    descriptor[574:702] = b"NITROQUAKE".ljust(128, b" ")
    date = b"2026010100000000\0"
    for offset in (814, 831, 848, 865):
        descriptor[offset:offset + 17] = date
    descriptor[882] = 1
    return bytes(descriptor)


def build(tree: Path, output: Path, volume_id: str, force: bool) -> None:
    if not re.fullmatch(r"[A-Z0-9_]{1,32}", volume_id):
        raise ValueError("Volume ID must be 1-32 uppercase ISO characters")
    output = output.expanduser().resolve()
    if output.exists() and not force:
        raise FileExistsError(f"Output exists; pass --force to replace it: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)

    root, directories, files = collect_tree(tree)
    table_size = path_table_size(directories)
    table_sectors = sectors(table_size)
    l_table_sector = 18
    m_table_sector = l_table_sector + table_sectors
    next_sector = m_table_sector + table_sectors

    # First size every directory, then assign extents in ISO path-table order.
    for directory in directories:
        directory.extent = 0
        directory.size = 0
    for directory in directories:
        probe = directory_bytes(directory)
        directory.size = len(probe)
    for directory in directories:
        directory.extent = next_sector
        next_sector += sectors(directory.size)
    for item in files:
        item.extent = next_sector
        next_sector += sectors(item.size)
    total_sectors = next_sector
    if total_sectors > 0xFFFFFFFF:
        raise ValueError("ISO image exceeds ISO-9660 volume-space limit")

    little_table = path_table(directories, False)
    big_table = path_table(directories, True)
    if len(little_table) != table_size or len(big_table) != table_size:
        raise AssertionError("Path table size calculation mismatch")

    descriptor = pvd(root, volume_id, total_sectors, table_size,
                     l_table_sector, m_table_sector)
    terminator = bytearray(SECTOR)
    terminator[0:7] = b"\xffCD001\x01"

    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=output.name + ".", suffix=".tmp", dir=output.parent)
    os.close(fd)
    temp = Path(temp_name)
    try:
        with temp.open("wb") as stream:
            stream.truncate(total_sectors * SECTOR)
            stream.seek(16 * SECTOR)
            stream.write(descriptor)
            stream.write(terminator)
            stream.seek(l_table_sector * SECTOR)
            stream.write(little_table)
            stream.seek(m_table_sector * SECTOR)
            stream.write(big_table)
            for directory in directories:
                stream.seek(directory.extent * SECTOR)
                stream.write(directory_bytes(directory))
            for item in files:
                stream.seek(item.extent * SECTOR)
                with item.path.open("rb") as source:
                    shutil.copyfileobj(source, stream, 1024 * 1024)
        if output.exists() and not force:
            raise FileExistsError(f"Output appeared during build; refusing to replace it: {output}")
        os.replace(temp, output)
    finally:
        if temp.exists():
            temp.unlink()

    print(f"ISO: {output}")
    print(f"Volume: {volume_id}; sectors: {total_sectors}; bytes: {total_sectors * SECTOR}")
    print(f"Entries: {len(directories)} directories, {len(files)} files")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tree", required=True, type=Path, help="staged ISO directory tree")
    parser.add_argument("--output", required=True, type=Path, help="output ISO path")
    parser.add_argument("--volume-id", default="NQBENCH", help="ISO volume ID (uppercase)")
    parser.add_argument("--force", action="store_true", help="replace an existing output ISO")
    args = parser.parse_args()
    try:
        build(args.tree, args.output, args.volume_id, args.force)
    except (OSError, ValueError) as exc:
        print(f"build-iso9660: error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
