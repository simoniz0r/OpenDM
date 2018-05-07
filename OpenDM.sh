#!/bin/bash
# Author: simonizor
# License: MIT
# Description: A simple Display Manager that uses xinit and qarma to launch a session select GUI
# Description: Also provides configuration options and a logout menu

RUNNING_DIR="$(dirname $(readlink -f $0))"
if [ -z "$OPENDM_TTY" ]; then
    OPENDM_TTY="tty1"
fi

# Start function to check if $DISPLAY is set and running on $OPENDM_TTY; use startx if $DISPLAY is not set and running on $OPENDM_TTY
function startchecks() {
    if [ -z "$DISPLAY" ] && [ "$(ps ax | grep $$ | grep -v grep | awk '{ print $2 }')" = "$OPENDM_TTY" ]; then
        if [ ! -d "/tmp/opendm/$USER/$OPENDM_TTY" ]; then
            mkdir -p /tmp/opendm/"$USER"/"$OPENDM_TTY"
        fi
        if [ -f "$RUNNING_DIR/configs/.opendminitrc" ]; then
            startx "$RUNNING_DIR"/configs/.opendminitrc "--session-select" > ~/.xsession-errors 2>&1
        elif [ -f "$HOME/.config/opendm/.opendminitrc" ]; then
            startx "$HOME"/.config/opendm/.opendminitrc "--session-select" > ~/.xsession-errors 2>&1
        else
            echo '""$HOME"/.config/opendm/.opendminitrc does not exist!' 
            echo 'Please see https://github.com/simoniz0r/OpenDM/.opendminitrc for an example.'
            exit 1
        fi
    # If $DISPLAY is set, just run OpenDM's arguments without using startx
    elif [ ! -z "$DISPLAY" ]; then
        opendmconfig
    # Exit if not running on $OPENDM_TTY
    else
        echo "OPENDM_TTY is set to $OPENDM_TTY; currently running on $(ps ax | grep $$ | grep -v grep | awk '{ print $2 }')."
        echo "Running OpenDM on multiple TTYs at the same time is currently not supported."
        echo "Please edit your shell's profile to change the 'export OPENDM_TTY=' line if you wish to use a different TTY."
        exit 1
    fi
}

function generatesessionlist() {
    if [ ! -d "/tmp/opendm/$USER/$OPENDM_TTY" ]; then
        mkdir -p /tmp/opendm/"$USER"/"$OPENDM_TTY"
    fi
    # Run a for loop on ~/.config/opendm/xsessions that checks for enabled sessions
    # If OPENDM_DEFAULT_SESSION is set in variables.conf and session file matching name exists, list default session first
    if [ -f "$HOME/.config/opendm/lastsession" ]; then
        OPENDM_DEFAULT_SESSION="$(cat ~/.config/opendm/lastsession)"
    fi
    SESSION_LIST="$( if [ ! -z "$OPENDM_DEFAULT_SESSION" ] && [ -f "$HOME/.config/opendm/xsessions/$OPENDM_DEFAULT_SESSION" ]; then
        echo -n "$OPENDM_DEFAULT_SESSION|"
    else
        # Set default session to random numbers if it doesn't exist to avoid errors
        OPENDM_DEFAULT_SESSION="${RANDOM}${RANDOM}${RANDOM}"
    fi
    # For loop that looks for enabled session files and lists them by name
    for sessionfile in $(\dir -C -w 1 "$HOME"/.config/opendm/xsessions); do
        case "$sessionfile" in
            # Default session was already added to list, so we do nothing when it is found again
            "$OPENDM_DEFAULT_SESSION")
                sleep 0
                ;;
            *)
                # Add each found session to the list
                echo -n "$sessionfile|"
                ;;
        esac
    done
    # Add Settings and Other to list
    echo -n "Settings|"
    echo -n "Other...")"
}

# function that displays session choice and password entry.
function supasswordcheck() {
    SESSION_CHOICE="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms --cancel-label="Shutdown" \
    --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>Enter password for $USER<br/></h2>" \
    --add-combo="" --combo-values=$SESSION_LIST --add-password="")"
    case $? in
        1)
            logoutselect "SHUTDOWN"
            ;;
    esac
    SU_PASSWORD_CHECK="$(echo $SESSION_CHOICE | cut -f2 -d'|')"
    SESSION_CHOICE="$(echo $SESSION_CHOICE | cut -f1 -d'|')"
    # use su -c true "$USER" to check password entry
    if ! echo "$SU_PASSWORD_CHECK" | su -c true "$USER"; then
        qarma --title="OpenDM" --error --text="Incorrect password for $USER!"
        exit 1
    fi
}

# Function that provides session selection based on files in ~/.config/opendm/xsessions and runs 'exec' on the user's choice
function sessionselect() {
    generatesessionlist
    # Use qarma to provide a GUI with a list of enabled sessions, OpenDM's settings menu, and ability to launch non listed session through 'Other...'
    if [ -f "/tmp/opendm/$USER/$OPENDM_TTY/lastsession" ] || [ -z "$OPENDM_DEFAULT_SESSION" ]; then
        OPENDM_AUTOSTART_DEFAULT="FALSE"
    fi
    if [ "$OPENDM_PASSWORD_CHECK" = "TRUE" ]; then
        type openbox > /dev/null 2>&1 && ! pgrep openbox && [ -f "$HOME/.config/opendm/.openboxrc.xml" ] && openbox --config-file ~/.config/opendm/.openboxrc.xml & disown
        supasswordcheck || exit 0
    elif [ ! "$OPENDM_AUTOSTART_DEFAULT" = "TRUE" ]; then
        type openbox > /dev/null 2>&1 && ! pgrep openbox && [ -f "$HOME/.config/opendm/.openboxrc.xml" ] && openbox --config-file ~/.config/opendm/.openboxrc.xml & disown
        SESSION_CHOICE="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms --cancel-label="Logout" \
        --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>$USER@$HOST<br/></h2>" \
        --add-combo="" --combo-values=$SESSION_LIST)"
    else
        if [ -f "$HOME/.config/opendm/lastsession" ]; then
            SESSION_CHOICE="$(cat ~/.config/opendm/lastsession)"
        else
            SESSION_CHOICE="$OPENDM_DEFAULT_SESSION"
        fi
    fi
    # Go to logoutselect function if no choice was made; "LOGOUT" tells logoutselect function not to provide option to exit session and to return to sessionselect if no logout choice is made
    if [ -z "$SESSION_CHOICE" ]; then
        logoutselect "LOGOUT"
    else
        case "$SESSION_CHOICE" in
            Settings)
                # Run OpenDM's config with "sessionselect" so that config knows to come back to sessionselect after user has finished
                touch /tmp/opendm/"$USER"/"$OPENDM_TTY"/sessionselect
                opendmconfig
                ;;
            Other...)
                othersession
                ;;
            *)
                # Source variables stored in chosen session file
                . "$HOME"/.config/opendm/xsessions/"$SESSION_CHOICE"
                # source xprofile if it exists
                [ -f "/etc/xprofile" ] && . /etc/xprofile
                [ -f "$HOME/.xprofile" ] && . ~/.xprofile
                # source autostart script for chosen session if it is set in the session file and exists
                if [ ! -z "$SESSION_AUTOSTART" ] && [ -f "$HOME/.config/opendm/autostart/$SESSION_AUTOSTART" ]; then
                    . "$HOME"/.config/opendm/autostart/"$SESSION_AUTOSTART"
                fi
                # Place the $SESSION_EXIT command in ~/.config/opendm/.currentsession"$OPENDM_TTY" so we know how to exit the chosen session in the logout menu
                echo "$SESSION_CHOICE" > ~/.config/opendm/lastsession
                cp "$HOME"/.config/opendm/xsessions/"$SESSION_CHOICE" /tmp/opendm/"$USER"/"$OPENDM_TTY"/currentsession
                # Run 'exec' on chosen session so that Xorg will exit when chosen session exits
                type openbox > /dev/null 2>&1 && openbox --exit
                $SESSION_START
                ;;
        esac
    fi
}

# Provides a simple qarma entry box to run 'exec' on commands not listed in sessionselect
# Can be used for other DEs/WMs or even for running something like a browser quick without launching a whole DE/WM along with it
function othersession() {
    OTHER_CHOICE="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --entry --text="Enter a command to run" --entry-text="xterm")"
    if [ -z "$OTHER_CHOICE" ]; then
        sessionselect
        exit 0
    else
        touch /tmp/opendm/exit
        $OTHER_CHOICE
    fi
}

# Provides a logout menu during sessionselect and can also be used to exit/logout/restart/shutdown the PC while the session is running
function logoutselect() {
        # Detect if ran from sessionselect so we know if the 'Exit' option should be shown or not
        case "$1" in
            SHUTDOWN)
                LOGOUT_CHOICE="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms --cancel-label="Back" \
                --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>Shutdown?<br/></h2>" \
                --add-combo="" --combo-values="Restart|Shutdown")"
                case $? in
                    1)
                        supasswordcheck
                        ;;
                esac
                ;;
            LOGOUT)
                LOGOUT_CHOICE="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms --cancel-label="Back" \
                --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>Logout?<br/></h2>" \
                --add-combo="" --combo-values="Logout|Restart|Shutdown")"
                ;;
        esac
        case "$LOGOUT_CHOICE" in
            Logout)
                # Create '/tmp/opendm/logout' for use along with provided example function for running OpenDM automatically on login and after session exit
                touch /tmp/opendm/exit
                exit 0
                ;;
            Restart)
                # Set default $OPENDM_REBOOT_CMD if doesn't exist
                if [ -z "$OPENDM_REBOOT_CMD" ]; then
                    OPENDM_REBOOT_CMD="systemctl reboot"
                fi
                touch /tmp/opendm/exit
                $OPENDM_REBOOT_CMD
                ;;
            Shutdown)
                # Set default $OPENDM_SHUTDOWN_CMD if doesn't exist
                if [ -z "$OPENDM_SHUTDOWN_CMD" ]; then
                    OPENDM_SHUTDOWN_CMD="systemctl poweroff"
                fi
                touch /tmp/opendm/exit
                $OPENDM_SHUTDOWN_CMD
                ;;
            *)
                # Exit if no input and currentsession file exists else return to sessionselect
                if [ -f "/tmp/opendm/$USER/$OPENDM_TTY/currentsession" ]; then
                    exit 0
                else
                    sessionselect
                fi
                ;;
        esac
}

# Use qarma to provide a list of OpenDM's config options and route user's choice to relevant function
function opendmconfig() {
    if [ ! -z "$1" ]; then
        CONFIG_SELECTION="$1"
    else
        CONFIG_SELECTION="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>Edit Settings<br/></h2>" --add-combo="" --combo-values='Sessions Editor|Add New Session|OpenDM Variables Editor|Autostart Files Editor|Xorg Log Viewer')"
    fi
    case "$CONFIG_SELECTION" in
        Enable*)
            togglesessions
            ;;
        Sessions*)
            editsessions
            ;;
        Add*)
            addsession
            ;;
        OpenDM*)
            editvariables
            ;;
        Autostart*)
            editautostart
            ;;
        Xorg*)
            xorglogviewer
            ;;
        *)
            # Exit if no input and currentsession file exists else return to sessionselect
            if [ -f "/tmp/opendm/$USER/$OPENDM_TTY/currentsession" ]; then
                exit 0
            else
                if [ -f "/tmp/opendm/$USER/$OPENDM_TTY/sessionselect" ]; then
                    rm -f /tmp/opendm/"$USER"/"$OPENDM_TTY"/sessionselect
                    sessionselect
                else
                    exit 0
                fi
            fi
            ;;
    esac
}

# Use qarma entry boxes to provide ability to add new sessions that aren't included by default
# $SESSION_NAME cannot contain spaces.  $SESSION_NAME, $SESSION_START, and $SESSON_EXIT are required
# $SESSION_AUTOSTART is optional; will create autostart script if it does not exist and make it executable
function addsession() {
    SESSION_NAME="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --entry --text="OpenDM<br><br>Enter the name of the session (no spaces)")"
    if [ -z "$SESSION_NAME" ]; then
        qarma --title="OpenDM" --error --text="No session name was entered!"
        opendmconfig
        exit 0
    elif [ -f "$HOME/.config/opendm/xsessions/$SESSION_NAME" ]; then
        qarma --title="OpenDM" --error --text="$SESSION_NAME already exists!"
        opendmconfig
        exit 0
    fi
    SESSION_START="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --entry --text="OpenDM<br><br>Enter the command used to start this session")"
    if [ -z "$SESSION_START" ]; then
        qarma --title="OpenDM" --error --text="No session start command was entered!"
        opendmconfig
        exit 0
    fi
    SESSION_EXIT="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --entry --text="OpenDM<br><br>Enter the command used to exit this session")"
    if [ -z "$SESSION_EXIT" ]; then
        qarma --title="OpenDM" --error --text="No session exit was entered!"
        opendmconfig
        exit 0
    fi
    echo "SESSION_START=\"$SESSION_START\"" > "$HOME"/.config/opendm/xsessions/"$SESSION_NAME"
    echo "SESSION_EXIT=\"$SESSION_EXIT\"" >> "$HOME"/.config/opendm/xsessions/"$SESSION_NAME"
    SESSION_AUTOSTART="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --entry --text="OpenDM<br><br>Enter the file name in $HOME/.config/autostart/ for $SESSION_NAME <br>Leave the inputbox blank for no autostart file" --entry-text="autostart.sh")"
    if [ ! -z "$SESSION_AUTOSTART" ]; then
        echo "SESSION_AUTOSTART=\"$SESSION_AUTOSTART\"" >> "$HOME"/.config/opendm/xsessions/"$SESSION_NAME"
        if [ ! -f "$HOME/.config/opendm/autostart/$SESSION_AUTOSTART" ]; then
            echo "#!/bin/sh" > "$HOME"/.config/opendm/autostart/"$SESSION_AUTOSTART"
            echo "# All long running commands must be followed with an '&' otherwise the session will not start!" >> "$HOME"/.config/opendm/autostart/"$SESSION_AUTOSTART"
            echo "# Ex:" >> "$HOME"/.config/opendm/autostart/"$SESSION_AUTOSTART"
            echo "# lxpanel &" >> "$HOME"/.config/opendm/autostart/"$SESSION_AUTOSTART"
            chmod +x "$HOME"/.config/opendm/autostart/"$SESSION_AUTOSTART"
        fi
    else
        echo "SESSION_AUTOSTART=\"\"" >> "$HOME"/.config/opendm/xsessions/"$SESSION_NAME"
    fi
    qarma --title="OpenDM" --info --text="$SESSION_NAME has been added!"
    opendmconfig
}

# List all sessions in ~/.config/opendm/xsessions and open up a qarma text editor box to allow editing of the chosen session
function editsessions() {
    # Do dir -a here so we see even disabled sessions
    SESSION_LIST="$(for sessionfile in $(\dir -a -C -w 1 "$HOME"/.config/opendm/xsessions | tail -n +3); do\
        echo -n "$sessionfile|"
    done)"
    # Remove last '|' from $SESSION_LIST to prevent blank entry
    SESSION_LIST="$(echo $SESSION_LIST | rev | cut -f2- -d'|' | rev)"
    SESSION_CHOICE="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>Edit Session<br/></h2>" --add-combo="" --combo-values=$SESSION_LIST)"
    # If no choice, return to config
    if [ -z "$SESSION_CHOICE" ]; then
        opendmconfig
    else
        # qarma text input box to edit chosen session
        EDITED_SESSION="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --text-info --checkbox="Save Changes" --editable --filename=""$HOME"/.config/opendm/xsessions/"$SESSION_CHOICE"")"
        case $? in
            1)
                # Return to config without saving if canceled
                opendmconfig "Sessions"
                ;;
            0)
                # If no text input, display error and return to config else save changes
                if [ -z "$EDITED_SESSION" ]; then
                    qarma --title="OpenDM" --error --text="No text was entered!"
                    opendmconfig "Sessions"
                else
                    echo "$EDITED_SESSION" > "$HOME"/.config/opendm/xsessions/"$SESSION_CHOICE"
                    qarma --title="OpenDM" --info --text="Changes to $SESSION_CHOICE have been saved!"
                    opendmconfig "Sessions"
                fi
                ;;
        esac
    fi
}

# Similar to session editor above, but with autostart scripts
function editautostart() {
    AUTOSTART_LIST="$(for autostartfile in $(\dir -C -w 1 "$HOME"/.config/opendm/autostart); do\
        echo -n "$autostartfile|"
    done)"
    AUTOSTART_LIST="$(echo $AUTOSTART_LIST | rev | cut -f2- -d'|' | rev)"
    AUTOSTART_CHOICE="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>Edit Autostart File<br/></h2>" --add-combo="" --combo-values=$AUTOSTART_LIST)"
    case $? in
        1)
            opendmconfig
            ;;
        0)
            EDITED_AUTOSTART="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --text-info --checkbox="Save Changes" --editable --filename=""$HOME"/.config/opendm/autostart/"$AUTOSTART_CHOICE"")"
            case $? in
                1)
                    opendmconfig "Autostart"
                    ;;
                0)
                    if [ -z "$EDITED_AUTOSTART" ]; then
                        qarma --title="OpenDM" --error --text="No text was entered!"
                        opendmconfig "Autostart"
                    else
                        echo "$EDITED_AUTOSTART" > "$HOME"/.config/opendm/autostart/"$AUTOSTART_CHOICE"
                        qarma --title="OpenDM" --info --text="Changes to $AUTOSTART_CHOICE have been saved!"
                        opendmconfig "Autostart"
                    fi
                    ;;
            esac
            ;;
    esac
}

# Launch a qarma text editor for editing OpenDM's variables.conf and warn user that changes will happen on next login
function editvariables() {
    CURRENT_WIDTH=$(xrandr --current | head -n 1 | cut -f2 -d',' | cut -f-1 -d'x' | cut -f3 -d' ')
    CURRENT_HEIGHT=$(xrandr --current | head -n 1 | cut -f2 -d',' | cut -f2 -d'x' | cut -f2 -d' ')
    DIALOG_WIDTH=$(echo $CURRENT_WIDTH | awk '{print $1 * .50}' | cut -f1 -d'.')
    DIALOG_HEIGHT=$(echo $CURRENT_HEIGHT | awk '{print $1 * .50}' | cut -f1 -d'.')
    EDITED_VARIABLES="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --text-info --checkbox="Save Changes" --editable --width=$DIALOG_WIDTH --height=$DIALOG_HEIGHT --filename=""$HOME"/.config/opendm/variables.conf")"
    case $? in
        1)
            opendmconfig
            ;;
        0)
            if [ -z "$EDITED_VARIABLES" ]; then
                qarma --title="OpenDM" --error --text="No text was entered!"
                opendmconfig
            else
                echo "$EDITED_VARIABLES" > "$HOME"/.config/opendm/variables.conf
                qarma --title="OpenDM" --info --text="Changes to OpenDM Variables have been saved.<br>Changes will take effect on next login!"
                opendmconfig
            fi
            ;;
    esac
}

# Check default Xorg log locations and open a qarma folder selection GUI on the first found dir
# A qarma text editor is launched to show the chosen Xorg log file
function xorglogviewer() {
    CURRENT_WIDTH=$(xrandr --current | head -n 1 | cut -f2 -d',' | cut -f-1 -d'x' | cut -f3 -d' ')
    CURRENT_HEIGHT=$(xrandr --current | head -n 1 | cut -f2 -d',' | cut -f2 -d'x' | cut -f2 -d' ')
    DIALOG_WIDTH=$(echo $CURRENT_WIDTH | awk '{print $1 * .50}' | cut -f1 -d'.')
    DIALOG_HEIGHT=$(echo $CURRENT_HEIGHT | awk '{print $1 * .50}' | cut -f1 -d'.')
    if [ -d "$HOME/.local/share/xorg" ]; then
        XORGLOG_SELECTION="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --file-selection --filename="$HOME/.local/share/xorg/X")"
        if [ ! -z "$XORGLOG_SELECTION" ]; then
            qarma --title="OpenDM" --text-info --editable --width=$DIALOG_WIDTH --height=$DIALOG_HEIGHT --filename="$XORGLOG_SELECTION"
            case $? in
                0)
                    opendmconfig "Xorg"
                    ;;
                1)
                    opendmconfig
                    ;;
            esac
        else
            opendmconfig
        fi
    else
        XORGLOG_SELECTION="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --file-selection --filename="/var/log/X")"
        if [ ! -z "$XORGLOG_SELECTION" ]; then
            qarma --title="OpenDM" --text-info --editable --width=$DIALOG_WIDTH --height=$DIALOG_HEIGHT --filename="$XORGLOG_SELECTION"
            case $? in
                0)
                    opendmconfig "Xorg"
                    ;;
                1)
                    opendmconfig
                    ;;
            esac
        else
            opendmconfig
        fi
    fi
}

# Check if startx and qarma are in $PATH
if ! type startx >/dev/null 2>&1; then
    echo "xinit is not installed; exiting..."
    exit 1
fi
if ! type qarma >/dev/null 2>&1; then
    echo "qarma not installed; exiting..."
    exit 1
fi

# Check if OpenDM's config dir exists and create config dir if it doesn't exist
if [ ! -d "$HOME/.config/opendm" ]; then
    if [ -d "$RUNNING_DIR/configs" ]; then
        cp -r "$RUNNING_DIR"/configs "$HOME"/.config/opendm || { echo "Could not create config dir for OpenDM; exiting..."; exit 1; }
    else
        echo "'$HOME/.config/opendm' does not exist and '$RUNNING_DIR/configs' not found!"
        echo "Could not create config dir for OpenDM; exiting..."
        exit 1
    fi
fi

# Copy opendm.png to /tmp so that qarma can actually use it (won't work from dirs beginning with '.' for some reason)
if [ -f "$HOME/.config/opendm/opendm.png" ]; then
    cp "$HOME"/.config/opendm/opendm.png /tmp/opendm.png
fi

# Run a for loop on ~/.config/opendm/xsessions that checks SESSION_START commands using type
for xsession in $(dir -a -C -w 1 "$HOME"/.config/opendm/xsessions | tail -n +3 | grep -vw '.directory'); do
    . "$HOME"/.config/opendm/xsessions/"$xsession"
    case "$xsession" in
        # If session is disabled and type finds SESSION_START command, session is enabled
        .*)
            if type $(echo "$SESSION_START" | cut -f1 -d' ') >/dev/null 2>&1; then
                ENABLED_NAME="$(echo $xsession | cut -f2- -d'.')"
                mv "$HOME"/.config/opendm/xsessions/"$xsession" "$HOME"/.config/opendm/xsessions/"$ENABLED_NAME"
            fi
            ;;
        # If session is enabled and type does not find SESSION_START command, session is disabled
        *)
            if ! type $(echo "$SESSION_START" | cut -f1 -d' ') >/dev/null 2>&1; then
                mv "$HOME"/.config/opendm/xsessions/"$xsession" "$HOME"/.config/opendm/xsessions/."$xsession"
            fi
            ;;
    esac
done

# Detect user input and route to proper functions
case "$1" in
    # Internal argument used by OpenDM to start sessionselect function
    --session-select)
        sessionselect
        ;;
    # Any other arguments are routed to startchecks function
    *)
        startchecks "$1"
        ;;
esac
exit 0
