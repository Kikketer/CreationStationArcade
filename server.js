#!/usr/bin/env node
// Creation Station Arcade - local HTTP server
// Serves public/ as static files, provides /api/games, and spawns game Chromium

const http = require("http");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn, exec, execFile } = require("child_process");

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
function handleConfig(res) {
  fs.readFile(path.join(GAMES_DIR, "config.json"), (err, data) => {
    res.writeHead(200, {
      "Content-Type": "application/json",
      "Cache-Control": "no-cache",
    });
    if (err) return res.end("{}");
    try {
      JSON.parse(data);
      res.end(data);
    } catch (e) {
      res.end("{}");
    }
  });
}

function handleHeartbeat(res) {
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ ok: true, ts: Date.now() }));
}

// Track the game Chromium process
let gameProcess = null;
let gameLaunchTime = 0;

function isGameRunning() {
  if (!gameProcess) return false;
  try {
    process.kill(gameProcess.pid, 0); // Check if process exists
    return true;
  } catch (e) {
    gameProcess = null;
    return false;
  }
}

// Actual display resolution for the game window — hardcoding 1920x1080
// overflows non-widescreen monitors. Fall back to 1080p.
function displayRes() {
  try {
    const out = require("child_process").execSync("xrandr 2>/dev/null").toString();
    const line = out.split("\n").find((l) => l.includes("*"));
    const m = line && line.match(/(\d+x\d+)/);
    if (m) return m[1];
  } catch (e) {}
  return "1920x1080";
}

function spawnGameChromium(gameName, gameFile) {
  // Clear previous game user data to prevent "restore session" prompts
  const gameUserDir = "/tmp/chromium-arcade-game";
  try {
    require("child_process").execSync(`rm -rf "${gameUserDir}"`);
  } catch (e) {
    // Ignore cleanup errors
  }

  const chromiumBin = process.env.CHROMIUM_BIN || 
    require("child_process").execSync("which chromium 2>/dev/null || which chromium-browser 2>/dev/null || echo ''").toString().trim();
  
  if (!chromiumBin) {
    console.error("[CSA] Chromium not found");
    return null;
  }

  const gameUrl = `http://localhost:${PORT}/play?game=${encodeURIComponent(gameName)}&file=${encodeURIComponent(gameFile || gameName)}`;
  
  const args = [
    "--user-data-dir=/tmp/chromium-arcade-game",
    "--kiosk",  // Kiosk mode - no exit UI
    "--window-position=0,0",
    `--window-size=${displayRes()}`,
    "--start-fullscreen",
    "--noerrdialogs",
    "--disable-infobars",
    "--no-first-run",
    "--disable-session-crashed-bubble",
    "--no-default-browser-check",
    "--disable-pinch",
    "--disable-extensions",
    "--disable-background-networking",
    "--disable-sync",
    "--disable-default-apps",
    "--disable-features=Translate,PreloadMediaEngagementData,MediaEngagementBypassAutoplayPolicies,RequestTabletSite,WebRTC,AccessibilityCache,AutofillServerCommunication,InfiniteSessionRestore",
    "--enable-features=VaapiVideoDecoder,VaapiVideoEncoder,CanvasOopRasterization,GpuRasterization,ZeroCopy",
    "--ignore-gpu-blocklist",
    "--enable-gpu-rasterization",
    "--use-gl=egl",
    "--hide-scrollbars",
    "--suppress-message-center-popups",
    gameUrl
  ];

  console.log(`[CSA] Spawning game Chromium for: ${gameName}`);
  
  const proc = spawn(chromiumBin, args, {
    detached: false,
    stdio: "ignore",
    env: { ...process.env, DISPLAY: process.env.DISPLAY || ':0' }
  });

  // Write PID file for kill-to-menu.sh
  fs.writeFileSync("/tmp/arcade-game-chromium.pid", proc.pid.toString());

  proc.on("exit", (code) => {
    console.log(`[CSA] Game Chromium exited (code: ${code})`);
    gameProcess = null;
    try {
      fs.unlinkSync("/tmp/arcade-game-chromium.pid");
    } catch (e) {
      // File might not exist, that's okay
    }
    
    // Refocus menu window via xdotool
    try {
      require("child_process").execSync(
        'xdotool search --onlyvisible --class "chromium" | head -1 | xargs -I {} xdotool windowraise {} windowfocus {} windowactivate {} 2>/dev/null || true'
      );
    } catch (e) {
      // xdotool might fail, that's okay
    }
  });

  proc.on("error", (err) => {
    console.error(`[CSA] Game Chromium error: ${err}`);
    gameProcess = null;
  });

  // Lower menu window and raise game window
  setTimeout(() => {
    try {
      // Find all Chromium windows, lower the first (menu), raise the rest
      const windows = require("child_process")
        .execSync('xdotool search --class "chromium" 2>/dev/null')
        .toString()
        .trim()
        .split("\n")
        .filter(id => id);
      
      if (windows.length >= 1) {
        // Lower first window (menu)
        try { require("child_process").execSync(`xdotool windowlower ${windows[0]} 2>/dev/null`); } catch (e) {}
      }
      if (windows.length >= 2) {
        // Raise last window (game - should be newest)
        const gameWin = windows[windows.length - 1];
        try { 
          require("child_process").execSync(`xdotool windowraise ${gameWin} windowfocus ${gameWin} windowactivate ${gameWin} 2>/dev/null`);
        } catch (e) {}
      }
    } catch (e) {
      // Window management failed, but game is still running
    }
  }, 3000);

  return proc;
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
  if (isGameRunning()) {
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

  // Spawn game Chromium
  gameProcess = spawnGameChromium(gameName, gameFile);
  gameLaunchTime = now;

  if (!gameProcess) {
    res.writeHead(500, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Failed to spawn Chromium" }));
    return;
  }

  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ ok: true, game: gameName, pid: gameProcess.pid }));
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
