#!/usr/bin/env node
// Creation Station Arcade - local HTTP server
// Serves public/ as static files, provides /api/games, and spawns game Chromium

const http = require("http");
const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");

const PORT = process.env.PORT || 3000;
const ROOT = __dirname;
const PUBLIC_DIR = path.join(ROOT, "public");
const GAMES_DIR = path.join(ROOT, "games");
const SIM_DIR = path.join(ROOT, "sim");

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
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

function handleGames(res) {
  const gamesJsonPath = path.join(GAMES_DIR, "games.json");

  fs.readFile(gamesJsonPath, (err, data) => {
    if (err) {
      // Fallback to directory scan if games.json doesn't exist
      fs.readdir(GAMES_DIR, (err, files) => {
        if (err) {
          res.writeHead(500, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "Cannot read games directory" }));
          return;
        }
        const games = files
          .filter((f) => f.endsWith(".js") && !f.startsWith("."))
          .map((f) => ({
            name: path.basename(f, ".js"),
            playerCount: 1,
            image: "",
            file: f,
          }));
        res.writeHead(200, {
          "Content-Type": "application/json",
          "Cache-Control": "no-cache",
        });
        res.end(JSON.stringify(games));
      });
      return;
    }

    try {
      const games = JSON.parse(data);
      res.writeHead(200, {
        "Content-Type": "application/json",
        "Cache-Control": "no-cache",
      });
      res.end(JSON.stringify(games));
    } catch (e) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Invalid games.json format" }));
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
    "--window-size=1920,1080",
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
    "--disable-features=Translate,PreloadMediaEngagementData,MediaEngagementBypassAutoplayPolicies,RequestTabletSite,WebRTC,AccessibilityCache,AutofillServerCommunication",
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

function handleLaunchGame(res, gameName, gameFile) {
  // Check if game already running
  if (isGameRunning()) {
    res.writeHead(409, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Game already running", active: true }));
    return;
  }

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

  if (pathname === "/api/heartbeat") {
    return handleHeartbeat(res);
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
    return serveFile(res, path.join(GAMES_DIR, gameFile));
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
