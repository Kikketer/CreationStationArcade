# Pick Your Arcade

Not sure which flavor of Creation Station Arcade to build? Answer the questions below and follow the arrow. Each one sends you to a full step-by-step guide.

## The short version

!!! question "Do you want a menu of games, or just one game?"

    - **A menu of games** → you want one of the two "menu" flavors below.
    - **Just one game** (a dedicated cabinet for a single game) → you want one of the three "single-game" flavors below.

!!! question "Which computer are you using?"

    - **Raspberry Pi 3** → the ELF flavors work great (they need a specific kernel detail the Pi 3 still has).
    - **Raspberry Pi Zero or Zero 2 W** → see the single-game options; the Pi Zero's one USB port limits what you can plug in.
    - **Raspberry Pi 5** → use a Chromium or Native flavor. The ELF flavors do **not** work on the Pi 5 (see the gotcha note below).
    - **A regular PC (x86, 64-bit)** → Chromium or Native flavors.

## Decision tree

```
Start here
   │
   ├── Got a Raspberry Pi 3 and want a MENU of games?
   │      → ELF Menu Arcade  ............ [elf-menu.md]
   │
   ├── Got a Raspberry Pi 3 or Pi Zero and want ONE game?
   │      → Pi 3 / Pi Zero Single-Game ELF  ... [pi3-elf-kiosk.md]
   │
   ├── Got a Raspberry Pi 5 (or a PC) and want a MENU of games?
   │      → Chromium Kiosk (Menu)  ........ [chromium-kiosk.md]
   │
   ├── Got a Raspberry Pi 5 (or a PC) and want ONE game,
   │   and you're fine running it in a browser?
   │      → Chromium Single-Game  ......... [single-game-kiosk.md]
   │
   └── Got a 64-bit Raspberry Pi (3/4/5/Zero 2 W) or a 64-bit PC
       and want ONE game running as fast as possible (no browser)?
              → Native SDL Single-Game  ... [single-native-arcade.md]
```

## The gotcha that picks the flavor for you

The two **ELF** flavors (the menu and the single-game ELF) only work on a **Raspberry Pi 3 or Pi Zero**. They depend on a line called `Hardware` that the Pi reports about itself, and newer Pi 5 software removed that line. You can't fix it by changing settings — it's a software-version thing.

So:

- If you have a **Pi 5**, cross both ELF options off your list. Use Chromium or Native.
- If you have a **Pi 3 or Pi Zero**, the ELF options are the lightest, fastest ones and a great default.

!!! warning "Don't update the Pi 3's software after you set it up"
    If you run the normal "update everything" command on a Pi 3, it can pull down the newer kernel that removes the `Hardware` line, and your ELF arcade will stop booting. The ELF setup guides tell you exactly which commands are safe. The short version: **don't run `sudo apt upgrade`** on an ELF arcade. See the [ELF Menu guide](elf-menu.md) for the full explanation.

## A note on GPIO buttons

"GPIO" means the row of metal pins on top of a Raspberry Pi that you can wire real arcade buttons to.

- On a **Pi 3 / Pi Zero**, you can wire real buttons to the GPIO pins for player controls and a reset button.
- On a **Pi 5**, the old way of talking to those pins (`wiringPi`) is gone, so GPIO button wiring for the ELF flavors is basically dead. USB gamepads and USB zero-delay encoders still work fine — use a Chromium or Native flavor with USB controllers.

## Still stuck?

If you just want the simplest possible first arcade:

- You have a **Pi 3** → [ELF Menu Arcade](elf-menu.md). It's the closest to what MakeCode intended and gives you a menu of games.
- You have a **Pi 5** → [Chromium Kiosk (Menu)](chromium-kiosk.md). It gives you a menu of games and uses the full MakeCode simulator in the browser.
