#!/bin/sh
# Any long running command
# MUST be followed by '&'
# Uncomment lines to enable them

# xset s noblank
# xset s off
# xset -dpms
if [ -f ~/.Xresources ]; then
    xrdb -merge ~/.Xresources
fi
# compton &
# fbpanel &
# spacefm --desktop &
