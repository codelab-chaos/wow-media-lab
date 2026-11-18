# WoW addon emulator: idea notes

Status: **for discussion**. Nothing here is built yet. Written 2026-11-18.

## The idea

Run an addon's XML and Lua outside the game, as if WoW hosted it, and render
its frames in a browser. Then we (and LLM agents) can view, debug and automate
addon UI without editing, deploying and `/reload`ing inside the client for
every change.

Two things we built for MediaLab make this more realistic than it sounds:

1. **We can read the user's own game files.** `scripts/casc.py` opens the local
   CASC storage and pulls any file by ID: textures, icons, fonts, the
   Blizzard UI's own XML and Lua. An emulator could render real artwork, from
   the user's install, without us shipping any of it.
2. **We already emulate the API, a little.** `tests/wow.lua` is a strict mock
   of exactly the widget methods and APIs MediaLab uses, with anchor
   resolution. It runs the real addon headless. An emulator is that mock,
   grown up, plus a renderer.

## Why it could accelerate us

- **Iteration speed.** Edit, refresh a browser tab, see it. No deploy, no
  client restart for new files.
- **LLM tooling works on the web.** Agents can screenshot, inspect a DOM,
  click with Playwright, diff images, read console errors. Inside WoW we get
  none of that; we get the owner's screenshots.
- **Repeatable states.** Scripted events ("player enters combat", "bag
  update", "auction results arrive") replayed exactly, instead of waiting for
  them in game.
- **Visual regression tests.** Golden screenshots per addon per state, run
  in CI.
- **One harness for every addon** in the workspace (Auction Hero, Quest Party,
  MediaLab...) instead of one hand-rolled mock each.

## What exists already

- **[wowless](https://github.com/wowless/wowless)**: "a headless WoW client
  Lua and FrameXML interpreter, intended for addon testing." Active (pushed
  two days ago), Lua, built on **elune**, a taint-aware Lua 5.1 fork. It loads
  Blizzard's FrameXML and an addon, then clicks and mouses over things. Its
  README says it is pre-alpha, that errors are probably its own, that
  development is Docker only, and it targets the retail client. **No
  rendering.** License is not stated in the repo metadata (needs checking).
- **[WoWBench](https://wowinterface.com/downloads/info5095-WoWBench.html)**
  ([SourceForge](https://sourceforge.net/projects/wowbench/)): a pure-Lua
  API emulator with an XML parser, from 2006 (client 1.12). Console only, no
  GUI. Historical interest.
- **[Wowser](https://awesome.ecosyste.ms/projects/github.com%2Fwowserhq%2Fclient)**:
  the game world in a browser via WebGL. A different goal; not addon UI.
- **Editor tooling** (API annotations for VS Code and similar): static types
  and completion, no runtime.

Nobody renders addon frames in a browser, as far as a quick search shows.
That gap is the interesting part.

## Two ways to build it

**A. Build on wowless.** Use it as the runtime (Lua, XML, API surface), and
add what it lacks: a frame-tree export plus a browser renderer, Forever
(16001) support, and asset loading through our CASC reader.

- For: years of API and FrameXML work already done; taint-aware Lua.
- Against: pre-alpha, Docker-only, retail-targeted, unclear license, and a
  third party's roadmap. Upstreaming a renderer may not fit their goals.

**B. Grow our own, "only what we need".** Start from `tests/wow.lua`: run our
addons' real TOC and files, implement each API when an addon first calls it
(strict, so a missing API fails loudly and becomes the next task), and render
the resulting frame tree.

- For: small, ours, matches the incremental way we already work; every addon
  we write adds coverage. The generated API docs in
  `Blizzard_APIDocumentationGenerated` give exact signatures to stub from.
- Against: we will rebuild things wowless already has, and fidelity to the
  real layout engine is our problem.

A middle path: **B now, borrowing ideas and tests from wowless**, and revisit
using it as the runtime once it is less alpha.

## Rough architecture

```
addon folder ──► loader (TOC order, XML -> frames, Lua in addon env)
                     │
                     ▼
               runtime: Lua 5.1 (lua5.1, or Fengari/wasmoon in the browser)
               widget objects (Frame, Button, Texture, FontString, ...)
               API stubs: C_* namespaces, events, timers, CVars, saved variables
                     │
                     ▼
               layout: resolve anchors, sizes, scale, strata and levels
                     │
                     ▼
               renderer: browser DOM/canvas, one element per region,
               textures from a local asset server backed by casc.py
                     │
                     ▼
               control: event injector, scripted scenarios, screenshot API,
               an MCP server so agents can drive it
```

Notes on the hard parts:

- **Events.** We do not replicate the game. We replicate *the events an
  addon registers for*, with payloads we script ("scenarios"), the same way
  our mock fakes `ADDON_LOADED`. Recording real payloads in game with a small
  logger addon, then replaying them, gives realistic data cheaply.
- **Layout fidelity.** Anchors and sizes are well understood (our mock
  already resolves them). Fonts, text wrapping, nine-slice borders, texture
  coordinates and atlas slicing need care. Pixel-perfect is not the goal;
  "close enough to judge layout" is.
- **Blizzard UI.** Most addons lean on Blizzard templates (`UIPanelButtonTemplate`,
  `BackdropTemplate`, mixins). Loading parts of FrameXML from the UI source
  checkout we already have is how wowless does it; we could load just the
  shared templates.
- **Secure code and taint.** Out of scope at first. Combat lockdown can be a
  flag, like `InCombatLockdown` in our mock.
- **Lua in the browser.** Either run Lua 5.1 server side and stream the frame
  tree, or run it in the page with a JS/WASM Lua. Server side is simpler and
  keeps agent tooling on our side.

## Assets and the "metabase"

The metadata pipeline (names, colors, tags) has a property worth building on:
**a file ID's content in a given build never changes.** Once an icon is
described, that record is done. Keyed by file ID (and the content hash from
CASC), the knowledge base only ever grows: each patch adds new IDs and the
rest is reused. The same holds for an emulator's asset cache: decode a
texture once per content hash, forever.

Licensing line, for both projects: artwork and audio are read from the
**user's own install** and served **locally**. We ship code and derived facts
(names, sizes, colors, tags), never Blizzard files.

## Same project or separate?

Recommendation: **a separate project** (`wow-addon-emu`), with shared pieces
extracted so both use them:

- `casc.py` and the icon metadata pipeline become a small shared library
  (or a third repo) that MediaLab and the emulator both depend on.
- MediaLab stays an in-game addon. The emulator is a dev tool that *runs*
  MediaLab (and every other addon) as one of its first test subjects. MediaLab
  is a perfect first target: it touches textures, atlases, fonts, sounds and
  templates, and we already have its mock.

They help each other: MediaLab's catalog tells the emulator what assets
exist; the emulator gives MediaLab (and every addon) screenshots and tests.

## Related: an HTML reference library

A smaller, nearer idea from the same conversation: ship a tool that builds a
**static HTML reference library** of the media lab on the user's machine:

- every icon, texture and atlas with its name, ID, colors, tags and snippets,
  searchable and filterable in a browser;
- images extracted from the **user's own install** by `casc.py` into a local
  folder next to the HTML; nothing Blizzard-owned is shipped or published;
- built from `catalog/*.json` and `catalog/icons-meta.json`, so it needs no
  game running.

This is useful on its own, is mostly done (the data exists), and doubles as
the emulator's first asset server and browser UI. A good stepping stone.

## A possible first milestone

Small enough to finish, big enough to judge the idea:

1. Load MediaLab's TOC outside the game with a grown-up version of
   `tests/wow.lua` (shared, not per addon).
2. Dump the frame tree (positions, sizes, textures, text) as JSON after
   opening the lab.
3. Render that JSON in a browser page with real icons from the local asset
   server.
4. Screenshot it with Playwright and compare against an in-game screenshot.

If step 4 looks recognizably like the game, the approach works.

## Open questions

- Build on wowless, or grow our own (or our own now, wowless later)?
- Which addon is the first real customer: MediaLab (best mock today), or
  Auction Hero (most UI, already has an HTML version to compare against)?
- Server-side Lua with a streamed frame tree, or Lua in the browser?
- How much Blizzard FrameXML do we load: none, shared templates only, or all?
- Do we record real event payloads in game for scenarios, or hand-write them?
- Where do shared pieces live (`casc.py`, the metadata pipeline)?
