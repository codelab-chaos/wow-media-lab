# MediaLab

Work in this project folder. Do not create worktrees or alternate copies. Use SSH
for any GitHub Git remotes.

This addon targets **WoW Forever**, interface **16001**. Blizzard's UI source is
available at `/home/chadneff/git/hub/wow-ui-source`; inspect `origin/forever` with
`git show` / `git grep` without switching or modifying that checkout. Retail's
`live` branch is a different API baseline. Start with
`Interface/AddOns/Blizzard_APIDocumentationGenerated/` for API shapes.

MediaLab covers icons, textures, atlases, sounds, control templates and
fonts. Keep it data driven: a media type
is a row in `ML.Kinds` (`kinds.lua`), a provider in `sources.lua` and a snippet
builder in `snippets.lua`. Prefer the client's own enumeration APIs; the
generated `data/` files are the fallback. Regenerate them with
`python3 scripts/build-catalog.py`. No Blizzard artwork or audio is bundled.
Keep indexing batched and create frames only when needed.

## Checks

```sh
rg --files MediaLab tests -g '*.lua' -0 | xargs -0 -n1 luac5.1 -p
lua5.1 tests/run.lua
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 scripts/package.py
```

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
