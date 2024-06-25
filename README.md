A fork of [CogentRedTester/mpv-changerefresh](https://github.com/CogentRedTester/mpv-changerefresh) with extra changes from [Sevardon-Code](https://github.com/Sevardon-Code/mpvshim-changerefresh) and [WhonderWy](https://github.com/WhonderWy/mpv-changerefresh), and then torn to shreds by me to add HDR support too.

# change-refresh

## Installation

This script uses WindowsDisplayManager to change the refresh rate and HDR status of the display that the mpv window is currently open in.

Open PowerShell as administrator and run
```
Set-ExecutionPolicy Unrestricted
Install-Module -Name WindowsDisplayManager
```

Then copy the .lua and .conf files into your scripts and script-opts directories. These should be in `%AppData%\mpv`, `%AppData%\jellyfin-mpv-shim`, or `%AppData%\mpv.net` depending on how you installed MPV.

## Behaviour
When the script is activated it will automatically detect the refresh rate of the current video and attempt to change the display
to the closest rate on the whitelist. The script will keep track of the original refresh rate of the monitor and revert when mpv exits.

## Rate Whitelist
If the display does not support the specified resolution or refresh rate it will silently fail
If the video refresh rate does not match any on the whitelist it will pick the next highest.
If the video fps is higher than any on the whitelist it will pick the highest available
The whitelist is specified via the script-opt `rates`. Valid rates are separated via semicolons, do not include spaces and list in ascending order.

    changerefresh-rates="23;24;30;60"

### Custom Rates
You can also set a custom display rate for individual video rates using a hyphen:

    changerefresh-rates="23;24;25-50;30;60"

This will change the display to 23, 24, and 30 fps when playing videos in those same rates, but will change the display to 50 fps when
playing videos in 25 Hz

## Monitor Detection
The script automatically detects which monitor the mpv window is currently loaded on, and will save the original resolution and rate to revert to.

Note that if the mpv window is lying across multiple displays it may not save the original refresh rate of the correct display.

## Configuration
See `changerefresh.conf` for the full options list, this file can be placed into the script-opts folder inside the mpv config directory.
