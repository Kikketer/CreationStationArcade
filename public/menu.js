/**
 * MadeArcade Menu - NES.css DOM-based Game Launcher
 * Pure DOM with native scrolling and animated GIF support
 */

const GAMEPAD_REPEAT_DELAY = 200;
const IDLE_TIMEOUT_MS = 4 * 60 * 1000; // 4 minutes

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

// Calculate scale to fill width or height while maintaining aspect ratio
function updateScale() {
  const scaleX = window.innerWidth / VIRTUAL_W;
  const scaleY = window.innerHeight / VIRTUAL_H;
  const scale = Math.min(scaleX, scaleY);
  pixelScreen.style.setProperty('--scale', scale);
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

    // Image sources: derive from file field (e.g., Game.js -> Game.png, Game.gif)
    const baseName = game.file.replace(/\.[^.]+$/, '');
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

// Navigation with grid layout awareness (2 columns fixed)
function move(dir) {
  if (!games.length || isLaunching) return;

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

// Launch game
async function selectGame() {
  if (!games.length || isLaunching) return;
  const game = games[selectedIndex];
  if (!game) return;

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
  if (name === 'menu') {
    sceneMenu.classList.remove('hidden');
    sceneAttract.classList.add('hidden');
    currentScene = 'menu';
  } else {
    sceneMenu.classList.add('hidden');
    sceneAttract.classList.remove('hidden');
    currentScene = 'attract';
  }
}

function resetIdleTimer() {
  lastActivityTime = Date.now();
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = setTimeout(() => showScene('attract'), IDLE_TIMEOUT_MS);
}

function onActivity() {
  if (currentScene !== 'menu') {
    showScene('menu');
  }
  resetIdleTimer();
}

// Start in attract mode; any button press will switch to menu
showScene('attract');
resetIdleTimer();

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
  onActivity();
  if (currentScene !== 'menu') return; // absorbed into menu, don't act yet
  switch(e.key) {
    case 'ArrowUp':    e.preventDefault(); move('up'); break;
    case 'ArrowDown':  e.preventDefault(); move('down'); break;
    case 'ArrowLeft':  e.preventDefault(); move('left'); break;
    case 'ArrowRight': e.preventDefault(); move('right'); break;
    case 'Enter':
    case ' ':
    case 'z':
    case 'Z':          e.preventDefault(); selectGame(); break;
  }
}
window.addEventListener('keydown', handleKey, true);

// Gamepad input
function pollGamepads() {
  const pads = navigator.getGamepads ? navigator.getGamepads() : [];
  const now = performance.now();

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

    const anyPressed = up || down || left || right || a;
    if (anyPressed) {
      onActivity();
      lastGamepadInput = now;
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

// Init
window.addEventListener('gamepadconnected', () => {});
pollGamepads();
loadGames().then(() => startHeartbeat());
