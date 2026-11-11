# Creation Station Arcade

Creation Station Arcade turns a small computer (usually a Raspberry Pi) into a dedicated arcade cabinet that boots straight into games you make with [MakeCode Arcade](https://makecode.com/arcade).

You build a game in MakeCode Arcade in your browser, export it, drop the file onto the arcade, and reboot. The arcade boots up, hides all the normal computer stuff, and shows only your game on the screen. Plug in a USB gamepad or wire up arcade buttons, and you've got a real arcade machine.

!!! success "Our recommended setup: an older x86 PC running Chromium"
    The best, go-forward configuration is an **older x86 desktop or mini PC** running one of the Chromium flavors ([menu](chromium-kiosk.md) or [single-game](single-game-kiosk.md)) with **USB controllers**. Even modest machines run MakeCode games in Chromium just fine — our slowest tested box that runs well is an **Intel Core i3-8100 with UHD 630 graphics and 8 GB of RAM**, the kind of office PC you can find used for very little.

    If you insist on **GPIO-wired buttons**, a **Raspberry Pi 5 with Chromium** is a good bet.

    Running on older or weaker hardware (Pi 3, Pi Zero 2 W) is possible, but go with the **Native** or **ELF** flavors at that point.

## Recommendations by hardware

| Your hardware | Use | Controls |
| --- | --- | --- |
| Anything less powerful than a Raspberry Pi 5 (Pi 3, Pi 4, Pi Zero 2 W) | [Native](multi-native-arcade.md) or [ELF](elf-menu.md) flavors | GPIO buttons or USB |
| Raspberry Pi 5 | [Chromium](chromium-kiosk.md) flavors | GPIO is possible and useful, or USB |
| Any reasonable x86 PC (i3-8100-class or better) | [Chromium](chromium-kiosk.md) flavors | USB controllers |

## What flavor do I build?

There isn't just one arcade. There are **six** flavors, because the same MakeCode Arcade games can run several different ways, and each way fits different hardware and different goals. You pick the flavor *before* you start, because each one lives on its own branch of the project and has its own setup steps.

!!! tip "Not sure which one?"
    Head to the [Pick Your Arcade](pick-your-arcade.md) guide. It asks a few plain questions and points you at the right page.

The six flavors:

| Flavor | Best hardware | Menu? | What runs the game |
| --- | --- | --- | --- |
| [ELF Menu Arcade](elf-menu.md) | Raspberry Pi 3 | Yes — a menu of games | Raw `.elf` files (the "close to what MakeCode intended" path) |
| [Pi 3 / Pi Zero Single-Game ELF](pi3-elf-kiosk.md) | Raspberry Pi 3 or Pi Zero | No — one game only | A single raw `.elf` file |
| [Chromium Kiosk (Menu)](chromium-kiosk.md) | An older x86 PC (recommended) or a Raspberry Pi 5 | Yes — a menu of games | Games in a fullscreen Chromium browser |
| [Chromium Single-Game](single-game-kiosk.md) | An older x86 PC (recommended) or a Raspberry Pi 5 | No — one game only | One game in a fullscreen Chromium browser |
| [Multi-Native Arcade](multi-native-arcade.md) | 64-bit Raspberry Pi weaker than a Pi 5 (3/4/Zero 2 W) | Yes — a menu of games | Native `Game` programs (no browser) |
| [Native Application Single-Game](single-native-arcade.md) | 64-bit Raspberry Pi weaker than a Pi 5 (3/4/Zero 2 W) | No — one game only | A native `Game` program (no browser) |

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
