// Creation Station Arcade menu.
// Runs on the native (hw---vm) runtime — uses the control.* game hooks
// (programList / programImage / runProgram) that only exist there.
// Up/down picks a game, A (or B) launches it. The launcher loop outside
// brings this menu back whenever a game exits.

const SELF = "Menu"
const MAX_ROWS = 6
const LIST_W = 104
const ROW_H = 16

let entries: string[] = []
for (const e of control.programList()) {
    if (e != SELF) {
        entries.push(e)
    }
}

let sel = 0
let coverSprite: Sprite = null

function redraw() {
    const bg = image.create(160, 120)
    bg.fill(1)
    bg.print("ARCADE", 4, 3, 14)
    bg.drawLine(0, 12, LIST_W, 12, 12)

    if (entries.length == 0) {
        bg.print("No games installed.", 4, 24, 15)
        bg.print("Drop tarballs on a", 4, 40, 13)
        bg.print("USB stick.", 4, 52, 13)
    } else {
        // keep the selection inside a scrolling window
        let start = sel - (MAX_ROWS - 1)
        if (start < 0) start = 0
        if (start > entries.length - MAX_ROWS) {
            start = Math.max(0, entries.length - MAX_ROWS)
        }
        for (let i = 0; i < Math.min(MAX_ROWS, entries.length); i++) {
            const idx = start + i
            const y = 18 + i * ROW_H
            if (idx == sel) {
                bg.fillRect(0, y - 2, LIST_W, ROW_H - 2, 5)
                bg.print("> " + entries[idx], 2, y + 1, 15)
            } else {
                bg.print("  " + entries[idx], 2, y + 1, 13)
            }
        }
    }
    scene.setBackgroundImage(bg)

    // cover art for the selected game (cover.img / cover.png next to it)
    if (coverSprite) {
        coverSprite.destroy()
        coverSprite = null
    }
    if (entries.length) {
        const buf = control.programImage(entries[sel])
        if (buf) {
            coverSprite = sprites.create(image.ofBuffer(buf))
            coverSprite.setPosition(132, 60)
        }
    }
}

function move(d: number) {
    if (!entries.length) return
    sel = (sel + d + entries.length) % entries.length
    redraw()
}

function launch() {
    if (!entries.length) return
    music.powerUp.play()
    control.runProgram(entries[sel])
    // never reached — runProgram exits this Game and the launcher
    // starts the requested one
}

controller.up.onEvent(ControllerButtonEvent.Pressed, function () { move(-1) })
controller.down.onEvent(ControllerButtonEvent.Pressed, function () { move(1) })
controller.A.onEvent(ControllerButtonEvent.Pressed, launch)
controller.B.onEvent(ControllerButtonEvent.Pressed, launch)
controller.player2.up.onEvent(ControllerButtonEvent.Pressed, function () { move(-1) })
controller.player2.down.onEvent(ControllerButtonEvent.Pressed, function () { move(1) })
controller.player2.A.onEvent(ControllerButtonEvent.Pressed, launch)
controller.player2.B.onEvent(ControllerButtonEvent.Pressed, launch)

redraw()
