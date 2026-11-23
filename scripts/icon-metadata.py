#!/usr/bin/env python3
"""Build icon metadata from the local game files: names, colors, descriptions, tags.

Stages (each cached under .cache/icons/ and resumable):

    names    community listfile -> file ID and name for every interface/icons file
    colors   decode each icon from the local CASC store and measure its colors
    vision   ask a local vision model (LM Studio) for a description, subject and tags
    merge    write catalog/icons-meta.json and the MediaLab_Icons addon data

    .venv/bin/python scripts/icon-metadata.py names colors merge
    .venv/bin/python scripts/icon-metadata.py vision --limit 200 --workers 2
    .venv/bin/python scripts/icon-metadata.py all

Colors and vision need Pillow (.venv). Vision needs LM Studio's server with
"Serve on Local Network" on. No artwork is written anywhere; only derived facts.
"""

import argparse
import base64
import colorsys
import io
import json
import math
import os
import re
import struct
import sys
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".cache" / "icons"
LISTFILE = ROOT / ".cache" / "community-listfile.csv"
LISTFILE_URL = "https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv"
ADDON = ROOT / "MediaLab_Icons"
JSON_OUT = ROOT / "catalog" / "icons-meta.json"

# Hue ranges in degrees (upper bound, name); low saturation or extreme lightness is gray.
HUES = [(15, "red"), (40, "orange"), (65, "gold"), (160, "green"), (195, "teal"),
        (255, "blue"), (290, "purple"), (335, "pink"), (360, "red")]
# Dark, warm pixels read as brown rather than orange or red.
BROWN = {"hues": (10, 50), "max_light": 0.34}
GRAY_SATURATION = 0.18
COLOR_WORDS = {name for _, name in HUES} | {"gray", "grey", "black", "white", "yellow", "golden", "brown",
                                             "silver", "violet", "magenta", "dark", "light", "bright", "colorful"}
SUBJECTS = ["weapon", "armor", "jewelry", "consumable", "food", "currency", "material", "tool", "container",
            "object", "creature", "character", "spell", "ability", "symbol", "nature", "building", "mount", "pet"]
FILLER = {"icon", "ui", "wow", "world of warcraft", "warcraft", "item", "image", "game", "symbol", "graphic"}

PROMPT = """This is a World of Warcraft icon (shown enlarged). Its file name is "{name}"; use it as a hint, \
it is often abbreviated (inv = inventory item, wod = Warlords of Draenor). Describe only what is visible.
Return JSON:
- description: one sentence, at most 18 words, of what the icon shows.
- subject: one of {subjects}.
- tags: 5 to 8 lowercase search words someone would type to find it: the concrete thing \
(ring, potion, sword, shoulder, eye) and its likely game use (stealth, healing, engineering, fire). \
No color words. Never use: icon, ui, wow, world of warcraft, item, image."""


def read_jsonl(path):
    rows = {}
    if path.is_file():
        for line in path.read_text().splitlines():
            if line.strip():
                row = json.loads(line)
                rows[row["id"]] = row
    return rows


class Appender:
    """Thread-safe JSONL appender so long runs can stop and resume."""

    def __init__(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.handle, self.lock = open(path, "a"), threading.Lock()

    def write(self, row):
        with self.lock:
            self.handle.write(json.dumps(row) + "\n")
            self.handle.flush()


def open_store():
    sys.path.insert(0, str(ROOT / "scripts"))
    from casc import Casc, game_root
    return Casc(game_root(ROOT))


def load_names():
    path = CACHE / "names.json"
    if not path.is_file():
        sys.exit("Run the names stage first.")
    return {int(k): v for k, v in json.loads(path.read_text()).items()}


# ---------------------------------------------------------------------------
def stage_names(args):
    if not LISTFILE.is_file() or args.refresh_listfile:
        print(f"downloading {LISTFILE_URL}")
        LISTFILE.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(LISTFILE_URL, LISTFILE)
    pattern = re.compile(r"^(\d+);interface/icons/([^/]+)\.blp$", re.I)
    names = {}
    for line in LISTFILE.read_text(errors="replace").splitlines():
        match = pattern.match(line)
        if match:
            names[int(match.group(1))] = match.group(2).lower()
    store = open_store()
    present = {fdid: name for fdid, name in names.items() if fdid in store.files}
    CACHE.mkdir(parents=True, exist_ok=True)
    (CACHE / "names.json").write_text(json.dumps(present, sort_keys=True))
    print(f"names: {len(names):,} icon paths in the listfile, {len(present):,} in this client")


# ---------------------------------------------------------------------------
def hue_name(hue):
    return next(name for limit, name in HUES if hue * 360 < limit)


def analyze(image):
    """Colors of an icon's inner area, ignoring its frame and near-black pixels."""
    from PIL import Image
    rgba = image.convert("RGBA")
    w, h = rgba.size
    inner = rgba.crop((w // 10, h // 10, w - w // 10, h - h // 10)).resize((24, 24), Image.BILINEAR)
    kept, counts, x, y = [], {}, 0.0, 0.0
    for r, g, b, a in inner.get_flattened_data():
        if a < 128:
            continue
        hue, light, sat = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        if light < 0.12:
            continue
        kept.append((r, g, b))
        degrees = hue * 360
        if sat < GRAY_SATURATION or light > 0.92:
            name = "gray"
        elif BROWN["hues"][0] <= degrees < BROWN["hues"][1] and light < BROWN["max_light"]:
            name = "brown"
        else:
            name = hue_name(hue)
        counts[name] = counts.get(name, 0) + 1
        if name not in ("gray", "brown"):
            x += math.cos(hue * 2 * math.pi) * sat
            y += math.sin(hue * 2 * math.pi) * sat
    total = max(1, len(kept))
    ranked = sorted(counts.items(), key=lambda kv: -kv[1])
    colors = [name for name, count in ranked if count / total >= 0.15][:2] or [ranked[0][0] if ranked else "gray"]
    alpha = any(p[3] < 250 for p in rgba.get_flattened_data())
    return {
        "size": [w, h], "alpha": alpha, "colors": colors,
        "hue": round(math.degrees(math.atan2(y, x)) % 360) if (x or y) else None,
        "brightness": round(sum(0.299 * r + 0.587 * g + 0.114 * b for r, g, b in kept) / total / 255, 2),
    }


def decode(store, fdid):
    from PIL import Image
    raw = store.read(fdid)
    if raw[:4] == b"BLP2" and raw[8] == 3:
        # Uncompressed BGRA, which Pillow does not read: take mip level 0 directly.
        width, height = struct.unpack_from("<II", raw, 12)
        offset, length = struct.unpack_from("<I", raw, 20)[0], struct.unpack_from("<I", raw, 84)[0]
        return Image.frombytes("RGBA", (width, height), raw[offset:offset + length], "raw", "BGRA")
    image = Image.open(io.BytesIO(raw))
    image.load()
    return image


def stage_colors(args):
    names, store = load_names(), open_store()
    path = CACHE / "colors.jsonl"
    done = read_jsonl(path)
    todo = [fdid for fdid in sorted(names) if fdid not in done][:args.limit or None]
    out, failures, start = Appender(path), 0, time.time()
    for index, fdid in enumerate(todo, 1):
        try:
            row = {"id": fdid, **analyze(decode(store, fdid))}
        except Exception as error:
            row, failures = {"id": fdid, "error": f"{type(error).__name__}: {error}"[:200]}, failures + 1
        out.write(row)
        if index % 2000 == 0:
            print(f"colors: {index:,}/{len(todo):,} ({time.time() - start:.0f}s)", flush=True)
    print(f"colors: {len(todo):,} measured, {failures:,} unreadable, {len(done) + len(todo):,} cached")


# ---------------------------------------------------------------------------
SCHEMA = {"type": "json_schema", "json_schema": {"name": "icon", "strict": True, "schema": {
    "type": "object", "additionalProperties": False, "required": ["description", "subject", "tags"],
    "properties": {
        "description": {"type": "string"},
        "subject": {"type": "string", "enum": SUBJECTS},
        "tags": {"type": "array", "items": {"type": "string"}},
    }}}}


def clean_tags(tags, name):
    result = []
    for tag in tags:
        tag = re.sub(r"\s+", " ", str(tag).lower().strip(" .,;-"))
        if not tag or tag in FILLER or tag in COLOR_WORDS or tag in result or len(tag) > 24:
            continue
        result.append(tag)
    return result[:8]


def ask(args, store, fdid, name):
    from PIL import Image
    buffer = io.BytesIO()
    decode(store, fdid).convert("RGB").resize((256, 256), Image.LANCZOS).save(buffer, "PNG")
    prompt = PROMPT.format(name=name, subjects=", ".join(SUBJECTS))
    body = {"model": args.model, "temperature": 0.2, "max_tokens": 300, "response_format": SCHEMA,
            "messages": [{"role": "user", "content": [
                {"type": "text", "text": prompt},
                {"type": "image_url", "image_url": {
                    "url": "data:image/png;base64," + base64.b64encode(buffer.getvalue()).decode()}}]}]}
    request = urllib.request.Request(args.url.rstrip("/") + "/chat/completions", json.dumps(body).encode(),
                                     {"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=300) as response:
        text = json.load(response)["choices"][0]["message"]["content"]
    data = json.loads(text[text.find("{"):text.rfind("}") + 1])
    return {"id": fdid, "model": args.model, "description": str(data["description"]).strip(),
            "subject": data["subject"] if data["subject"] in SUBJECTS else "object",
            "tags": clean_tags(data.get("tags", []), name)}


def stage_vision(args):
    names, store = load_names(), open_store()
    colors = read_jsonl(CACHE / "colors.jsonl")
    path = CACHE / "vision.jsonl"
    done = read_jsonl(path)
    readable = [fdid for fdid in sorted(names) if fdid not in done and "error" not in colors.get(fdid, {})]
    todo = readable[:args.limit or None]
    out, failures, start = Appender(path), 0, time.time()
    print(f"vision: {len(todo):,} icons with {args.model} ({args.workers} workers)", flush=True)
    with ThreadPoolExecutor(args.workers) as pool:
        futures = {pool.submit(ask, args, store, fdid, names[fdid]): fdid for fdid in todo}
        for index, future in enumerate(as_completed(futures), 1):
            try:
                out.write(future.result())
            except Exception as error:
                failures += 1
                print(f"vision: {futures[future]} failed: {type(error).__name__}: {str(error)[:120]}", flush=True)
            if index % 100 == 0:
                rate = (time.time() - start) / index
                print(f"vision: {index:,}/{len(todo):,} ({rate:.2f}s/icon, "
                      f"~{rate * (len(todo) - index) / 3600:.1f}h left)", flush=True)
    print(f"vision: {len(todo) - failures:,} described, {failures:,} failed, "
          f"{len(done) + len(todo) - failures:,} cached")


# ---------------------------------------------------------------------------
def category(name):
    """The first word of a Blizzard icon name: inv, spell, ability, achievement, trade..."""
    return name.split("_", 1)[0] if "_" in name else "other"


def lua_string(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def stage_merge(args):
    names = load_names()
    colors = read_jsonl(CACHE / "colors.jsonl")
    vision = read_jsonl(CACHE / "vision.jsonl")
    items = []
    for fdid in sorted(names):
        color = colors.get(fdid, {})
        if "error" in color:
            continue
        seen = vision.get(fdid, {})
        items.append({
            "id": fdid, "name": names[fdid], "category": category(names[fdid]),
            "colors": color.get("colors", []), "hue": color.get("hue"), "brightness": color.get("brightness"),
            "alpha": color.get("alpha"), "size": color.get("size"),
            "subject": seen.get("subject"), "description": seen.get("description"), "tags": seen.get("tags", []),
        })
    described = sum(1 for item in items if item["description"])
    JSON_OUT.parent.mkdir(parents=True, exist_ok=True)
    header = json.dumps({
        "kind": "icons-meta",
        "source": {"names": "wowdev/wow-listfile", "colors": "local CASC pixels",
                   "vision": sorted({row.get("model") for row in vision.values()} - {None})},
        "count": len(items), "described": described,
    })[:-1]
    # One compact item per line keeps the file small and its git diffs readable.
    body = ",\n".join(json.dumps(item, separators=(",", ":")) for item in items)
    JSON_OUT.write_text(f'{header}, "items": [\n{body}\n]}}\n')

    # Addon data: one tab-separated string per icon keeps memory low; MediaLab
    # splits it only when indexing. Fields: name, colors, subject, tags, description.
    lines = ["-- Generated by scripts/icon-metadata.py. Derived facts only; no artwork.",
             "MediaLabIconMeta = {"]
    for item in items:
        fields = [item["name"], ",".join(item["colors"]), item["subject"] or "",
                  ",".join(item["tags"]), item["description"] or ""]
        lines.append(f"[{item['id']}]={lua_string(chr(9).join(fields))},")
    lines.append("}")
    ADDON.mkdir(exist_ok=True)
    (ADDON / "data.lua").write_text("\n".join(lines) + "\n")
    size = (ADDON / "data.lua").stat().st_size
    print(f"merge: {len(items):,} icons, {described:,} described -> {JSON_OUT.relative_to(ROOT)}, "
          f"{(ADDON / 'data.lua').relative_to(ROOT)} ({size / 1e6:.1f} MB)")


STAGES = {"names": stage_names, "colors": stage_colors, "vision": stage_vision, "merge": stage_merge}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("stages", nargs="+", choices=[*STAGES, "all"])
    parser.add_argument("--limit", type=int, default=0, help="process at most N new icons per stage")
    parser.add_argument("--model", default="qwen/qwen3.5-9b")
    parser.add_argument("--url", default=os.environ.get("LMSTUDIO_URL", "http://172.20.16.1:1234/v1"))
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--refresh-listfile", action="store_true")
    args = parser.parse_args()
    for stage in (list(STAGES) if "all" in args.stages else args.stages):
        STAGES[stage](args)
