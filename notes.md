To kill the launcher and running elf, use SSH in and:

```
sudo pkill -9 -f launcher.sh
sudo pkill -9 -f .elf
```

then you have to clear the screen `clear`

To sync:

```
rsync -a --no-perms --no-owner --no-group --delete --exclude ".git" --exclude "arcade.log" "/home/pi/CreationStationArcade-src/" "/home/pi/CreationStationArcade/"
```
