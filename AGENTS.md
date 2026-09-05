# CreationStationArcade project notes

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

1. Bump `scripts/sim-version.json` to the new version (e.g. `4.1.6`).
2. Run the update script:
   ```bash
   node scripts/update-simulator.mjs
   ```
   The script first looks for an already-downloaded simulator at `../make-web/public/simulator/<version>` and falls back to downloading it from `https://trg-arcade.userpxt.io/v<version>/---simulator`.
3. The script copies the blob files into `sim/cdn/blob/`, updates the `<script>` and `<link>` references in the four `sim/*.html` files, updates the fallback `targetVersion` in `public/play.html`, and removes unreferenced old blob directories.
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
