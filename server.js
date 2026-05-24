#!/usr/bin/env node
// Creation Station Arcade - local HTTP server
// Serves public/ as static files and provides /api/games

const http = require("http");
const fs = require("fs");
const path = require("path");

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
        file: f,
      }));
    res.writeHead(200, {
      "Content-Type": "application/json",
      "Cache-Control": "no-cache",
    });
    res.end(JSON.stringify(games));
  });
}

function handleHeartbeat(res) {
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ ok: true, ts: Date.now() }));
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

  if (pathname.startsWith("/games/")) {
    const gameFile = path.basename(pathname);
    return serveFile(res, path.join(GAMES_DIR, gameFile));
  }

  if (pathname.startsWith("/sim/")) {
<<<<<<< HEAD
    const simRelPath = pathname.slice("/sim/".length);
=======
    let simRelPath = pathname.slice("/sim/".length);
    // Default to webgpu.html for testing
    if (simRelPath === "" || simRelPath === "/") {
      simRelPath = "webgpu.html";
    }
>>>>>>> d6b53ea479e3072839a62020aaa2765122e61ee5
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
