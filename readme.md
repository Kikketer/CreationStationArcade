# Creation Station Arcade

How to setup a Raspberry PI 3:

1. Install the 32bit Lite version of the Raspberry PI OS (Trixie was last tested)
2. Install git: `sudo apt install git`
3. After booting it up copy over everything in this repo (or git clone)
4. Clone the McAirpos repo `git clone https://github.com/Vegz78/McAirpos.git`
5. Copy the `/sd` directory to the root: `sudo cp -r ~/McAirpos/McAirpos/MakeCode/sd /`
6. Change permissions on that directory: `sudo chown -R pi /sd && sudo chgrp -R pi /sd && sudo chmod -R 755 /sd`
7. Make another user, this will be the "admin" user for the raspberry pi so you can admin the machine
8. Set the login for the `pi` user to use the `./launcher.sh` instead of bash, this will just force that user to fire up the arcade loop.

## Known Issues

- Raspberry PI 3 is the only modern device that works due to "Hardweare" line needed in the `/proc/cpuinfo` which is generally useless but the ELF files demand it to be there.

> The Pi 3 works because it still ships a slightly older 6.x kernel point-release that still contains the “Hardware” line.
> The Pi 5 image you flashed already carries a newer 6.x point-release in which the Raspberry Pi Foundation deliberately deleted that line (they got tired of every Pi reporting BCM2835 and confusing users).
> So on the Pi 5 the ELF aborts, while on the Pi 3 it starts—even though both run the same 32-bit Trixie Lite OS.
> Once your Pi 3 updates to the same kernel revision as the Pi 5, it will also lose the line and fail in exactly the same way.

BTW that sounds like a horrible day, so let's get a copy of that OS and keep it forever.

- `wiringPi` is dead on Raspberry Pi 5

This means that the GPIO is basically useless and can't be used for the gaming machine.
