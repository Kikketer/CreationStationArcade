# Pick Your Arcade

Not sure which flavor of Creation Station Arcade to build? Answer the questions below and follow the arrow. Each one sends you to a full step-by-step guide.

## The short version

!!! question "Do you want a menu of games, or just one game?"

    - **A menu of games** → you want one of the three "menu" flavors below.
    - **Just one game** (a dedicated cabinet for a single game) → you want one of the three "single-game" flavors below.

!!! question "Which computer are you using?"

    - **Anything less powerful than a Raspberry Pi 5** (Pi 3, Pi 4, Pi Zero 2 W), especially with GPIO buttons → use a **Native** or **ELF** flavor. (ELF only works on a Pi 3 / Pi Zero — see the gotcha note below.)
    - **Raspberry Pi 5** → use a **Chromium** flavor. GPIO buttons are possible and useful here. The ELF flavors do **not** work on the Pi 5.
    - **Any reasonable x86 PC** (i3-8100-class or better) → use a **Chromium** flavor with **USB controllers**. This is our recommended setup.

!!! success "Our recommendation"
    An **older x86 PC running Chromium** with USB controllers is the best, go-forward configuration. Even an i3-8100 with built-in UHD 630 graphics runs MakeCode games in Chromium just fine. If you insist on GPIO buttons, a **Raspberry Pi 5 with Chromium** is a good bet. On older hardware, go with Native or ELF.

!!! note "Native is not the fastest"
    Native `Game` programs skip the browser, but they run your game in an interpreter. Our compiler testing found they can be **10–40x slower** than the same game in Chromium. Choose Native for weak hardware, not for speed.

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
   ├── Got a Raspberry Pi 5 or an x86 PC and want a MENU of games
   │   running the full MakeCode simulator? (recommended)
   │      → Chromium Kiosk (Menu)  ........ [chromium-kiosk.md]
   │
   ├── Got a 64-bit Pi weaker than a Pi 5 and want a MENU
   │   of games without a browser?
   │      → Multi-Native Arcade  .......... [multi-native-arcade.md]
   │
   ├── Got a Raspberry Pi 5 (or a PC) and want ONE game,
   │   and you're fine running it in a browser?
   │      → Chromium Single-Game  ......... [single-game-kiosk.md]
   │
   └── Got a 64-bit Pi weaker than a Pi 5 (3/4/Zero 2 W)
       and want ONE game without a browser?
              → Native Application Single-Game  ... [single-native-arcade.md]
```

## The gotcha that picks the flavor for you

The two **ELF** flavors (the menu and the single-game ELF) only work on a **Raspberry Pi 3 or Pi Zero**. They depend on a line called `Hardware` that the Pi reports about itself, and newer Pi 5 software removed that line. You can't fix it by changing settings — it's a software-version thing.

So:

- If you have a **Pi 5**, cross both ELF options off your list. Use Chromium or Native.
- If you have a **Pi 3 or Pi Zero**, the ELF options are the lightest ones and a great default.

!!! warning "Don't update the Pi 3's software after you set it up"
    If you run the normal "update everything" command on a Pi 3, it can pull down the newer kernel that removes the `Hardware` line, and your ELF arcade will stop booting. The ELF setup guides tell you exactly which commands are safe. The short version: **don't run `sudo apt upgrade`** on an ELF arcade. See the [ELF Menu guide](elf-menu.md) for the full explanation.

## A note on GPIO buttons

"GPIO" means the row of metal pins on top of a Raspberry Pi that you can wire real arcade buttons to.

- On a **Pi 3 / Pi Zero**, you can wire real buttons to the GPIO pins for player controls and a reset button.
- On a **Pi 5**, the old way of talking to those pins (`wiringPi`) is gone, so the ELF flavors can't use GPIO buttons. The **Chromium** flavors support GPIO on the Pi 5 (`--gpio-controllers`), and that's the pairing we recommend if you want wired buttons.
- On an **x86 PC** there are no GPIO pins — use USB gamepads or a USB zero-delay encoder.

## Still stuck?

If you just want the simplest possible first arcade:

- You have a **Pi 3** → [ELF Menu Arcade](elf-menu.md). It's the closest to what MakeCode intended and gives you a menu of games.
- You have a **Pi 5** → [Chromium Kiosk (Menu)](chromium-kiosk.md). It gives you a menu of games and uses the full MakeCode simulator in the browser.
- You have (or can find) an **older x86 PC** → [Chromium Kiosk (Menu)](chromium-kiosk.md) with USB controllers. This is our recommended setup.
