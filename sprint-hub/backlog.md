## WoW Media Lab backlog (2026-11-23)

WoW Media Lab is a stand-alone, player-first addon. Reading the game (data
tables, CASC, the UI source, icon metadata) belongs to the Codex of Azeroth;
the lab ships data synced from it (`scripts/sync-codex.py`).

- **smoke-test-in-game** (task, owner): the checklist in
  `docs/development.md`: welcome card, every tab, Textures' Files and
  Atlases, Dev mode (code fields, Fonts, Copy), the column splitters,
  Target on a real NPC, `/reload`. Complexity: small.
- **share-first-release** (task, owner to decide): GitHub release and/or
  CurseForge, with screenshots or a GIF in the README. Git history stays as
  is (measured 2026-11-23: 5.5 MB, the old scripts are a few kB).
- **list-reader** (story, low priority): a `tools/` folder of downloadable,
  read-only, at-your-own-risk tools, starting with one HTML file that opens a
  player's `SavedVariables/MediaLab.lua` and shows their lists as a plain
  reference (kind, name, ID), offline. Packaged as its own
  `MediaLab-tools-<version>.zip`. Complexity: small.
- **model-details** (idea, later): tell same-named models apart. Measured
  2026-11-23: 13,118 displays share 907 names; size and transparency, all
  skins, and humanoid NPCs' class and outfit leave about 1,100 identical. Most
  NPC-to-display links are server side (574 of 14,192 displays are named in
  the client: mounts, forms, player models), so names would come from the
  codex's passive NPC recording. Needs the codex first (its backlog).
  Complexity: medium.

- **zip4d-motion** (proposal, owner to decide): bring zip4d's container
  conventions (`../../codelab/zip4d/docs/vision.md`) to the lab, as behavior
  rather than code (zip4d is TypeScript): momentum scrolling with exponential
  decay and a settle rule, pixel-smooth row offsets, scrollbar release
  carrying velocity, Ctrl+wheel for continuous thumbnail zoom that scales
  cells around their centers then settles, and preview zoom anchored on the
  pointer. A **Motion** setting keeps an instant option. Complexity: medium.

### On hold (owner, 2026-11-18)

- ArtGallery-era preview features: inspect your own reference, Stretch, Tile
  and Border modes, tint, blend and opacity, Surprise me.
