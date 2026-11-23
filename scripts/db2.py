"""Minimal read-only WDC5 (DB2) reader, with column names and types from WoWDBDefs.

Handles inline and sparse (offset map) tables, strings, floats, signed fields,
pallet, common, copy and relationship data. Encrypted sections (newer content
the client has no key for yet) come back from casc.py zero-filled and are
skipped. Rows are dicts keyed by the DBD column names; arrays are lists.
"""

import io
import re
import struct
import urllib.request
import zipfile
from pathlib import Path

DBD_ZIP = "https://github.com/wowdev/WoWDBDefs/archive/refs/heads/master.zip"


class Field:
    """One column of a layout: its name, where it is stored and how to decode it."""

    def __init__(self, name, is_id=False, inline=True, count=1, kind="int", size=32, signed=False):
        self.name, self.is_id, self.inline, self.count = name, is_id, inline, count
        self.kind, self.size, self.signed = kind, size, signed

    def columns(self):
        """Column names as stored in SQL: Name, or Name_0..Name_n for arrays."""
        return [self.name] if self.count == 1 else [f"{self.name}_{i}" for i in range(self.count)]

    def __repr__(self):
        return f"Field({self.name!r}, {self.kind}, {self.size}, count={self.count})"


def definitions(cache):
    """Every WoWDBDefs .dbd file, downloaded once into cache: {lowercase table: path}."""
    folder = Path(cache)
    if not (folder / ".complete").exists():
        folder.mkdir(parents=True, exist_ok=True)
        print(f"downloading {DBD_ZIP}")
        with urllib.request.urlopen(DBD_ZIP, timeout=120) as response:
            archive = zipfile.ZipFile(io.BytesIO(response.read()))
        for member in archive.namelist():
            parts = member.split("/")
            if len(parts) == 3 and parts[1] == "definitions" and parts[2].endswith(".dbd"):
                (folder / parts[2]).write_bytes(archive.read(member))
        (folder / ".complete").write_text("")
    return {path.stem.lower(): path for path in folder.glob("*.dbd")}


def dbd_layout(table, layout_hash, cache):
    """The record fields of a table's layout hash, as a list of Field."""
    files = definitions(cache)
    path = files.get(table.lower())
    if not path:
        raise ValueError(f"{table}: no WoWDBDefs definition")
    lines = path.read_text().splitlines()
    types = {}
    for line in lines:
        if line.startswith("LAYOUT") or line.startswith("BUILD"):
            break
        match = re.match(r"^(int|float|string|locstring)(?:<[^>]*>)?\s+([A-Za-z_0-9]+)", line)
        if match:
            types[match.group(2)] = "string" if "string" in match.group(1) else match.group(1)
    wanted = f"{layout_hash:08X}"
    fields, active = [], False
    for line in lines:
        if line.startswith("LAYOUT "):
            active = wanted in [value.strip() for value in line[7:].split(",")]
            fields = [] if active else fields
            continue
        if not active:
            continue
        if not line.strip():
            if fields:
                break
            continue
        if line.startswith(("BUILD", "COMMENT")):
            continue
        match = re.match(r"^(?:\$([^$]*)\$)?([A-Za-z_0-9]+)(?:<(u?)(\d+)>)?(?:\[(\d+)\])?", line)
        options = (match.group(1) or "").split(",")
        name = match.group(2)
        fields.append(Field(name, is_id="id" in options, inline="noninline" not in options,
                            count=int(match.group(5) or 1), kind=types.get(name, "int"),
                            size=int(match.group(4) or 32), signed=match.group(4) is not None and not match.group(3)))
    if not fields:
        raise ValueError(f"{table}: no WoWDBDefs layout {wanted}")
    return fields


def layout_hash(raw):
    return struct.unpack_from("<I", raw, 136 + 20)[0]


def bits(data, offset_bits, size_bits):
    start = offset_bits >> 3
    value = int.from_bytes(data[start:start + ((offset_bits & 7) + size_bits + 7) // 8], "little")
    return (value >> (offset_bits & 7)) & ((1 << size_bits) - 1)


def signed(value, size):
    return value - (1 << size) if value >> (size - 1) else value


def decode(field, value):
    """A stored 32-bit (or narrower) value as the field's type."""
    if field.kind == "float":
        return round(struct.unpack("<f", struct.pack("<I", value & 0xFFFFFFFF))[0], 6)
    if field.signed and field.size <= 32:
        return signed(value & ((1 << field.size) - 1), field.size)
    return value


def cstring(data, start):
    end = data.find(b"\0", start)
    return data[start:end if end >= 0 else len(data)].decode("utf-8", "replace"), end + 1


def read(raw, table, cache):
    if raw[:4] != b"WDC5":
        raise ValueError(f"{table}: not WDC5 ({raw[:4]!r})")
    at = 136
    (records, field_count, record_size, _strings, _table_hash, layout, _min, _max, _locale, flags,
     id_index, _total_fields, _bitpacked_offset, _lookup, storage_size, _common_size, _pallet_size,
     section_count) = struct.unpack_from("<9IHH7I", raw, at)
    at += 4 * 9 + 2 * 2 + 4 * 7
    sparse = bool(flags & 1)
    sections = []
    for _ in range(section_count):
        sections.append(struct.unpack_from("<Q8I", raw, at))
        at += 40
    at += 4 * field_count  # field_structure, also described by storage info
    storage = []
    for _ in range(storage_size // 24):
        storage.append(struct.unpack_from("<HHIIIII", raw, at))
        at += 24
    pallet, common = {}, {}
    for index, info in enumerate(storage):
        if info[3] in (3, 4):
            pallet[index] = raw[at:at + info[2]]
            at += info[2]
    for index, info in enumerate(storage):
        if info[3] == 2:
            common[index] = dict(struct.iter_unpack("<II", raw[at:at + info[2]]))
            at += info[2]

    layout_fields = dbd_layout(table, layout, cache)
    inline = [field for field in layout_fields if field.inline]
    relation = next((field for field in layout_fields if not field.inline and not field.is_id), None)
    if len(inline) != field_count:
        raise ValueError(f"{table}: DBD has {len(inline)} inline fields, file has {field_count}")

    # Non-sparse strings are offsets from the field to one string table that,
    # conceptually, follows every section's records.
    strings = b"".join(raw[s[1] + s[2] * record_size:s[1] + s[2] * record_size + s[3]] for s in sections)
    strings_start = records * record_size

    rows, first_record = [], 0
    for (_key, offset, count, string_size, records_end, id_size, relation_size, map_count,
         copy_count) in sections:
        section_first, first_record = first_record, first_record + count
        body_end = records_end if sparse else offset + count * record_size
        if not any(raw[offset:body_end]):
            continue  # an encrypted section, zero-filled
        cursor = body_end if sparse else body_end + string_size
        ids = list(struct.unpack_from(f"<{id_size // 4}I", raw, cursor)) if id_size else None
        cursor += id_size
        copies = [struct.unpack_from("<II", raw, cursor + i * 8) for i in range(copy_count)]
        cursor += copy_count * 8
        offset_map = [struct.unpack_from("<IH", raw, cursor + i * 6) for i in range(map_count)]
        cursor += map_count * 6
        relations = {}
        if relation_size:
            entries, = struct.unpack_from("<I", raw, cursor)
            for i in range(entries):
                foreign, record = struct.unpack_from("<II", raw, cursor + 12 + i * 8)
                relations[record] = foreign
            cursor += relation_size
        map_ids = list(struct.unpack_from(f"<{map_count}I", raw, cursor)) if sparse and map_count else None

        section_rows = []
        if sparse:
            for record, (start, size) in enumerate(offset_map):
                if not size:
                    continue
                row = sparse_row(raw, start, inline, storage)
                section_rows.append(finish(row, record, ids or map_ids, inline, layout_fields, id_index, storage,
                                           common, relation, relations))
        else:
            for record in range(count):
                base = offset + record * record_size
                data = raw[base:base + record_size]
                field_base = (section_first + record) * record_size - strings_start
                row = {}
                for index, field in enumerate(inline):
                    row[field.name] = inline_value(data, field, storage[index], pallet.get(index), strings, field_base)
                section_rows.append(finish(row, record, ids, inline, layout_fields, id_index, storage, common,
                                           relation, relations))
        by_id = {row["ID"]: row for row in section_rows if "ID" in row}
        for new_id, source in copies:
            if source in by_id:
                copy = dict(by_id[source])
                copy["ID"] = new_id
                section_rows.append(copy)
        rows.extend(section_rows)
    return rows


def inline_value(data, field, info, pallet, strings, field_base):
    # Bitpacked fields are read at their offset in the record; the storage
    # info's own offsets are relative to the bitpacked block.
    field_offset, field_bits, _size, kind, _a, _b, width_c = info
    if kind == 0:
        width = field_bits // field.count
        values = []
        for i in range(field.count):
            value = bits(data, field_offset + i * width, width)
            if field.kind == "string":
                position = field_base + (field_offset + i * width) // 8 + value
                values.append(cstring(strings, position)[0] if value and 0 <= position < len(strings) else "")
            elif field.kind == "float" or width == 32 or not field.signed:
                values.append(decode(field, value))
            else:
                values.append(signed(value, width))
    elif kind in (1, 5):
        value = bits(data, field_offset, field_bits)
        values = [signed(value, field_bits) if kind == 5 else decode(field, value)]
    elif kind == 2:
        values = [None]  # filled in finish(), once the id is known
    elif kind == 3:
        slot = bits(data, field_offset, field_bits)
        values = [decode(field, struct.unpack_from("<I", pallet, slot * 4)[0])]
    elif kind == 4:
        slot = bits(data, field_offset, field_bits)
        values = [decode(field, v) for v in struct.unpack_from(f"<{width_c}I", pallet, slot * width_c * 4)]
    else:
        raise ValueError(f"storage type {kind}")
    return values if field.count > 1 else values[0]


def sparse_row(raw, start, inline, storage):
    """A variable-length record: fields in order, strings inline and null-terminated."""
    row, at = {}, start
    for index, field in enumerate(inline):
        values = []
        width = max(1, storage[index][1] // field.count // 8)
        for _ in range(field.count):
            if field.kind == "string":
                value, at = cstring(raw, at)
            else:
                value = int.from_bytes(raw[at:at + width], "little")
                at += width
                value = decode(field, value) if width == 4 or field.kind == "float" else (
                    signed(value, width * 8) if field.signed else value)
            values.append(value)
        row[field.name] = values if field.count > 1 else values[0]
    return row


def finish(row, record, ids, inline, layout_fields, id_index, storage, common, relation, relations):
    row_id = ids[record] if ids else row[inline[id_index].name]
    for index, field in enumerate(inline):
        if storage[index][3] == 2:
            row[field.name] = decode(field, common[index].get(row_id, storage[index][4]))
    for field in layout_fields:
        if field.is_id:
            row[field.name] = row_id
    if relation:
        row[relation.name] = relations.get(record)
    return row
