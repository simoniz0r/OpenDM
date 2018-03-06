# OpenDM

![screenshot](/screenshot.png)

WIP - A simple GUI Display Manager written entirely in bash that uses xinit to start X sessions

# Dependencies

xinit, yad or qarma

# Installation/Removal

To install:

```
git clone https://github.com/simoniz0r/OpenDM.git
cd ./OpenDM
sudo make install
```

To uninstall:

```
cd /path/to/cloned/OpenDM
sudo make uninstall
```

# Using OpenDM

After install, to use OpenDM, just add the following to the default $SHELL's profile file (~/.bash_profile, ~/.zprofile, etc) to have OpenDM autostart on tty1 after login:

```
export OpenDM_TTY="tty1"

if [ -f "$HOME/.config/opendm/.opendmstart" ]; then
    . ~/.config/opendm/.opendmstart
fi
```

Instructions will be updated later when OpenDM is completed.
