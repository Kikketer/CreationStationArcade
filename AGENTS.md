# CreationStationArcade project notes

## Hardware floor

`machine-specs.txt` is the slowest-good x86 box (captured Nov 2026):
i3-8100 + UHD 630 + 8GB, Debian 13, Chromium 156, 1280x1024. It works
but shows visual tearing at scale — treat anything at/below this as the
performance floor. Full dump in `machine-specs.txt`.

## Where games live

The repo carries **no games list** — it's machine-agnostic. On the box, all
games live in `~/arcade-games/` (overridable via `CSA_GAMES_DIR`), which sits
outside both the git checkout and the runtime folder so it survives the
boot-time `git reset --hard` + `rsync --delete` in `launcher.sh` /
`pullFromGit.sh`.

- `server.js` serves `~/arcade-games/games.json` via `/api/games` and its
  files via `/games/<file>` (falls back to a directory scan when games.json
  is missing). `menu.js` polls `/api/games` every 5s and rebuilds on change.
- `stock-games/` in the repo seeds `~/arcade-games/` at setup (only utility
  titles like Controller Test — never machine-specific content). `example-usb/`
  shows a copy-ready USB stick layout, including a full example library.
- `install/arcade-usb-update.sh` + `arcade-usb-update@.service` +
  `99-arcade-usb.rules` install games from a USB stick: loose `*.js` at the
  drive root (with same-basename `.png`/`.gif`/`.json` siblings) or an
  `arcade-games/` folder copied wholesale. Freshness is tracked per-file in
  `.usb-source-mtimes`; metadata overrides accumulate in `usb-meta.json`.
- `install/arcade-regen-games.py <dir>` rebuilds `games.json`: preserves
  existing entries and hand-edits, applies `usb-meta.json` overrides, drops
  entries for deleted files. Entries with `file: ""` are decorative tiles
  (per-machine "Your Game Here"/QR cards) and are kept at the end.
- Archiving: hidden menu gesture (B×5, hold the 5th 5s) arms a game, A
  confirms. `menu.js` calls `/api/archive-game?file=` and `server.js` moves
  the game's files to `GAMES_DIR/.archived/` then runs regen — files stay
  on disk, restore by moving them back.
- `kiosk-setup.sh` and `debian-x86-setup.sh` install the above to
  `/usr/local/sbin` + `/etc` and write `/etc/arcade-usb-update.conf`.

## Updating the MakeCode Arcade simulator

The arcade box runs the MakeCode Arcade JavaScript simulator from the `sim/` directory. The simulator version is pinned to match the version used by `MakeCodeGamesIngest` (which compiles the games) and `make-web`.

### Current pin

- `pxt-arcade` / simulator: `4.1.6`
- Source of truth for the pinned version: `scripts/sim-version.json`

### Files that make up the simulator

- `sim/cdn/blob/<hash>/pxtsim.js` — MakeCode simulator runtime (version-specific)
- `sim/cdn/blob/<hash>/sim.js` — Arcade target simulator
- `sim/cdn/blob/<hash>/sim.css` — Simulator styles
- `sim/cdn/blob/<hash>/icons.css` — Icon font
- `sim/index.html`, `sim/slim.html`, `sim/webgpu.html`, `sim/slim-webgpu.html` — CSA-specific simulator pages

`sim.js`, `sim.css`, and `icons.css` often stay byte-for-byte identical across versions, while `pxtsim.js` changes. The blob directory names are git blob hashes of the file contents.

### How to update

#### Automatic (GitHub Actions)

`.github/workflows/update-simulator.yml` runs weekly on Mondays at 06:00 UTC on the `chromium-kiosk` branch. It checks the latest `pxt-arcade` version on npm, runs the update script, and pushes the result directly back to `chromium-kiosk`.

#### Manual

1. Bump `scripts/sim-version.json` to the new version (e.g. `4.1.6`).
2. Run the update script:
   ```bash
   node scripts/update-simulator.mjs
   ```
   The script first looks for an already-downloaded simulator at `../make-web/public/simulator/<version>` and falls back to downloading it from `https://trg-arcade.userpxt.io/v<version>/---simulator`.
3. The script copies the blob files into `sim/cdn/blob/`, updates the `<script>` and `<link>` references in the four `sim/*.html` files, updates the fallback `targetVersion` in `public/play.html`, writes the new version to `scripts/sim-version.json`, and removes unreferenced old blob directories.
4. Verify by starting the server and loading a game:
   ```bash
   node server.js
   # open http://localhost:3000/play?game=<name>
   ```

### Game compatibility

- Games with `targetVersion: 4.1.6` in their `// meta=` header are built for this simulator.
- Older games (e.g. `targetVersion: 4.0.14` or `4.1.2`) may still run, but should be recompiled through `MakeCodeGamesIngest` or `make-web` to guarantee compatibility.

### Related projects

- `~/Projects/MakeCodeGamesIngest` — compiles PNGs to `game.js` files using `pxt-arcade` and `pxt-core`.
- `~/Projects/make-web` — hosts the same simulator files under `public/simulator/<version>`.
