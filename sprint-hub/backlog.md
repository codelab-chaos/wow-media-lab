## MediaLab backlog (2026-11-18)

MediaLab is an independent project: an in-game media catalog plus offline
tools (catalog builder, CASC reader, icon metadata, JSON catalog). Other
projects, such as wow-addon-studio, may use its scripts and `catalog/` output,
but nothing here is built for or depends on them.

- **icon-vision-full-run** (story, running 2026-11-18): finish the
  `qwen/qwen3.5-9b` pass over all icons, then `icon-metadata.py merge`,
  deploy and commit the full `MediaLab_Icons/data.lua` and
  `catalog/icons-meta.json`. Complexity: small (waiting).
- **smoke-test-in-game** (task, owner): first run in the client: every tab,
  icon filters (Type, Subject, Color), CSV, `/mlab export` with
  `MediaLab_Export` enabled, minimize and resize, `/reload`. Complexity: small.
- **html-library** (story): `scripts/html-library.py` builds a static,
  searchable HTML reference library on the owner's machine from `catalog/`
  and `catalog/icons-meta.json`, with images extracted locally from their
  install by `casc.py` into an ignored output folder. Never published or
  committed. Done: open `index.html`, search icons by name, tag and color,
  copy IDs and snippets. Complexity: medium.
- **atlas-coords-offline** (spike): read atlas coordinates from the game files
  through CASC so atlases can be cut without a client export. Useful for the
  HTML library. Complexity: unknown.

### On hold (owner, 2026-11-18)

- ArtGallery-era preview features: inspect your own reference, Stretch, Tile
  and Border modes, tint, blend and opacity, Surprise me.
