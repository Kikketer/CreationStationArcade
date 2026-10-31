// Creation Station Arcade menu — "MadeArcade".
// Runs on the native (hw---vm) runtime — uses the control.* game hooks
// (programList / programImage / runProgram) that only exist there.
//
// Arcade palette reminder: index 0 is transparent, 1 is white, 15 is
// black. Background is black (15); all drawn colors stay in 1-14 so
// nothing punches a "hole" in the backdrop.
//
// Layout on the 160x120 screen:
//   - Banner (top ~28px): animated rainbow "MadeArcade" title over a
//     cycling palette strip. Redrawn on every page.
//   - Grid: 2x2 pages of 60x34 cover images. D-pad moves the selection,
//     past-the-edge flips to the next page. Centered up/down arrows
//     hint that more pages exist in that direction.
//   - Games with no cover.img/cover.png get a generated tile: a random
//     palette color for the tile + contrasting letter color.
//   - A/B launches the selected game via control.runProgram (which exits
//     this Game; the launcher loop starts the pick and returns here on
//     exit).

const SELF = "Menu"
const SKIP = ["ControllerTest"]
const PER_PAGE = 4
const COL_X = [10, 90]   // two 60px-wide columns
const ROW_Y = [34, 72]   // two 34px-tall rows
const COVER_W = 60
const COVER_H = 34
const BLACK = 15
const COLORS = 14        // usable bright palette indices are 1-14

let entries: string[] = []
for (const e of control.programList()) {
    if (e != SELF && SKIP.indexOf(e) < 0) {
        entries.push(e)
    }
}
const pageCount = Math.max(1, Math.ceil(entries.length / PER_PAGE))

let sel = 0
let tick = 0
let coverSprites: Sprite[] = []
// per-game placeholder tile colors, picked once so they don't flicker
let tileBg: number[] = []
let tileFg: number[] = []

function drawBanner(bg: Image) {
    // palette strip: 16 segments, hue drifts each tick (colors 1-14 only)
    for (let i = 0; i < 16; i++) {
        bg.fillRect(i * 10, 0, 10, 4, (i + tick) % COLORS + 1)
    }
    // title, one color per letter, marching the other way
    const title = "MadeArcade"
    const x0 = 50  // ~10 chars * 6px centered-ish
    for (let i = 0; i < title.length; i++) {
        bg.print(title.charAt(i), x0 + i * 6, 10, (tick + title.length - i) % COLORS + 1)
    }
    // second palette strip under the title, same drift as the top
    for (let i = 0; i < 16; i++) {
        bg.fillRect(i * 10, 24, 10, 4, (i + tick) % COLORS + 1)
    }
}

function tileColor(idx: number): number[] {
    // lazily pick a stable bg/fg pair per game
    while (tileBg.length <= idx) {
        let b = Math.randomRange(2, COLORS)
        let f = Math.randomRange(1, COLORS)
        if (f == b) f = (f % COLORS) + 1
        tileBg.push(b)
        tileFg.push(f)
    }
    return [tileBg[idx], tileFg[idx]]
}

function placeholder(idx: number, dir: string): Image {
    const pair = tileColor(idx)
    const img = image.create(COVER_W, COVER_H)
    img.fill(pair[0])
    img.drawRect(0, 0, COVER_W, COVER_H, pair[1])
    // big letter: print the first char on a scratch image, then blow the
    // glyph up ~6x into blocky pixels
    const letter = dir.charAt(0).toUpperCase()
    const glyph = image.create(7, 9)
    glyph.print(letter, 0, 0, 1)
    for (let gx = 0; gx < 7; gx++) {
        for (let gy = 0; gy < 9; gy++) {
            if (glyph.getPixel(gx, gy)) {
                img.fillRect(5 + gx * 7, 3 + gy * 3, 6, 2, pair[1])
            }
        }
    }
    return img
}

function redraw() {
    const bg = image.create(160, 120)
    bg.fill(BLACK)
    drawBanner(bg)

    if (entries.length == 0) {
        bg.print("No games installed.", 20, 56, 1)
        bg.print("Drop tarballs on a USB stick.", 8, 72, 13)
    } else {
        const page = Math.idiv(sel, PER_PAGE)
        // centered page arrows (the 'v' sits lower, centered too)
        if (page > 0) {
            bg.print("^", 78, 29, (tick * 3) % COLORS + 1)
        }
        if (page < pageCount - 1) {
            bg.print("v", 78, 111, (tick * 3 + 7) % COLORS + 1)
        }
        for (let i = 0; i < PER_PAGE; i++) {
            const idx = page * PER_PAGE + i
            if (idx >= entries.length) break
            const x = COL_X[i % 2]
            const y = ROW_Y[Math.idiv(i, 2)]
            if (idx == sel) {
                // selection box pulses through the palette with the banner
                bg.drawRect(x - 3, y - 3, COVER_W + 6, COVER_H + 6, 1)
                bg.drawRect(x - 2, y - 2, COVER_W + 4, COVER_H + 4, tick % COLORS + 1)
            }
        }
    }
    scene.setBackgroundImage(bg)

    // covers as sprites so they draw over the background
    for (const s of coverSprites) s.destroy()
    coverSprites = []
    const page = Math.idiv(sel, PER_PAGE)
    for (let i = 0; i < PER_PAGE; i++) {
        const idx = page * PER_PAGE + i
        if (idx >= entries.length) break
        const x = COL_X[i % 2]
        const y = ROW_Y[Math.idiv(i, 2)]
        const buf = control.programImage(entries[idx])
        const img = buf ? image.ofBuffer(buf) : placeholder(idx, entries[idx])
        const s = sprites.create(img)
        s.setPosition(x + COVER_W / 2, y + COVER_H / 2)
        coverSprites.push(s)
    }
}

function move(dcol: number, drow: number) {
    if (!entries.length) return
    const page = Math.idiv(sel, PER_PAGE)
    let col = sel % 2
    let row = Math.idiv(sel % PER_PAGE, 2)
    let newPage = page
    col += dcol
    row += drow
    if (col < 0) col = 0
    if (col > 1) col = 1
    if (row < 0) {
        if (newPage > 0) { newPage--; row = 1 }
        else row = 0
    }
    if (row > 1) {
        if (newPage < pageCount - 1) { newPage++; row = 0 }
        else row = 1
    }
    let next = newPage * PER_PAGE + row * 2 + col
    if (next >= entries.length) next = entries.length - 1
    if (next != sel) {
        sel = next
        redraw()
    }
}

function launch() {
    if (!entries.length) return
    music.powerUp.play()
    control.runProgram(entries[sel])
    // never reached — runProgram exits this Game and the launcher
    // starts the requested one
}

controller.left.onEvent(ControllerButtonEvent.Pressed, function () { move(-1, 0) })
controller.right.onEvent(ControllerButtonEvent.Pressed, function () { move(1, 0) })
controller.up.onEvent(ControllerButtonEvent.Pressed, function () { move(0, -1) })
controller.down.onEvent(ControllerButtonEvent.Pressed, function () { move(0, 1) })
controller.A.onEvent(ControllerButtonEvent.Pressed, launch)
controller.B.onEvent(ControllerButtonEvent.Pressed, launch)
controller.player2.left.onEvent(ControllerButtonEvent.Pressed, function () { move(-1, 0) })
controller.player2.right.onEvent(ControllerButtonEvent.Pressed, function () { move(1, 0) })
controller.player2.up.onEvent(ControllerButtonEvent.Pressed, function () { move(0, -1) })
controller.player2.down.onEvent(ControllerButtonEvent.Pressed, function () { move(0, 1) })
controller.player2.A.onEvent(ControllerButtonEvent.Pressed, launch)
controller.player2.B.onEvent(ControllerButtonEvent.Pressed, launch)

// banner/selection animation
game.onUpdateInterval(200, function () {
    tick = (tick + 1) % 900
    redraw()
})

redraw()
