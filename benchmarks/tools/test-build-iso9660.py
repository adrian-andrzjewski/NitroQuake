#!/usr/bin/env python3
"""Host tests for the DOS ISO-9660 writer and its emitted structures."""

from __future__ import annotations

import importlib.util
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "build_iso9660", ROOT / "tools" / "build-iso9660.py")
assert SPEC is not None and SPEC.loader is not None
ISO = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = ISO
SPEC.loader.exec_module(ISO)


def parse_directory(image: bytes, extent: int, size: int) -> list[dict[str, object]]:
    data = image[extent * ISO.SECTOR:extent * ISO.SECTOR + size]
    records: list[dict[str, object]] = []
    offset = 0
    while offset < len(data):
        length = data[offset]
        if length == 0:
            offset = ((offset // ISO.SECTOR) + 1) * ISO.SECTOR
            continue
        record = data[offset:offset + length]
        if len(record) != length or length < 34:
            raise AssertionError("truncated directory record")
        name_length = record[32]
        name = record[33:33 + name_length]
        records.append({
            "name": name,
            "extent": int.from_bytes(record[2:6], "little"),
            "extent_be": int.from_bytes(record[6:10], "big"),
            "size": int.from_bytes(record[10:14], "little"),
            "size_be": int.from_bytes(record[14:18], "big"),
            "flags": record[25],
        })
        offset += length
    return records


def parse_path_table(data: bytes, endian: str) -> list[tuple[bytes, int, int]]:
    entries: list[tuple[bytes, int, int]] = []
    offset = 0
    while offset < len(data):
        name_length = data[offset]
        if name_length == 0:
            break
        record_length = 8 + name_length + (name_length & 1)
        record = data[offset:offset + record_length]
        if len(record) != record_length:
            raise AssertionError("truncated path table record")
        entries.append((
            record[8:8 + name_length],
            int.from_bytes(record[2:6], endian),
            int.from_bytes(record[6:8], endian),
        ))
        offset += record_length
    return entries


class FakePath:
    """Small filesystem stand-in for Windows-unrepresentable duplicate names."""

    def __init__(self, name: str, *, directory: bool, size: int = 0,
                 children: tuple["FakePath", ...] = (), mode: int | None = None,
                 attributes: int = 0) -> None:
        self.name = name
        self.directory = directory
        self.size = size
        self.children = children
        self.mode = mode if mode is not None else (
            stat.S_IFDIR if directory else stat.S_IFREG)
        self.attributes = attributes

    def resolve(self, *, strict: bool = False) -> "FakePath":
        return self

    def lstat(self) -> SimpleNamespace:
        return SimpleNamespace(st_mode=self.mode,
                               st_file_attributes=self.attributes)

    def is_dir(self) -> bool:
        return self.directory

    def is_file(self) -> bool:
        return not self.directory

    def iterdir(self) -> tuple["FakePath", ...]:
        return self.children

    def stat(self) -> SimpleNamespace:
        return SimpleNamespace(st_size=self.size)

    def __str__(self) -> str:
        return self.name


class IsoWriterTests(unittest.TestCase):
    def test_structures_extents_alignment_and_payload(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "tree"
            (root / "EMPTY").mkdir(parents=True)
            (root / "NESTED").mkdir()
            (root / "NESTED" / "CHILD.TXT").write_bytes(b"nested payload")
            payloads = {
                "ZERO.DAT": b"",
                "ONE.BIN": b"x",
                "END0.BIN": bytes((index & 0xFF) for index in range(2047)),
                "END1.BIN": bytes((index & 0xFF) for index in range(2048)),
                "END2.BIN": bytes((index & 0xFF) for index in range(2049)),
                "BIG.BIN": bytes((index * 7 & 0xFF) for index in range(4097)),
            }
            for name, payload in payloads.items():
                (root / name).write_bytes(payload)

            output = Path(temporary) / "result.iso"
            ISO.build(root, output, "NQTEST", force=False)
            image = output.read_bytes()
            self.assertEqual(len(image) % ISO.SECTOR, 0)
            self.assertEqual(image[:16 * ISO.SECTOR], bytes(16 * ISO.SECTOR))

            pvd = image[16 * ISO.SECTOR:17 * ISO.SECTOR]
            self.assertEqual(pvd[:7], b"\x01CD001\x01")
            self.assertEqual(pvd[40:72].rstrip(b" "), b"NQTEST")
            self.assertEqual(pvd[80:84], pvd[84:88][::-1])
            self.assertEqual(image[17 * ISO.SECTOR:17 * ISO.SECTOR + 7],
                             b"\xffCD001\x01")

            table_size = int.from_bytes(pvd[132:136], "little")
            self.assertEqual(table_size, int.from_bytes(pvd[136:140], "big"))
            little_extent = int.from_bytes(pvd[140:144], "little")
            big_extent = int.from_bytes(pvd[148:152], "big")
            self.assertEqual(int.from_bytes(pvd[144:148], "little"), 0)
            self.assertEqual(int.from_bytes(pvd[152:156], "big"), 0)
            little_data = image[little_extent * ISO.SECTOR:
                                little_extent * ISO.SECTOR + table_size]
            big_data = image[big_extent * ISO.SECTOR:
                             big_extent * ISO.SECTOR + table_size]
            little = parse_path_table(little_data, "little")
            big = parse_path_table(big_data, "big")
            self.assertEqual(little, big)
            self.assertEqual([entry[0] for entry in little],
                             [b"\0", b"EMPTY", b"NESTED"])
            self.assertEqual([entry[2] for entry in little], [1, 1, 1])

            root_record = pvd[156:190]
            root_extent = int.from_bytes(root_record[2:6], "little")
            root_size = int.from_bytes(root_record[10:14], "little")
            self.assertEqual(root_extent * ISO.SECTOR % ISO.SECTOR, 0)
            root_records = parse_directory(image, root_extent, root_size)
            self.assertEqual([record["name"] for record in root_records[:2]],
                             [b"\0", b"\1"])
            root_children = {record["name"]: record for record in root_records[2:]}
            for name in ("EMPTY", "NESTED"):
                record = root_children[name.encode("ascii")]
                self.assertEqual(record["extent"], record["extent_be"])
                self.assertEqual(record["size"], record["size_be"])
                self.assertEqual(record["flags"], 2)
                self.assertEqual(int(record["extent"]) * ISO.SECTOR % ISO.SECTOR, 0)

            empty_record = root_children[b"EMPTY"]
            empty_records = parse_directory(image, int(empty_record["extent"]),
                                             int(empty_record["size"]))
            self.assertEqual([record["name"] for record in empty_records],
                             [b"\0", b"\1"])

            nested_record = root_children[b"NESTED"]
            nested_records = parse_directory(image, int(nested_record["extent"]),
                                              int(nested_record["size"]))
            self.assertEqual(nested_records[1]["extent"], root_extent)
            child_record = next(record for record in nested_records
                                if record["name"] == b"CHILD.TXT;1")
            child_offset = int(child_record["extent"]) * ISO.SECTOR
            self.assertEqual(image[child_offset:child_offset + 14], b"nested payload")

            allocated = [(root_extent, root_size)]
            allocated.extend((int(record["extent"]), int(record["size"]))
                             for record in root_children.values()
                             if record["flags"] == 2)
            allocated.extend((int(record["extent"]), int(record["size"]))
                             for record in root_children.values()
                             if record["flags"] == 0)
            allocated.append((int(child_record["extent"]), int(child_record["size"])))
            cursor = 18 + 2 * ISO.sectors(table_size)
            for extent, size in sorted((extent, size) for extent, size in allocated if size):
                self.assertEqual(extent, cursor, "directory/file extents must be contiguous")
                cursor += ISO.sectors(size)
            self.assertEqual(cursor, len(image) // ISO.SECTOR)

            for name, payload in payloads.items():
                record = root_children[(name + ";1").encode("ascii")]
                extent = int(record["extent"])
                start = extent * ISO.SECTOR
                self.assertEqual(start % ISO.SECTOR, 0)
                self.assertEqual(int(record["size"]), len(payload))
                self.assertEqual(image[start:start + len(payload)], payload)
                if payload:
                    aligned_size = ISO.sectors(len(payload)) * ISO.SECTOR
                    self.assertEqual(image[start + len(payload):start + aligned_size],
                                     bytes(aligned_size - len(payload)))

            self.assertEqual(int.from_bytes(pvd[80:84], "little"),
                             len(image) // ISO.SECTOR)

    def test_invalid_names_and_duplicate_names_are_rejected(self) -> None:
        for name, is_directory in (("lower.txt", False), ("BAD:NAME.TXT", False),
                                   ("TOOLONGNAME.TXT", False), ("A.LONGEXT", False),
                                   ("BAD.NAME", True)):
            with self.subTest(name=name):
                with self.assertRaises(ValueError):
                    ISO.disk_name(name, is_directory)

        duplicate_root = FakePath("root", directory=True, children=(
            FakePath("foo.txt", directory=False, size=1),
            FakePath("FOO.TXT", directory=False, size=1),
        ))
        with self.assertRaisesRegex(ValueError, "Duplicate ISO name"):
            ISO.collect_tree(duplicate_root)  # type: ignore[arg-type]

    def test_links_and_reparse_points_are_rejected(self) -> None:
        reparse_root = FakePath("root", directory=True, attributes=0x400)
        with self.assertRaisesRegex(ValueError, "link or reparse point"):
            ISO.collect_tree(reparse_root)  # type: ignore[arg-type]

        linked_child = FakePath("LINK", directory=False, mode=stat.S_IFLNK)
        linked_root = FakePath("root", directory=True, children=(linked_child,))
        with self.assertRaisesRegex(ValueError, "link or reparse point"):
            ISO.collect_tree(linked_root)  # type: ignore[arg-type]


if __name__ == "__main__":
    unittest.main()
