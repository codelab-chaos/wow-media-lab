"""Minimal read-only reader for a local CASC store (WoW game files): file data ID -> bytes.

Reads .build.info, the local .idx indices, the encoding table and the TSFM root.
BLTE chunks N (raw), Z (zlib) and F (nested) are supported. Encrypted chunks
raise, or with skip_encrypted=True come back zero-filled at their real size
(DB2 tables keep their unencrypted sections readable that way).
It never writes to the game folder.
"""

import os
import struct
import sys
import zlib
from pathlib import Path


def game_root(repo):
    """The game folder, found from WOW_ADDONS_DIR or the repo's .deploy-target
    (both name its Interface/AddOns folder)."""
    addons = os.environ.get("WOW_ADDONS_DIR")
    target = Path(repo) / ".deploy-target"
    if not addons and target.is_file():
        addons = target.read_text().splitlines()[0].strip()
    if not addons:
        sys.exit("Set WOW_ADDONS_DIR or .deploy-target (the game's Interface/AddOns folder).")
    return Path(addons).parents[2]


class Casc:
    def __init__(self, root, product="wowf"):
        self.root = Path(root)
        self.data = self.root / "Data"
        info = (self.root / ".build.info").read_text().splitlines()
        names = [column.split("!")[0] for column in info[0].split("|")]
        rows = [dict(zip(names, line.split("|"))) for line in info[1:] if line.strip()]
        row = next(r for r in rows if r.get("Product") == product)
        self.version = row.get("Version")
        self.build = self.config(row["Build Key"])
        self.index = self.load_indices()
        encoding_ekey = bytes.fromhex(self.build["encoding"].split()[1])
        self.encoding = self.load_encoding(self.read_ekey(encoding_ekey))
        self.files = self.load_root(self.read_ckey(bytes.fromhex(self.build["root"].split()[0])))

    def config(self, key):
        path = self.data / "config" / key[0:2] / key[2:4] / key
        result = {}
        for line in path.read_text().splitlines():
            if " = " in line:
                name, value = line.split(" = ", 1)
                result[name] = value
        return result

    def load_indices(self):
        latest = {}
        for path in (self.data / "data").glob("*.idx"):
            bucket = int(path.stem[0:2], 16)
            version = int(path.stem[2:], 16)
            if bucket not in latest or version > latest[bucket][0]:
                latest[bucket] = (version, path)
        index = {}
        for _, path in latest.values():
            raw = path.read_bytes()
            spans = raw[12:16]
            size_bytes, offset_bytes, key_bytes, offset_bits = spans
            entries_size = struct.unpack_from("<I", raw, 0x20)[0]
            entry = key_bytes + offset_bytes + size_bytes
            mask = (1 << offset_bits) - 1
            for at in range(0x28, 0x28 + entries_size, entry):
                key = raw[at:at + key_bytes]
                packed = int.from_bytes(raw[at + key_bytes:at + key_bytes + offset_bytes], "big")
                size = int.from_bytes(raw[at + key_bytes + offset_bytes:at + entry], "little")
                index.setdefault(key, (packed >> offset_bits, packed & mask, size))
        return index

    def read_ekey(self, ekey, skip_encrypted=False):
        archive, offset, size = self.index[ekey[:9]]
        with open(self.data / "data" / f"data.{archive:03d}", "rb") as handle:
            handle.seek(offset + 30)
            return blte(handle.read(size - 30), skip_encrypted)

    def load_encoding(self, raw):
        assert raw[:2] == b"EN", raw[:2]
        ckey_size, ekey_size = raw[3], raw[4]
        ce_page_kb, = struct.unpack_from(">H", raw, 5)
        ce_pages, = struct.unpack_from(">I", raw, 9)
        espec_size = int.from_bytes(raw[17:22], "big")
        at = 22 + espec_size + ce_pages * 32
        result = {}
        for _ in range(ce_pages):
            page = raw[at:at + ce_page_kb * 1024]
            at += ce_page_kb * 1024
            p = 0
            while p < len(page) and page[p] != 0:
                count = page[p]
                ckey = page[p + 6:p + 6 + ckey_size]
                result[ckey] = page[p + 6 + ckey_size:p + 6 + ckey_size + ekey_size]
                p += 6 + ckey_size + count * ekey_size
        return result

    def read_ckey(self, ckey, skip_encrypted=False):
        return self.read_ekey(self.encoding[ckey], skip_encrypted)

    def load_root(self, raw):
        assert raw[:4] == b"TSFM", raw[:4]
        header_size, version = struct.unpack_from("<II", raw, 4)
        if header_size == 0x18:
            at = header_size
        else:
            version, at = 1, 12
        files = {}
        while at < len(raw):
            if version >= 2:
                count, locale, flags1, flags2 = struct.unpack_from("<IIII", raw, at)
                flags = flags1 | flags2 | (raw[at + 16] << 17)
                at += 17
            else:
                count, flags, locale = struct.unpack_from("<III", raw, at)
                at += 12
            deltas = struct.unpack_from(f"<{count}i", raw, at)
            at += 4 * count
            ckeys = at
            at += 16 * count
            if not flags & 0x10000000:
                at += 8 * count
            fdid = -1
            english = locale & 0x2 or locale == 0xFFFFFFFF or locale & 0x1FFFE == 0x1FFFE
            for i, delta in enumerate(deltas):
                fdid += delta + 1
                if english or fdid not in files:
                    files[fdid] = raw[ckeys + 16 * i:ckeys + 16 * i + 16]
        return files

    def read(self, fdid, skip_encrypted=False):
        return self.read_ckey(self.files[fdid], skip_encrypted)


def blte(raw, skip_encrypted=False):
    assert raw[:4] == b"BLTE", raw[:4]
    header, = struct.unpack_from(">I", raw, 4)
    if header == 0:
        return chunk(raw[8:])
    count = int.from_bytes(raw[9:12], "big")
    at, out = header, []
    for i in range(count):
        size, plain = struct.unpack_from(">II", raw, 12 + i * 24)
        data = raw[at:at + size]
        out.append(b"\0" * plain if skip_encrypted and data[:1] == b"E" else chunk(data))
        at += size
    return b"".join(out)


def chunk(data):
    mode = data[:1]
    if mode == b"N":
        return data[1:]
    if mode == b"Z":
        return zlib.decompress(data[1:])
    if mode == b"F":
        return blte(data[1:])
    raise ValueError(f"unsupported BLTE chunk {mode!r}")
