# Migrating Creation Station Arcade to the MakeCode Simulator

## Why This Document Exists

The current ELF-based approach has reached a dead end:

- **Hardware lock-in**: The `hw---rpi-raw-elf` target only runs on Pi 3 due to the `Hardware:` line in `/proc/cpuinfo`. Pi 4 and Pi 5 kernels have removed that line and `wiringPi` is dead on Pi 5. Once the Pi 3 kernel updates, it will also stop working.
- **Memory constraints**: The native ARM ELF binary has tight memory limits that prevent complex games from running.
- **No extension support**: Community extensions (raytracing, advanced graphics, etc.) don't compile to the ELF target. Kids can build things in the editor that simply cannot run on the arcade box.
- **1:1 fidelity gap**: What kids see in the browser simulator is not what plays on the machine.

The proposed replacement runs the **same JavaScript simulator that powers `arcade.makecode.com`** locally on the Pi, achieving perfect fidelity and removing hardware constraints.

---

## Two Paths Forward

There are two approaches to running the JS simulator on the arcade machine:

### Option 1: Electrobun Shell ("Real Apps")

Each game is wrapped in an Electrobun application (similar to Electron) and launched as a separate process. The menu could remain an ELF file or also become an Electrobun app.

**How it works:**
```
[MadeArcadeMenu.elf] → forks → [Electrobun: Gelb.js]
                       → forks → [Electrobun: Vikings.js]
```

**Advantages:**
- "Real" applications that can be started and killed individually
- 1:1 mapping with current ELF architecture — `monitor_kill.py` kills the process, returns to menu
- Process isolation: one game crash doesn't affect others or the menu

**Disadvantages:**
- Slower launch times (each Electrobun app must spin up its own Chromium instance)
- Uncertain if Electrobun works outside a desktop environment (current setup boots straight to the menu with no desktop)
- Losing the "boot to arcade" feel — becomes "an app running inside a desktop"
- More complex deployment: each game is a bundled app, not a simple JS file
- Heavier resource usage: multiple Chromium processes vs. one shared instance

---

### Option 2: Single Chromium Kiosk (SPA Navigation)

One Chromium window in kiosk mode hosts everything: a web-based menu carousel and simulator-based games via SPA navigation.

**How it works:**
```
[chromium --kiosk]
  └── http://localhost:3000/           ← web carousel (game selection)
  └── http://localhost:3000/play?g=Gelb  ← simulator page (switches games without reload)
```

**Advantages:**
- Fast game switching — no process spawn overhead, just JS context swap
- Simpler deployment: games are plain `.js` files, menu is HTML/CSS/JS
- Proven at `~/Projects/makecode-desktop` — we know the simulator works in a webview
- Runs without desktop environment — can still boot straight to kiosk
- Freedom to build the menu in any web tech (not constrained to MakeCode blocks)
- Works on Pi 3/4/5 — no hardware lock-in

**Disadvantages:**
- Single point of failure: browser freeze bricks the whole system (mitigation: `monitor_kill.py` hard-restarts Chromium)
- Need GPIO → HID bridge to translate Pi pin inputs to USB-style gamepad events
- "Just a web page" feel — though streamlined boot can minimize this

---

## Decision: Option 2 (Single Chromium Kiosk)

**Rationale:**

1. **The "real app" feel is an illusion anyway.** The current ELF menu is itself a compiled game — it's not "real" in the sense of a native OS shell. The boot-to-kiosk experience can feel just as seamless if we hide the boot sequence.

2. **Resource constraints on Pi 3.** Launching multiple Electrobun instances (each with Chromium) on a Pi 3 will be painful. One shared Chromium instance with iframe/simulator switching is far lighter.

3. **Deployment simplicity.** Committing a 5KB `.js` file vs. a 100MB+ Electrobun bundle per game is a massive win. Kids can PR new games easily.

4. **Proven path.** `make-web` proves we can compile JS games. `makecode-desktop` proves we can run them in a shell. Kiosk mode is the simplest extension of this.

### POCs → CreationStationArcade

**`make-web` and `makecode-desktop` are proof-of-concepts only.** They will not be called or used directly by `CreationStationArcade`. Instead, the working code from these POCs will be **copied and adapted** into the `CreationStationArcade` repository:

- `make-web/apps/compile-service/` → standalone compile service running **on the Pi** (no network calls)
- `make-web/app/twominute/` → simulator player (strip to just game, no timer/NES)
- `make-web/public/sim/` → simulator runtime files
- `makecode-desktop` → Electrobun approach documented but **not used**

The rest of this document details the implementation of **Option 2** in `CreationStationArcade`.

---

## How the Current System Works

Understanding what we're replacing:

```
[Git repo: CreationStationArcade]
  └── games/*.elf         ← pre-compiled ARM binaries (one per game)
  └── MadeArcadeMenu.elf  ← game selection UI, also an ELF
  └── launcher.sh         ← pi user's login shell
  └── simpleLaunch.sh     ← forks the ELF, watches for exit, restores framebuffer
  └── monitor_kill.py     ← GPIO: Kill button (BCM 3) + 2-min inactivity → return to menu
  └── arcade.cfg          ← GPIO pin map for all 4 players (BTN_A through BTN_DOWN4)
```

**Boot flow:**
1. Pi boots → `pi` user logs in → `launcher.sh` is the login shell
2. `launcher.sh` rsyncs `*-src` → runtime dir, kicks off `pullFromGit.sh` in background
3. Syncs `games/` to `/sd/prj` if that folder exists
4. Starts `monitor_kill.py` (GPIO watcher) in background
5. Launches `MadeArcadeMenu.elf` via `simpleLaunch.sh`
6. `MadeArcadeMenu.elf` (a MakeCode Arcade game built as an ELF) is the game picker UI — player picks a game, the menu ELF kills itself and launches the chosen game's ELF
7. When a game exits, `simpleLaunch.sh` restores the framebuffer and launcher.sh exits (login shell exits → auto-restarts, looping back to step 2)

**How games are built today (transitioning to JS):**
- Old way: use `?compile=rawELF&hw=rpi` to build `.elf` binaries (deprecated, Pi 3 only)
- New way: use `make-web` desktop compiler to build `.js` files that work on any Pi

**Where the compiled game files come from:**
- `make-web` (this repo) has a working PNG → JS compiler at `/desktop`
- Upload a `.png` from MakeCode Arcade editor → download `[projectname].js`
- The JS compile happens entirely in-process via `pxt-core` (no Docker, no ARM compiler)
- Drop the `.js` file into `CreationStationArcade/games/` and commit

---

## The Proposed Replacement Architecture

Compile to the **JS/VM target** (`hw---vm`) and run inside the MakeCode Arcade browser simulator, hosted locally on the Pi. Games are pure JavaScript files (`[gamename].js`), not binaries.

```
[Git repo: CreationStationArcade]
  └── games/*.js          ← compiled JS bundles (e.g., `Gelb.js`, `Vikings.js`)
  └── launcher.sh         ← same pattern, but launches Chromium instead of ELF
  └── monitor_kill.py     ← same GPIO logic, but kills Chromium instead of ELFs
  └── arcade.cfg          ← same GPIO pin map (still used for inactivity timer)
  └── sim/                ← local copy of the MakeCode Arcade simulator JS
  └── public/
      └── index.html      ← game selection carousel (replaces MadeArcadeMenu.elf)
      └── play.html       ← fullscreen simulator page, loads a chosen game's JS
```

**New boot flow:**
1. Pi boots → `pi` user logs in → `launcher.sh` is still the login shell
2. Same sync/git-pull logic runs
3. `launcher.sh` starts a small local HTTP server (e.g., `node server.js` or `python3 -m http.server`)
4. Launches `chromium-browser --kiosk --noerrdialogs http://localhost:3000` 
5. Chromium loads the game carousel (`index.html`), player picks a game
6. Chromium navigates to `play.html?game=gameName`, which loads the simulator with that game's JS bundle
7. Kill button / inactivity: `monitor_kill.py` sends `pkill chromium` or navigates back to carousel via a local HTTP endpoint

**Key properties:**
- **Parity with editor**: the JS VM target is identical to what runs in the browser simulator on `arcade.makecode.com` — all extensions work
- **No hardware constraints**: V8 on RPi 3 has access to all available RAM
- **4-player input**: Chromium's Gamepad API or keyboard mapping handles all 4 controller inputs — `arcade.cfg` pin map would need translation to either USB HID or a small bridge daemon
- **Offline**: once `sim/` is populated with the simulator JS files, zero internet required
- **Upgradeability**: works on Pi 3, Pi 4, Pi 5, or any device that runs a browser — no kernel version dependency

---

## How Games Would Be Built (New Flow)

This is where `pxt-root/png-to-elf` comes in, but targeting `hw---vm` instead of `hw---rpi-raw-elf`.

### The Compile Change

In `png-to-elf/src/server.ts` (or compile pipeline), the hardware variant passed to the PXT compiler changes from:

```
hw=rpi-raw-elf   (produces binary.elf via Docker pext/rpi:alsa)
```

to:

```
hw=vm            (produces a JavaScript bundle — no Docker, no ARM compiler needed)
```

The `hw---vm` target compiles the game TypeScript to a self-contained JS file that can be loaded into the MakeCode simulator runtime. This compile happens entirely in-process via `pxt-core` — proven in `make-web/app/api/compile-js/route.ts`.

### Output Format

The output is a `.js` file named after the project (e.g., `Gelb.js`). This gets committed to `CreationStationArcade/games/`.

### Build Flow (as implemented in `make-web`)

```
User uploads game.png to /desktop
  → server decodes PNG → extracts project source (TypeScript files)
  → PXT compiler runs with hw=vm variant via pxt-core
  → outputs [projectname].js (JS bundle for simulator)
  → downloads [projectname].js to user
  → user commits [projectname].js to CreationStationArcade/games/
```

No Docker. No ARM cross-compiler. No Microsoft compile service dependency. Runs entirely in Node.js via `pxt-core` — proven in `make-web/app/api/compile-js/route.ts`.

---

## What Needs to Be Built

### 1. Build Pipeline — On-Pi Compilation (no network)

**Based on:** `make-web/apps/compile-service/`

This is a **standalone Node.js service** that runs directly on the Raspberry Pi. It compiles PNG files to JS entirely locally using `pxt-core` — no Docker, no Microsoft compile service, no network calls.

**Components to copy from `make-web/apps/compile-service/`:**
- `src/js-compile.ts` — PXT compiler logic (PNG → `[projectname].js`)
- `src/server.ts` — HTTP server (Express/Fastify) with endpoints:
  - `POST /api/compile-js` — accepts PNG, returns JS
  - `GET /api/games` — list available games
- `pxt/target.js` — copied from `make-web` (required for hw---vm compilation)
- `package.json` — dependencies: `pxt-core`, `pxt-arcade`, etc.

**User workflow:**
```
1. Drop `NewGame.png` onto Raspberry Pi (USB, SCP, etc.)
2. Run: ./compile-png.sh NewGame.png
3. Script calls: curl -X POST -F "png=@NewGame.png" http://localhost:3001/api/compile-js
4. Output: games/NewGame.js
5. Menu auto-detects new game on next refresh (or restart)
```

**Key benefit:** Zero external dependencies. The Pi is fully self-contained for game compilation.

### 2. Game Launcher — Custom HTML/JS Menu (replaces `MadeArcadeMenu.elf`)

**Standard web-based menu, not a MakeCode Arcade game.**

The menu is a plain HTML/CSS/JS page (like any web app) that:
- On load: `fetch('/api/games')` → list of `{ name, title, description, thumbnail }` from `games/` directory
- Renders a D-pad navigable game carousel
- Controller input: Gamepad API (via GPIO → `uinput` bridge, see below)
- On selection: navigates to `play.html?game=[name]` with the selected `.js` file

**Why not a MakeCode game as menu?** A simulator-hosted game cannot query the server's filesystem to list available games. The outer page must provide the list anyway, so we skip the indirection and build the menu in standard web tech.

### 3. Game Player — Simulator Page (based on `make-web/twominute`)

**The player is essentially `make-web/app/twominute/page.tsx` stripped down:**
- No timer, no NES games, no bezel, no control panel
- Just the simulator iframe loading the selected game's `.js` file
- Same pattern as `/twominute?game=Gelb` — load `[gameName].js` into the simulator runtime

**Architecture:**
```
http://localhost:3000/              ← menu carousel (custom HTML/JS)
http://localhost:3000/play?game=Gelb  ← simulator player loading `games/Gelb.js`
```

The `play` page:
- Hosts the simulator runtime (same files as `make-web/public/sim/`)
- Loads the specified `.js` file from `games/` directory
- Waits for `type: "ready"` postMessage from simulator
- Sends `{ type: "run", code: <game JS> }` to start the game
- Kill button triggers return to menu via `window.location = '/'`

**Proven approach:** `make-web/twominute` already does exactly this — it loads a game by name and runs it in the simulator.

### 4. Update `launcher.sh`

Replace:
```bash
"$RUNNER" "$RUN_DIR/MadeArcadeMenu.elf"
```

With something like:
```bash
node "$RUN_DIR/server.js" &
sleep 2
chromium --kiosk --noerrdialogs --disable-infobars \
  --no-first-run --disable-session-crashed-bubble \
  http://localhost:3000 &
```

### 5. Update `monitor_kill.py`

Replace ELF kill logic with Chromium kill:
```python
subprocess.run(["pkill", "-9", "chromium"], check=False)
```

The launcher loop (`launcher.sh`) will restart Chromium back to the menu. No separate menu process — just one Chromium instance navigating between pages.

### 6. GPIO → Browser Input Bridge

**Decision: Start with a Python `uinput` virtual gamepad daemon. Rewire to USB HID encoder boards only if lag is unacceptable.**

The current hardware: joystick/button microswitches soldered to female header pins, plugged directly into RPi GPIO. The wiring does not need to change for the `uinput` approach.

#### Primary approach: Python `uinput` virtual gamepad

A Python daemon (`gpio_bridge.py`) reads all GPIO pins from `arcade.cfg` and writes button events to a `/dev/uinput` virtual gamepad device. Chromium sees four standard gamepad devices via the Gamepad API — identical to USB HID controllers.

**Latency profile**: GPIO poll → kernel `uinput` event → Chromium Gamepad API (60Hz polling) → JS game input handler. Estimated **1–2 frames** above direct ELF GPIO. Imperceptible for the games on this machine.

**Required**: `python3-uinput` or the `evdev` package on the Pi. The `arcade.cfg` pin map is used directly as the source of truth.

**Player mapping**: 4 virtual gamepad devices created (one per player), each mapped to the `BTN_A`/`BTN_B`/`BTN_UP`/`BTN_DOWN`/`BTN_LEFT`/`BTN_RIGHT` for that player number from `arcade.cfg`.

#### Fallback: USB HID encoder boards

If `uinput` lag proves to be a problem: the existing female-header-crimped wire ends can be plugged onto USB encoder board terminals individually (no resoldering — just re-plugging headers). The `arcade.cfg` pin map would no longer be needed; the Gamepad API handles everything natively.

The `arcade.cfg` GPIO pin map (BTN_A through BTN_DOWN4) is the source of truth for both approaches.

---

## Known Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| **Browser freeze bricks the system** | `monitor_kill.py` hard-restarts Chromium on kill button (pkill -9); watchdog can detect unresponsiveness via heartbeat URL |
| Chromium startup time (~3-4s on RPi 3) | Pre-launch Chromium in background during git sync; show splash screen during boot |
| RPi 3 performance with JS simulator | RPi 3 runs Chromium + simple WebGL fine; tested for this use case in MakeCode kiosk docs |
| GPIO input bridge latency | Python `uinput` adds ~1-2 frames; acceptable for these games. USB HID encoder fallback if needed |
| "Just a web page" feel vs "boot to arcade" | Hide all boot messages via `quiet` kernel param + plymouth splash; seamless kiosk launch feels like dedicated firmware |
| Simulator JS files getting out of sync with game bundles | Pin `sim/` files to a specific pxt-arcade version; update intentionally |
| Offline operation | All simulator JS files live in `sim/` in the repo; no CDN dependency |

### Addressing the "App on Desktop" Feel

The concern about Option 2 feeling like "just an app on a desktop" can be mitigated through boot sequence hardening:

1. **Kernel:** Add `quiet splash` to `/boot/cmdline.txt` — suppress all kernel messages
2. **systemd:** Disable Getty on TTY1, hide systemd units via `quiet` parameter
3. **Plymouth:** Add custom "Creation Station Arcade" boot splash (replace rainbow screen)
4. **Login:** `pi` user auto-logs in, `launcher.sh` immediately starts Chromium
5. **Chromium flags:** `--kiosk --noerrdialogs --disable-infobars --no-first-run --disable-session-crashed-bubble`

The user experience becomes: **Power on → Arcade logo → Game menu** with no visible OS. This is indistinguishable from the current ELF flow.

### Browser Freeze Mitigation Strategy

Since the entire experience lives in one Chromium process, a freeze is catastrophic. Two layers of defense:

**Layer 1: Cooperative heartbeat**
- The web app POSTs to `/api/heartbeat` every 5 seconds while running
- `monitor_kill.py` watches for missing heartbeats; if 3 consecutive misses → `pkill -9 chromium`
- Launcher restarts Chromium, returning to menu

**Layer 2: Kill button always works**
- GPIO kill button (BCM 3) triggers `pkill -9 chromium` via `monitor_kill.py`
- Launcher loop brings it back

---

## Reference: Build Tooling

The build tooling now lives in two places:

**POCs to copy from (not call directly):**

- `~/Projects/make-web/apps/compile-service/` — **standalone Node.js compile service**
  - `src/js-compile.ts` — PXT compiler logic to copy (runs PNG → JS entirely on Pi)
  - `pxt/target.js` — required for hw---vm compilation, copy to `compile-service/pxt/`
  - Runs as local HTTP service, no network calls needed
- `~/Projects/make-web/app/twominute/` — simulator player pattern (strip to just game)
- `~/Projects/make-web/public/sim/` — simulator runtime files (copy to `CreationStationArcade/sim/`)
- `~/Projects/make-web/lib/png-decode.ts` — PNG steganography decoder (copy to compile-service)
- `~/Projects/makecode-desktop/` — Electrobun POC (documented but **not selected**)

**Reference only:**
- `~/Projects/pxt-root/` — original PXT toolchain workspace
  - `pxt-arcade/libs/hw---vm/` — the VM hardware target definition

---

## Implementation Checklist

### Phase 1: On-Pi Compile Service (copy from `make-web/apps/compile-service/`)
- [ ] Copy `src/js-compile.ts` and `pxt/target.js` to `CreationStationArcade/compile-service/`
- [ ] Build minimal HTTP server with `POST /api/compile-js` and `GET /api/games`
- [ ] Create `./compile-png.sh` script for CLI compilation
- [ ] Test: drop PNG → compile → `games/[name].js` available
- [ ] Verify 4-player input compiles correctly to JS target

### Phase 2: Simulator Hosting (`CreationStationArcade/sim/`)
- [ ] Copy simulator runtime from `pxt-arcade/built/sim/` to `sim/`
- [ ] Create `public/index.html` — game carousel (HTML/CSS/JS, not MakeCode)
- [ ] Create `public/play.html` — simulator host page with iframe
- [ ] Build small HTTP server (`server.js`) to serve files + API

### Phase 3: Input Bridge (`CreationStationArcade/gpio_bridge.py`)
- [ ] Python daemon reading `arcade.cfg` pin map
- [ ] Write events to `/dev/uinput` virtual gamepads (4 players)
- [ ] Test latency with fast-twitch games
- [ ] Fallback plan: USB HID encoder boards if lag is unacceptable

### Phase 4: Launcher & Monitor Updates
- [ ] Update `launcher.sh` — start HTTP server + Chromium kiosk
- [ ] Update `monitor_kill.py` — kill Chromium, heartbeat watchdog
- [ ] Add cooperative heartbeat to web app
- [ ] Test kill button recovery flow

### Phase 5: Boot Experience
- [ ] Configure `cmdline.txt` with `quiet splash`
- [ ] Add Plymouth boot splash (Creation Station Arcade logo)
- [ ] Hide all boot messages
- [ ] Test power-on to game menu flow — should feel like dedicated hardware

### Phase 6: Migration
- [ ] Recompile all games in `games/` from `.elf` to `.js`
- [ ] Remove ELF launcher dependencies
- [ ] Update documentation
- [ ] Deploy to arcade machine
