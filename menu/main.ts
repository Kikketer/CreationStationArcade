// Creation Station Arcade menu — "MadeArcade".
// Runs on the native (hw---vm) runtime — uses the control.* game hooks
// (programList / programImage / runProgram) that only exist there.
//
// Layout on the 160x120 screen:
//   - Banner (top ~30px): animated rainbow "MadeArcade" title over a
//     cycling palette strip. Redrawn on every page.
//   - Grid: 2x2 pages of 60x34 cover images. D-pad moves the selection,
//     down past the bottom row flips to the next page. Up/down arrows
//     hint that more pages exist in that direction.
//   - A/B launches the selected game via control.runProgram (which exits
//     this Game; the launcher loop starts the pick and returns here on
//     exit).

const SELF = "Menu"
const PER_PAGE = 4
const COL_X = [10, 90]   // two 60px-wide columns
const ROW_Y = [34, 72]   // two 34px-tall rows
const COVER_W = 60
const COVER_H = 34

let entries: string[] = []
for (const e of control.programList()) {
    if (e != SELF) {
        entries.push(e)
    }
}
const pageCount = Math.max(1, Math.ceil(entries.length / PER_PAGE))

let sel = 0
let tick = 0
let coverSprites: Sprite[] = []

function drawBanner(bg: Image) {
    // palette strip: 16 segments, hue drifts each tick
    for (let i = 0; i < 16; i++) {
        bg.fillRect(i * 10, 0, 10, 4, (i + tick) % 15 + 1)
    }
    // title, one color per letter, marching the other way
    const title = "MadeArcade"
    const x0 = 50  // ~10 chars * 6px centered-ish
    for (let i = 0; i < title.length; i++) {
        bg.print(title.charAt(i), x0 + i * 6, 10, (tick + title.length - i) % 15 + 1)
    }
    bg.drawLine(0, 26, 159, 26, 12)
    bg.drawLine(0, 27, 159, 27, 0)
}

function placeholder(dir: string): Image {
    const img = image.create(COVER_W, COVER_H)
    img.fill(4)
    img.drawRect(0, 0, COVER_W, COVER_H, 13)
    // word-wrap the dir name into the box
    let line = ""
    let row = 6
    for (const word of dir.split("_")) {
        if ((line + word).length > 9) {
            img.print(line, 4, row, 15)
            line = ""
            row += 9
            if (row > COVER_H - 9) break
        }
        line = line ? line + "_" + word : word
    }
    if (line) img.print(line, 4, row, 15)
    return img
}

function redraw() {
    const bg = image.create(160, 120)
    bg.fill(1)
    drawBanner(bg)

    if (entries.length == 0) {
        bg.print("No games installed.", 20, 56, 15)
        bg.print("Drop tarballs on a USB stick.", 8, 72, 13)
    } else {
        const page = Math.idiv(sel, PER_PAGE)
        // page arrows: up if we can go back, down if more pages exist
        if (page > 0) {
            bg.print("^", 155, 30, (tick * 3) % 15 + 1)
        }
        if (page < pageCount - 1) {
            bg.print("v", 155, 110, (tick * 3 + 7) % 15 + 1)
        }
        for (let i = 0; i < PER_PAGE; i++) {
            const idx = page * PER_PAGE + i
            if (idx >= entries.length) break
            const x = COL_X[i % 2]
            const y = ROW_Y[Math.idiv(i, 2)]
            if (idx == sel) {
                // selection box pulses through the palette with the banner
                bg.drawRect(x - 2, y - 2, COVER_W + 4, COVER_H + 4, tick % 15 + 1)
                bg.drawRect(x - 3, y - 3, COVER_W + 6, COVER_H + 6, 15)
            }
        }
    }
    scene.setBackgroundImage(bg)

    // covers as sprites so the selection box draws under them
    for (const s of coverSprites) s.destroy()
    coverSprites = []
    const page = Math.idiv(sel, PER_PAGE)
    for (let i = 0; i < PER_PAGE; i++) {
        const idx = page * PER_PAGE + i
        if (idx >= entries.length) break
        const x = COL_X[i % 2]
        const y = ROW_Y[Math.idiv(i, 2)]
        const buf = control.programImage(entries[idx])
        const img = buf ? image.ofBuffer(buf) : placeholder(entries[idx])
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
