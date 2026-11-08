# Example USB drive

This shows a ready-to-use USB stick layout. **Copy the contents of this
folder to the root of a USB drive** (i.e. the drive ends up with an
`arcade-games/` folder at its root), plug it into the arcade, and the games
install automatically — no reboot needed.

```
USB drive root
└── arcade-games/        everything inside is installed into ~/arcade-games
    ├── MyGame.js        a compiled MakeCode Arcade game
    ├── MyGame.png       its cover image (optional)
    ├── MyGame.gif       animated cover (optional)
    ├── MyGame.json      metadata overrides: {"name":..,"author":..,"playerCount":..} (optional)
    ├── games.json       the game list (optional — regenerated if absent)
    └── config.json      per-machine settings, e.g. title screen text (optional)
```

The `arcade-games/` folder here is a real library as an example — delete the
sample games and drop in your own.

Loose files also work without the folder: put `MyGame.js` (plus optional
`MyGame.png`/`.gif`/`.json` siblings) directly at the drive root.

See the main `readme.md` → "Putting Games On The Arcade" for details.
