# Creation Station Arcade

Creation Station Arcade turns a small computer (usually a Raspberry Pi) into a dedicated arcade cabinet that boots straight into games you make with [MakeCode Arcade](https://makecode.com/arcade).

You build a game in MakeCode Arcade in your browser, export it, drop the file onto the arcade, and reboot. The arcade boots up, hides all the normal computer stuff, and shows only your game on the screen. Plug in a USB gamepad or wire up arcade buttons, and you've got a real arcade machine.

## What flavor do I build?

There isn't just one arcade. There are **five** flavors, because the same MakeCode Arcade games can run several different ways, and each way fits different hardware and different goals. You pick the flavor *before* you start, because each one lives on its own branch of the project and has its own setup steps.

!!! tip "Not sure which one?"
    Head to the [Pick Your Arcade](pick-your-arcade.md) guide. It asks a few plain questions and points you at the right page.

The five flavors:

| Flavor | Best hardware | Menu? | What runs the game |
| --- | --- | --- | --- |
| [ELF Menu Arcade](elf-menu.md) | Raspberry Pi 3 | Yes — a menu of games | Raw `.elf` files (the "close to what MakeCode intended" path) |
| [Pi 3 / Pi Zero Single-Game ELF](pi3-elf-kiosk.md) | Raspberry Pi 3 or Pi Zero | No — one game only | A single raw `.elf` file |
| [Chromium Kiosk (Menu)](chromium-kiosk.md) | Raspberry Pi 5 or a regular PC | Yes — a menu of games | Games in a fullscreen Chromium browser |
| [Chromium Single-Game](single-game-kiosk.md) | Raspberry Pi 5 or a regular PC | No — one game only | One game in a fullscreen Chromium browser |
| [Native SDL Single-Game](single-native-arcade.md) | 64-bit Raspberry Pi (3/4/5/Zero 2 W) or a 64-bit PC | No — one game only | A native `Game` program (no browser, fastest) |

## How these guides are written

These guides assume you can:

- Use a web browser.
- Copy and paste text into a terminal.
- Plug things into a Raspberry Pi.

You do **not** need to know what "git", "branches", "SSH", or "systemd" mean. Where one of those words would show up, you'll get a single copy-paste command instead, with a one-line plain-language note about what it does. If a word is unavoidable, it's explained right there.

Every installation guide follows the same shape:

1. **What this is / who it's for** — so you know you're on the right page.
2. **What you'll need** — a checklist of hardware and tools before you start.
3. **The walkthrough** — numbered steps from "I just unboxed the parts" to "I'm playing a game."
4. **If something goes wrong** — fixes for the known gotchas.

Ready? Start with [Pick Your Arcade](pick-your-arcade.md).
