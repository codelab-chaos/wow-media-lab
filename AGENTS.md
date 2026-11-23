# MediaLab

Work in this project folder. Do not create worktrees or alternate copies. Use SSH
for any GitHub Git remotes.

This addon targets **WoW Forever**, interface **16001**. Blizzard's UI source is
available in a local wow-ui-source checkout (`WOW_UI_SOURCE`, or
`../../hub/wow-ui-source` from this folder); inspect `origin/forever` with
`git show` / `git grep` without switching or modifying that checkout. Retail's
`live` branch is a different API baseline. Start with
`Interface/AddOns/Blizzard_APIDocumentationGenerated/` for API shapes.

WoW Media Lab is a **stand-alone, in-game addon** for browsing the game's
media: icons, textures (atlases are textures), sounds, creature models,
controls (XML templates) and fonts. Everyday players are the first audience,
addon developers the second. It is an independent project: never add code
here that depends on, or exists only for, another project.

- **No extraction here.** Reading the game (DB2 tables, CASC, the UI source,
  icon colors and vision tags) belongs to the sibling `../codex-of-azeroth`
  project (`CODEX_DIR`). MediaLab ships generated data files, committed, and
  refreshes them with `python3 scripts/sync-codex.py`, which only reads the
  codex database. Need new data? Add a table to the codex, then a row to
  `OUTPUTS` in `sync-codex.py`.
- **Data driven.** A media type is a row in `ML.Kinds` (`kinds.lua`), a
  provider in `sources.lua` and a snippet builder in `snippets.lua`. Prefer the
  client's own enumeration APIs; the generated `data/` files are the fallback.
- **Light.** `MediaLab_Icons`, `MediaLab_Models` and `MediaLab_Sounds` are load on demand; keep
  indexing batched and create frames only when needed. `MediaLabDB` holds only
  the player's lists, captured NPC names and settings.
- No Blizzard artwork or audio is bundled. Never write extracted artwork to
  the repo or the game folder.
- Plan in `sprint-hub/`.

## Checks

```sh
rg --files MediaLab tests -g '*.lua' -0 | xargs -0 -n1 luac5.1 -p
lua5.1 tests/run.lua
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 scripts/package.py
```

Releases: `python3 scripts/release.py <version> [--interface N] [--sync]`.

The Lua tests load the real TOC against a strict mock in `tests/wow.lua`; add
any new widget method there when the addon starts using it.

## Deploy after every change (the game does not read this repo)

```sh
scripts/deploy.sh            # copy MediaLab/ into the game's AddOns folder
scripts/deploy.sh --dry-run  # see what is out of date, copy nothing
```

The target is `WOW_ADDONS_DIR` or the first line of the ignored `.deploy-target`.
Never change other installed addons or saved variables. Tell the owner whether
`/reload` is enough (edits to existing files) or a client restart is needed
(new files or `.toc` changes).
