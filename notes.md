# Recovery notes for single-native-arcade

## Temporarily disable the autologin launcher

Log in as an admin (or via SSH) and reset the `pi` user's shell:

```bash
sudo usermod -s /bin/bash pi
```

After fixing things, set it back to the runtime launcher:

```bash
sudo usermod -s /home/pi/CreationStationArcade/launcher.sh pi
```

## Kill the running game and launcher

```bash
sudo pkill -9 -f "games/[^/]+/Game"
sudo pkill -9 -f launcher.sh
sudo pkill -9 -f single-native-launch.sh
```

Then clear the screen:

```bash
clear
```

## Test a native game from a console

```bash
cd /home/pi/CreationStationArcade/games/YourGame
export SDL_VIDEODRIVER=kmsdrm
export SDL_AUDIODRIVER=alsa
./Game -f
```

If you get permission errors on `/dev/dri`, make sure the arcade user is in the `video` group and reboot.

## Re-run the installer

```bash
cd /home/pi/CreationStationArcade
sudo bash install/single-native-arcade-setup.sh --game=YourGame
```
