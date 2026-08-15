# BVC

**Unofficial. Free. No permission required.**

A from-scratch rework of the `badvape-v2` runtime with every license wall
ripped out. No credential. No LuaProt key. No auth server. No sealed
artifacts. Execute and go.

## Load

```lua
loadstring(game:HttpGet('https://raw.githubusercontent.com/ezbrohack/bvc-v2/main/bootstrap.lua'))()
```

Or, if `init.lua` is already installed locally:

```lua
loadstring(game:HttpGet('https://raw.githubusercontent.com/ezbrohack/bvc-v2/main/init.lua'))()
```

## What changed

- `bootstrap.lua` and the `.github` loader: credential gate removed — they
  never ask for a key.
- `main.lua`: LuaProt routing, product keys, and auth staging deleted.
- `init.lua`: `forwardedLuaProtSecret` gone; `credentialKind` is always `free`.
- Rivals module, redirects, dependencies, and `luaprot-*` libraries removed.
- The protected FloodCraft artifact was replaced with the free module.
- Cloud config API neutralized (offline/localhost).
- Everything rebranded to **BVC**.

## How it works

1. `bootstrap.lua` fetches `init.lua` from `main`.
2. `init.lua` resolves the latest commit SHA, downloads
   `public-manifest.json`, validates every file (SHA-256 over LF-normalized
   content), and installs only the listed public paths.
3. `os.luau` boots `main.lua`, which loads the universal/base modules, then
   the game module matching the current place.
4. Cached runs reuse validated files; only missing or changed files are
   repaired.

User profiles are never overwritten. Diagnostics live at
`workspace/bvc/bvc-debug.txt`.

## Game routing

- FloodCraft (`6872274481`, `8444591321`, `8560631822`) →
  `games/6872274481.lua`
- Everything else → `games/<place>.lua`

## Status

Unofficial fork. Not affiliated with the upstream project. Free forever.
