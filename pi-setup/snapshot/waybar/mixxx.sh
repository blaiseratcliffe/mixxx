#!/bin/bash

if ! pgrep -x "mixxx" > /dev/null
then
    swaymsg exec "env QT_QPA_PLATFORM=xcb /home/pi/src/mixxx-cdj/build/mixxx --resource-path /usr/share/mixxx"
fi
