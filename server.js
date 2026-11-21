#!/usr/bin/env node
// Creation Station Arcade - local HTTP server
// Serves public/ as static files, provides /api/games, and tracks game state
// for the single-window kiosk (the menu page swaps the game in via iframe).

const http = require("http");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFile } = require("child_process");

const STATS_FILE = path.join(os.homedir(), "arcade-stats.json");

const PORT = process.env.PORT || 3000;
const ROOT = __dirname;
const PUBLIC_DIR = path.join(ROOT, "public");
const SIM_DIR = path.join(ROOT, "sim");
const MEDIA_DIR = path.join(ROOT, "media");
// Games live outside the repo entirely so the codebase is machine-agnostic:
// ~/arcade-games survives the boot-time git reset + rsync wipe of the
// runtime folder. Stock games are seeded there by the setup script and the
// USB update service installs more from a thumb drive.
const GAMES_DIR = process.env.CSA_GAMES_DIR || path.join(os.homedir(), "arcade-games");

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".gif": "image/gif",
  ".jpg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".woff2": "font/woff2",
};

function serveFile(res, filePath) {
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404, { "Content-Type": "text/plain" });
      res.end("Not found");
      return;
    }
    const ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, { "Content-Type": MIME[ext] || "application/octet-stream" });
    res.end(data);
  });
}

// Read the game list for one games dir: its games.json, else a directory scan.
function readGameList(dir, cb) {
  fs.readFile(path.join(dir, "games.json"), (err, data) => {
    if (!err) {
      try {
        const games = JSON.parse(data);
        if (Array.isArray(games)) return cb(games);
      } catch (e) {
        // Invalid games.json — fall through to directory scan
      }
    }
    fs.readdir(dir, (err, files) => {
      if (err) return cb([]);
      cb(
        files
          .filter((f) => f.endsWith(".js") && !f.startsWith("."))
          .map((f) => ({
            name: path.basename(f, ".js"),
            playerCount: 1,
            image: "",
            file: f,
          }))
      );
    });
  });
}

function handleGames(res) {
  readGameList(GAMES_DIR, (games) => {
    // ControllerTest is a fallback sanity game: show it only when it's the
    // sole playable entry (like the native launcher's last-resort pick).
    const playable = games.filter((g) => g.file);
    if (playable.length > 1) {
      games = games.filter((g) => g.file !== "ControllerTest.js");
    }
    trackNewGames(games);
    res.writeHead(200, {
      "Content-Type": "application/json",
      "Cache-Control": "no-cache",
    });
    res.end(JSON.stringify(games));
  });
}

// Move a game's files into GAMES_DIR/.archived/ and regenerate games.json.
// Mirrors the native branch: archived games are hidden from the menu but
// kept on disk — restore by moving the files back and re-running regen.
function handleArchiveGame(res, gameFile) {
  const name = String(gameFile || "");
  const base = path.basename(name);
  if (!base.endsWith(".js") || base.startsWith(".") || base !== name) {
    res.writeHead(400, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Invalid file" }));
    return;
  }

  const stem = base.slice(0, -3);
  if (!fs.existsSync(path.join(GAMES_DIR, base))) {
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Game not found" }));
    return;
  }

  const archDir = path.join(GAMES_DIR, ".archived");
  fs.mkdirSync(archDir, { recursive: true });
  const stamp = Date.now();
  const moved = [];
  for (const ext of [".js", ".png", ".gif", ".json"]) {
    const f = stem + ext;
    const src = path.join(GAMES_DIR, f);
    if (!fs.existsSync(src)) continue;
    let dst = path.join(archDir, f);
    if (fs.existsSync(dst)) dst = path.join(archDir, `${stem}-${stamp}${ext}`);
    try {
      fs.renameSync(src, dst);
      moved.push(f);
    } catch (e) {
      console.error(`[CSA] Archive move failed for ${f}: ${e.message}`);
    }
  }

  execFile("python3", [path.join(ROOT, "install", "arcade-regen-games.py"), GAMES_DIR], (err) => {
    if (err) console.error(`[CSA] games.json regen after archive failed: ${err.message}`);
    console.log(`[CSA] Archived: ${moved.join(", ")}`);
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ok: true, archived: moved }));
  });
}

// Per-machine config (title screen text, etc.) lives in GAMES_DIR/config.json
// — outside the repo so each box can differ. Missing/invalid just means
// "use the defaults baked into the page".
// Strip // line comments and /* block comments */ from JSONC-style text,
// skipping anything inside string literals (URLs etc. stay intact).
function stripJsonComments(text) {
  let out = "";
  let inStr = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    const next = text[i + 1];
    if (inStr) {
      out += c;
      if (c === "\\") out += next || "";
      else if (c === '"') inStr = false;
      if (c === "\\") i++;
      continue;
    }
    if (c === '"') { inStr = true; out += c; continue; }
    if (c === "/" && next === "/") { while (i < text.length && text[i] !== "\n") i++; continue; }
    if (c === "/" && next === "*") { while (i < text.length && !(text[i] === "*" && text[i + 1] === "/")) i++; i++; continue; }
    out += c;
  }
  return out;
}

function handleConfig(res) {
  const respond = (err, data) => {
    res.writeHead(200, {
      "Content-Type": "application/json",
      "Cache-Control": "no-cache",
    });
    if (err) return res.end("{}");
    try {
      const stripped = stripJsonComments(data.toString());
      res.end(JSON.stringify(JSON.parse(stripped)));
    } catch (e) {
      res.end("{}");
    }
  };
  // config.jsonc preferred (IDEs flag comments in .json); config.json still works.
  fs.readFile(path.join(GAMES_DIR, "config.jsonc"), (err, data) => {
    if (err) {
      fs.readFile(path.join(GAMES_DIR, "config.json"), respond);
    } else {
      respond(null, data);
    }
  });
}

// POST body: {order: ["file1.js", ...]}. Rewrites games.json so entries
// appear in that order; unlisted entries keep their relative order and
// are appended at the end.
function handleReorder(req, res) {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    res.writeHead(200, { "Content-Type": "application/json" });
    let order;
    try {
      order = JSON.parse(body).order;
    } catch (e) {}
    if (!Array.isArray(order)) return res.end('{"ok":false}');
    const file = path.join(GAMES_DIR, "games.json");
    fs.readFile(file, (err, data) => {
      if (err) return res.end('{"ok":false}');
      let entries;
      try {
        entries = JSON.parse(data);
      } catch (e) {
        return res.end('{"ok":false}');
      }
      const used = new Set();
      const sorted = [];
      order.forEach((f) => {
        const i = entries.findIndex((e, j) => !used.has(j) && e.file === f);
        if (i !== -1) { used.add(i); sorted.push(entries[i]); }
      });
      entries.forEach((e, j) => { if (!used.has(j)) sorted.push(e); });
      fs.writeFile(file, JSON.stringify(sorted, null, 2), () => res.end('{"ok":true}'));
    });
  });
}

// GET /api/track-button?btn=N — increments stats.buttons[N]. Fire-and-forget
// from menu.js/play.html gamepad edge-detection (replaces the Pi-only GPIO
// monitor's job on x86).
function handleTrackButton(res, btn) {
  let stats = { buttons: {}, games: {}, first_seen: {}, last_updated: null };
  try {
    stats = JSON.parse(fs.readFileSync(STATS_FILE, "utf8"));
    stats.buttons = stats.buttons || {};
  } catch (e) {}
  const key = String(btn);
  stats.buttons[key] = (stats.buttons[key] || 0) + 1;
  stats.last_updated = new Date().toISOString().replace("T", " ").slice(0, 19);
  try {
    fs.writeFileSync(STATS_FILE + ".tmp", JSON.stringify(stats, null, 2));
    fs.renameSync(STATS_FILE + ".tmp", STATS_FILE);
  } catch (e) {}
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end('{"ok":true}');
}

// GET /api/kill-game — mark that the game should close. This is the
// out-of-page reset path (GPIO reset button, kill-to-menu.sh); the menu page
// polls /api/game-state and tears down the game iframe itself. Nothing is
// killed — the single kiosk window stays up the whole time.
function handleKillGame(res) {
  gameCloseRequested = true;
  console.log("[CSA] Return-to-menu requested via /api/kill-game");
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ ok: true }));
}

function handleHeartbeat(res) {
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ ok: true, ts: Date.now() }));
}

// Game state for the single-window kiosk. The menu page owns the whole
// lifecycle — it opens play.html in an iframe and removes it again. The
// server only tracks whether a game is "active" and whether someone asked
// to close it, so out-of-page resets can reach the page.
let gameActive = false;
let gameCloseRequested = false;
let gameLaunchTime = 0;

// GET /api/game-state — polled by the menu page while a game is open.
function handleGameState(res) {
  res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-cache" });
  res.end(JSON.stringify({ active: gameActive, closeRequested: gameCloseRequested }));
}

// GET /api/game-closed — the page reports the game iframe is gone. Also
// called on menu page load so a crashed game can't wedge the launcher.
function handleGameClosed(res) {
  gameActive = false;
  gameCloseRequested = false;
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ ok: true }));
}

function trackGamePlay(gameName) {
  try {
    let stats = { buttons: {}, games: {}, first_seen: {}, last_updated: null };
    try {
      const data = fs.readFileSync(STATS_FILE, 'utf8');
      stats = JSON.parse(data);
    } catch (e) {
      // File doesn't exist or is invalid, start fresh
    }
    stats.games[gameName] = (stats.games[gameName] || 0) + 1;
    stats.last_updated = new Date().toISOString().replace('T', ' ').slice(0, 19);
    fs.writeFileSync(STATS_FILE + '.tmp', JSON.stringify(stats, null, 2));
    fs.renameSync(STATS_FILE + '.tmp', STATS_FILE);
  } catch (e) {
    console.error(`[CSA] Failed to track game play: ${e.message}`);
  }
}

function trackNewGames(gamesList) {
  try {
    let stats = { buttons: {}, games: {}, first_seen: {}, last_updated: null };
    try {
      const data = fs.readFileSync(STATS_FILE, 'utf8');
      stats = JSON.parse(data);
    } catch (e) {
      // File doesn't exist or is invalid, start fresh
    }
    const now = new Date().toISOString().replace('T', ' ').slice(0, 19);
    let newGamesFound = false;
    for (const game of gamesList) {
      if (game.name && !stats.first_seen[game.name]) {
        stats.first_seen[game.name] = now;
        newGamesFound = true;
        console.log(`[CSA] New game detected: ${game.name} (added: ${now})`);
      }
    }
    if (newGamesFound) {
      stats.last_updated = now;
      fs.writeFileSync(STATS_FILE + '.tmp', JSON.stringify(stats, null, 2));
      fs.renameSync(STATS_FILE + '.tmp', STATS_FILE);
    }
  } catch (e) {
    console.error(`[CSA] Failed to track new games: ${e.message}`);
  }
}

function handleLaunchGame(res, gameName, gameFile) {
  // Check if game already running
  if (gameActive) {
    res.writeHead(409, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Game already running", active: true }));
    return;
  }

  // Track game play
  trackGamePlay(gameName);

  // Check if launch recently happened (debounce)
  const now = Date.now();
  if (now - gameLaunchTime < 5000) {
    res.writeHead(429, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Launch already pending", retryAfter: Math.ceil((5000 - (now - gameLaunchTime)) / 1000) }));
    return;
  }

  // Mark the game active — the menu page does the actual swap into its iframe.
  gameActive = true;
  gameCloseRequested = false;
  gameLaunchTime = now;

  console.log(`[CSA] Game launched (iframe swap): ${gameName}`);
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ ok: true, game: gameName }));
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const pathname = url.pathname;

  res.setHeader("Access-Control-Allow-Origin", "*");

  if (pathname === "/api/games") {
    return handleGames(res);
  }

  if (pathname === "/api/config") {
    return handleConfig(res);
  }

  if (pathname === "/api/reorder") {
    return handleReorder(req, res);
  }

  if (pathname === "/api/track-button") {
    return handleTrackButton(res, url.searchParams.get("btn"));
  }

  if (pathname === "/api/kill-game") {
    return handleKillGame(res);
  }

  if (pathname === "/api/game-state") {
    return handleGameState(res);
  }

  if (pathname === "/api/game-closed") {
    return handleGameClosed(res);
  }

  if (pathname === "/api/heartbeat") {
    return handleHeartbeat(res);
  }

  if (pathname === "/api/archive-game") {
    return handleArchiveGame(res, url.searchParams.get("file") || "");
  }

  if (pathname === "/api/launch-game") {
    const gameName = url.searchParams.get("name") || "";
    const gameFile = url.searchParams.get("file") || "";
    if (!gameName) {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Missing name parameter" }));
      return;
    }
    return handleLaunchGame(res, gameName, gameFile);
  }

  if (pathname.startsWith("/games/")) {
    const gameFile = path.basename(pathname);
    // no-cache so the browser refetches files a USB update replaced.
    res.setHeader("Cache-Control", "no-cache");
    return serveFile(res, path.join(GAMES_DIR, gameFile));
  }

  if (pathname.startsWith("/media/")) {
    const mediaFile = path.basename(pathname);
    return serveFile(res, path.join(MEDIA_DIR, mediaFile));
  }

  if (pathname.startsWith("/sim/")) {
    const simRelPath = pathname.slice("/sim/".length);
    const simFile = path.join(SIM_DIR, simRelPath);
    if (!simFile.startsWith(SIM_DIR)) {
      res.writeHead(403, { "Content-Type": "text/plain" });
      res.end("Forbidden");
      return;
    }
    return serveFile(res, simFile);
  }

  let filePath;
  if (pathname === "/" || pathname === "") {
    filePath = path.join(PUBLIC_DIR, "index.html");
  } else if (pathname === "/play" || pathname === "/play/") {
    filePath = path.join(PUBLIC_DIR, "play.html");
  } else {
    filePath = path.join(PUBLIC_DIR, pathname.replace(/^\//, ""));
  }

  // Prevent path traversal
  if (!filePath.startsWith(PUBLIC_DIR) && !filePath.startsWith(GAMES_DIR) && !filePath.startsWith(SIM_DIR)) {
    res.writeHead(403, { "Content-Type": "text/plain" });
    res.end("Forbidden");
    return;
  }

  serveFile(res, filePath);
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`[CSA] Server running at http://localhost:${PORT}`);
});
