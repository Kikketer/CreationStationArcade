/**
 * MadeArcade Menu - NES.css DOM-based Game Launcher
 * Pure DOM with native scrolling and animated GIF support
 */

const GAMEPAD_REPEAT_DELAY = 200;
const IDLE_TIMEOUT_MS = 2 * 60 * 1000; // 2 minutes

// State
let games = [];
let selectedIndex = 0;
let previousSelectedIndex = -1;
let cardElements = [];
let lastGamepadInput = 0;
let isLaunching = false;
let placeholderCache = {};

// Scene state: 'menu' | 'attract'
let currentScene = 'attract';
let idleTimer = null;
let lastActivityTime = Date.now();

// DOM elements
const gameList = document.getElementById('game-list');
const pixelScreen = document.getElementById('pixel-screen');
const sceneMenu = document.getElementById('scene-menu');
const sceneAttract = document.getElementById('scene-attract');

// Virtual resolution
const VIRTUAL_W = 160;
const VIRTUAL_H = 120;
// Trim factor: slightly reduces scale to inset from physical mask edges
// 8/9 ≈ 0.8889 gives exact 8x integer scale on 1920x1080, eliminating sub-pixel wiggle
const SCALE_TRIM = 8 / 9;

// Per-machine display tuning from config.json "display": offset in screen
// pixels (for bezels/CRT masks) and an extra scale multiplier.
let displayCfg = { offsetX: 0, offsetY: 0, scale: 1 };

// Calculate scale to fill width or height while maintaining aspect ratio
function updateScale() {
  const scaleX = window.innerWidth / VIRTUAL_W;
  const scaleY = window.innerHeight / VIRTUAL_H;
  const scale = Math.min(scaleX, scaleY) * SCALE_TRIM * (displayCfg.scale || 1);
  pixelScreen.style.setProperty('--scale', scale);
  // Margins shift the flex-centered element in real screen pixels — offset
  // stays constant regardless of scale.
  pixelScreen.style.marginLeft = `${displayCfg.offsetX || 0}px`;
  pixelScreen.style.marginTop = `${displayCfg.offsetY || 0}px`;
}

// Initial scale and resize handler
updateScale();
window.addEventListener('resize', updateScale);

// Generate placeholder image (60x32 for 160x120 virtual resolution)
function generatePlaceholderImage(name) {
  // Return cached version if available
  if (placeholderCache[name]) return placeholderCache[name];

  const c = document.createElement('canvas');
  c.width = 60;
  c.height = 32;
  const ctx = c.getContext('2d');
  ctx.imageSmoothingEnabled = false;

  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = (hash * 31 + name.charCodeAt(i)) >>> 0;
  }

  const colors = ['#e76e55', '#f7d51d', '#209cee', '#92cc41', '#a65ec5', '#4aa52e'];
  ctx.fillStyle = colors[hash % colors.length];
  ctx.fillRect(0, 0, 60, 32);
  ctx.fillStyle = '#fff';
  for (let i = 0; i < 8; i++) {
    const px = ((hash >> (i * 2)) & 15) % 60;
    const py = ((hash >> (i * 2 + 1)) & 15) % 32;
    ctx.fillRect(px & 0xFC, py & 0xFC, 4, 4);
  }

  const dataUrl = c.toDataURL();
  placeholderCache[name] = dataUrl;
  return dataUrl;
}

// Create game cards
function createGameCards() {
  gameList.innerHTML = '';
  cardElements = [];

  games.forEach((game, index) => {
    const card = document.createElement('div');
    card.className = 'game-card nes-container';
    card.dataset.index = index;

    // Image
    const img = document.createElement('img');
    img.className = 'game-image';
    img.alt = '';

    // Image sources: use explicit image field, or derive from file field
    const baseName = game.image
      ? game.image.replace(/\.[^.]+$/, '')
      : game.file.replace(/\.[^.]+$/, '');
    img.dataset.staticSrc = `/games/${baseName}.png`;
    img.dataset.animSrc = `/games/${baseName}.gif`;

    // Load static image with fallback
    img.src = img.dataset.staticSrc;
    img.onerror = () => { img.src = generatePlaceholderImage(game.name); };

    // Player count (floating over image)
    const players = document.createElement('div');
    players.className = 'player-count';
    players.textContent = `${game.playerCount}P`;

    card.appendChild(img);
    card.appendChild(players);

    // Click to select
    card.addEventListener('click', () => {
      selectedIndex = index;
      updateSelection();
    });

    gameList.appendChild(card);
    cardElements.push({ card, img, game });
  });

  updateSelection();
}

// Update selection - only touch changed cards to prevent reflow
function updateSelection() {
  // Update previously selected card - remove highlight, revert to static
  if (previousSelectedIndex >= 0 && previousSelectedIndex !== selectedIndex) {
    const prev = cardElements[previousSelectedIndex];
    if (prev) {
      prev.card.classList.remove('selected');
      if (prev.img.dataset.staticSrc && prev.img.src !== prev.img.dataset.staticSrc) {
        prev.img.src = prev.img.dataset.staticSrc;
      }
    }
  }

  // Update newly selected card - add highlight, try GIF
  const curr = cardElements[selectedIndex];
  if (curr) {
    curr.card.classList.add('selected');
    // Try animated GIF if not already loaded
    if (curr.img.dataset.animSrc && !curr.img.src.endsWith('.gif')) {
      const animImg = new Image();
      animImg.onload = () => { curr.img.src = curr.img.dataset.animSrc; };
      animImg.src = curr.img.dataset.animSrc;
    }
    // Scroll into view only if off-screen
    const rect = curr.card.getBoundingClientRect();
    const listRect = gameList.getBoundingClientRect();
    if (rect.top < listRect.top || rect.bottom > listRect.bottom) {
      curr.card.scrollIntoView({ behavior: 'auto', block: 'nearest' });
    }
  }

  // Track for next time
  previousSelectedIndex = selectedIndex;
}

// --- hidden archive gesture ---
// B B B B B — the 5th B held for 5s "arms" the selected game; while armed,
// pressing A archives it (server moves the files to .archived/) and releasing
// B cancels. Same gesture as the native branch's menu.
const ARCHIVE_COMBO_LEN = 5;
const ARCHIVE_COMBO_GAP_MS = 1500;
const ARCHIVE_HOLD_MS = 5000;
let bCombo = 0;
let lastBPress = 0;
let bHoldStart = 0;
let archiveArmed = false;
let bWasDown = false;

function resetArchiveGesture() {
  bCombo = 0;
  bHoldStart = 0;
  disarmArchive();
}

function disarmArchive() {
  if (!archiveArmed) return;
  archiveArmed = false;
  cardElements[selectedIndex]?.card.classList.remove('is-armed');
}

// No text or prompt — the only visible cue is a subtle red border, so the
// gesture stays undiscoverable. A while armed archives; releasing B cancels.
function armArchive() {
  const game = games[selectedIndex];
  if (!game || !game.file) { resetArchiveGesture(); return; } // tiles can't be archived
  archiveArmed = true;
  cardElements[selectedIndex]?.card.classList.add('is-armed');
}

function onBPress() {
  const now = performance.now();
  if (now - lastBPress > ARCHIVE_COMBO_GAP_MS) bCombo = 0;
  lastBPress = now;
  bCombo++;
  if (bCombo >= ARCHIVE_COMBO_LEN) {
    bCombo = ARCHIVE_COMBO_LEN;
    bHoldStart = now;
  }
}

// Runs every frame with the raw B state — not throttled like other input,
// so quick taps aren't missed.
function trackArchiveGesture(bDown, now) {
  if (currentScene !== 'menu' || isLaunching) {
    if (archiveArmed) disarmArchive();
    if (!bDown) bCombo = 0;
    bWasDown = bDown;
    return;
  }
  if (bDown && !bWasDown) onBPress();
  if (bDown && bCombo >= ARCHIVE_COMBO_LEN && !archiveArmed && bHoldStart && now - bHoldStart >= ARCHIVE_HOLD_MS) {
    armArchive();
  }
  // Releasing B after the combo completes cancels the arming.
  if (!bDown && bWasDown && (archiveArmed || bCombo >= ARCHIVE_COMBO_LEN)) resetArchiveGesture();
  bWasDown = bDown;
}

async function confirmArchive() {
  const game = games[selectedIndex];
  resetArchiveGesture();
  if (!game || !game.file) return;
  try {
    const res = await fetch(`/api/archive-game?file=${encodeURIComponent(game.file)}`);
    if (res.ok) await refreshGames();
  } catch (e) {
    console.error('Archive error:', e);
  }
}

// Navigation with grid layout awareness (2 columns fixed)
function move(dir) {
  if (!games.length || isLaunching) return;
  resetArchiveGesture();

  const cards = cardElements.length;
  const columns = 2; // Fixed 2-column layout

  switch(dir) {
    case 'up':
      selectedIndex = Math.max(0, selectedIndex - columns);
      break;
    case 'down':
      selectedIndex = Math.min(cards - 1, selectedIndex + columns);
      break;
    case 'left':
      selectedIndex = Math.max(0, selectedIndex - 1);
      break;
    case 'right':
      selectedIndex = Math.min(cards - 1, selectedIndex + 1);
      break;
  }

  updateSelection();
}

// Launch game (or confirm an armed archive)
async function selectGame() {
  if (!games.length || isLaunching) return;
  if (archiveArmed) { confirmArchive(); return; }
  const game = games[selectedIndex];
  if (!game || !game.file) return;

  isLaunching = true;
  const card = cardElements[selectedIndex]?.card;
  if (card) card.classList.add('is-disabled');

  try {
    const res = await fetch(`/api/launch-game?name=${encodeURIComponent(game.name)}&file=${encodeURIComponent(game.file)}`);
    const data = await res.json();

    if (res.status === 409) console.log('Game already running');
    else if (res.status === 429) console.log('Launch pending');
    else if (data.ok) console.log('Game launched');
  } catch (e) {
    console.error('Launch error:', e);
  }

  isLaunching = false;
  if (card) card.classList.remove('is-disabled');
}

// Load games
async function loadGames() {
  try {
    const res = await fetch('/api/games');
    games = await res.json();
  } catch (e) {
    games = [];
    gameList.innerHTML = '<div style="grid-column: 1/-1; text-align: center; padding: 2rem;">No games found</div>';
  }

  if (games.length > 0) {
    createGameCards();
  }
}

// ---- Scene / idle management ----

function showScene(name) {
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = null;

  if (name === 'menu') {
    sceneMenu.classList.remove('hidden');
    sceneAttract.classList.add('hidden');
    currentScene = 'menu';
    // After idle period on menu, switch to attract
    idleTimer = setTimeout(() => showScene('attract'), IDLE_TIMEOUT_MS);
  } else {
    // Reload the page when entering attract mode so Chromium gets a clean refresh
    // (but only if we were previously on the menu — not on initial page load)
    if (currentScene === 'menu') {
      location.reload();
      return;
    }
    sceneMenu.classList.add('hidden');
    sceneAttract.classList.remove('hidden');
    currentScene = 'attract';
    idleTimer = setTimeout(() => showScene('menu'), IDLE_TIMEOUT_MS);
  }
}

function resetIdleTimer() {
  lastActivityTime = Date.now();
  if (currentScene !== 'menu') return;
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = setTimeout(() => showScene('attract'), IDLE_TIMEOUT_MS);
}

function onActivity() {
  if (currentScene !== 'menu') {
    showScene('menu');
  }
  resetIdleTimer();
}

// Start in attract mode; timer will flip to menu after timeout
showScene('attract');

// ---- Aggressive focus management for kiosk mode ----
function ensureFocus() {
  if (document.activeElement !== document.body) {
    document.body.focus();
  }
}
window.addEventListener('load', () => {
  document.body.tabIndex = 0;
  document.body.focus();
  setInterval(ensureFocus, 100);
});
window.addEventListener('blur', () => setTimeout(() => document.body.focus(), 10));
document.addEventListener('visibilitychange', () => { if (!document.hidden) document.body.focus(); });

// Keyboard input - multiple listeners for kiosk compatibility
function handleKey(e) {
  const wasAttract = currentScene !== 'menu';
  onActivity();
  if (wasAttract) return; // wakeup press only - don't act
  switch(e.key) {
    case 'ArrowUp':    e.preventDefault(); move('up'); break;
    case 'ArrowDown':  e.preventDefault(); move('down'); break;
    case 'ArrowLeft':  e.preventDefault(); move('left'); break;
    case 'ArrowRight': e.preventDefault(); move('right'); break;
    case 'x':
    case 'X':
      // 'x' is the keyboard B button — same archive gesture as the gamepad.
      if (!e.repeat) onBPress();
      else if (bCombo >= ARCHIVE_COMBO_LEN && !archiveArmed && performance.now() - bHoldStart >= ARCHIVE_HOLD_MS) armArchive();
      break;
    case 'Enter':
    case ' ':
    case 'z':
    case 'Z':          e.preventDefault(); selectGame(); break;
  }
}
window.addEventListener('keydown', handleKey, true);
window.addEventListener('keyup', (e) => {
  if ((e.key === 'x' || e.key === 'X') && (archiveArmed || bCombo >= ARCHIVE_COMBO_LEN)) resetArchiveGesture();
}, true);

// Gamepad input
function pollGamepads() {
  const pads = navigator.getGamepads ? navigator.getGamepads() : [];
  const now = performance.now();

  // B-button tracking runs every frame, before the input repeat throttle —
  // the archive combo needs to see quick taps.
  let bDown = false;
  for (const pad of pads) {
    if (pad && pad.buttons[1]?.pressed) { bDown = true; break; }
  }
  trackArchiveGesture(bDown, now);

  if (now - lastGamepadInput <= GAMEPAD_REPEAT_DELAY) {
    requestAnimationFrame(pollGamepads);
    return;
  }

  for (const pad of pads) {
    if (!pad) continue;

    const up = pad.buttons[12]?.pressed || pad.axes[1] < -0.5;
    const down = pad.buttons[13]?.pressed || pad.axes[1] > 0.5;
    const left = pad.buttons[14]?.pressed || pad.axes[0] < -0.5;
    const right = pad.buttons[15]?.pressed || pad.axes[0] > 0.5;
    const a = pad.buttons[0]?.pressed;
    const b = pad.buttons[1]?.pressed;

    const anyPressed = up || down || left || right || a || b;
    if (anyPressed) {
      const wasAttract = currentScene !== 'menu';
      onActivity();
      lastGamepadInput = now;
      if (wasAttract) continue; // wakeup press only - don't act
    }
    if (currentScene !== 'menu') continue;

    if (up)    { move('up'); }
    else if (down)  { move('down'); }
    else if (left)  { move('left'); }
    else if (right) { move('right'); }
    else if (a)     { selectGame(); }
  }

  requestAnimationFrame(pollGamepads);
}

// Heartbeat
function startHeartbeat() {
  setInterval(() => fetch('/api/heartbeat').catch(() => {}), 5000);
}

// Re-fetch the game list periodically so games installed from a USB stick
// show up without a reboot. Rebuilds the cards only when the list changed.
let gamesSignature = '';
function gamesListSignature(list) {
  return JSON.stringify(list.map(g => [g.file, g.name, g.author, g.playerCount]));
}
async function refreshGames() {
  try {
    const res = await fetch('/api/games');
    const fresh = await res.json();
    if (!Array.isArray(fresh)) return;
    const sig = gamesListSignature(fresh);
    if (sig === gamesSignature) return;
    gamesSignature = sig;
    games = fresh;
    archiveArmed = false; // rebuilt cards drop the armed marker anyway
    if (games.length === 0) {
      selectedIndex = 0;
      previousSelectedIndex = -1;
      gameList.innerHTML = '<div style="grid-column: 1/-1; text-align: center; padding: 2rem;">No games found</div>';
      return;
    }
    selectedIndex = Math.min(selectedIndex, games.length - 1);
    previousSelectedIndex = -1;
    createGameCards();
  } catch (e) {}
}

function startGamesPolling() {
  gamesSignature = gamesListSignature(games);
  setInterval(() => { if (!isLaunching) refreshGames(); }, 5000);
}

// Per-machine config (~/arcade-games/config.json -> /api/config).
// "attractLines" replaces the title screen text; wrap a word in *asterisks*
// to render it with the .highlight accent color.
async function loadConfig() {
  try {
    const res = await fetch('/api/config');
    const cfg = await res.json();
    if (!cfg || typeof cfg !== 'object') return;
    if (cfg.display && typeof cfg.display === 'object') {
      displayCfg = { offsetX: 0, offsetY: 0, scale: 1, ...cfg.display };
      updateScale();
    }
    if (!Array.isArray(cfg.attractLines) || !cfg.attractLines.length) return;
    const el = document.getElementById('attract-text');
    el.innerHTML = '';
    for (const line of cfg.attractLines) {
      const p = document.createElement('p');
      for (const part of String(line).split(/(\*[^*]+\*)/g)) {
        if (part.length > 2 && part.startsWith('*') && part.endsWith('*')) {
          const s = document.createElement('span');
          s.className = 'highlight';
          s.textContent = part.slice(1, -1);
          p.appendChild(s);
        } else if (part) {
          p.appendChild(document.createTextNode(part));
        }
      }
      el.appendChild(p);
    }
  } catch (e) {}
}

// Init
window.addEventListener('gamepadconnected', () => {});
pollGamepads();
loadConfig();
loadGames().then(() => { startHeartbeat(); startGamesPolling(); });
