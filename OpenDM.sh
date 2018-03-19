#!/bin/bash
# Author: simonizor
# License: MIT
# Description: A simple Display Manager that uses xinit and qarma to launch a session select GUI
# Description: Also provides configuration options and a logout menu

RUNNING_DIR="$(dirname $(readlink -f $0))"
if [ -z "$OPENDM_TTY" ]; then
    OPENDM_TTY="tty1"
fi

function generatesessionlist() {
    if [ ! -d "/tmp/opendm/$USER/$OPENDM_TTY" ]; then
        mkdir -p /tmp/opendm/"$USER"/"$OPENDM_TTY"
    fi
    # Run a for loop on ~/.config/opendm/xsessions that checks for enabled sessions
    # If OPENDM_DEFAULT_SESSION is set in variables.conf and session file matching name exists, list default session first
    SESSION_LIST="$( if [ ! -z "$OPENDM_DEFAULT_SESSION" ] && [ -f "$HOME/.config/opendm/xsessions/$OPENDM_DEFAULT_SESSION" ]; then
        echo -n "$OPENDM_DEFAULT_SESSION|"
    else
        # Set default session to random numbers if it doesn't exist to avoid errors
        OPENDM_DEFAULT_SESSION="${RANDOM}${RANDOM}${RANDOM}"
    fi
    # For loop that looks for enabled session files and lists them by name
    for sessionfile in $(\dir -C -w 1 "$HOME"/.config/opendm/xsessions); do
        case $sessionfile in
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
    if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
        SESSION_CHOICE="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms --cancel-label="Shutdown" \
        --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>Enter password for $USER<br/></h2>" \
        --add-combo="" --combo-values=$SESSION_LIST --add-password="")"
    else
        SESSION_CHOICE="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --align="center" --text-align="center" \
        --width=350 --height=200 --separator="|" --form --item-separator="|" --image="/tmp/opendm.png" --button="Shutdown|gtk-cancel":1 --button=gtk-ok:0 \
        --field="OpenDM\n\n":LBL "OpenDM\n\n" --field="Enter password for$USER\n":LBL "Enter password for$USER\n" --field="":CB "$SESSION_LIST" \
        --field="":H "")"
    fi
    case $? in
        1)
            logoutselect "SHUTDOWN"
            ;;
    esac
    SU_PASSWORD_CHECK="$(echo $SESSION_CHOICE | cut -f2 -d'|')"
    SESSION_CHOICE="$(echo $SESSION_CHOICE | cut -f1 -d'|')"
    # use su -c true "$USER" to check password entry
    if ! echo "$SU_PASSWORD_CHECK" | su -c true "$USER"; then
        if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
            qarma --title="OpenDM" --error --text="Incorrect password for $USER!"
        else
            yad --borders=10 --on-top --center --title="OpenDM" --error --text="Incorrect password for $USER!" --button=gtk-ok:0
        fi
        exit 1
    fi
}

# Function that provides session selection based on files in ~/.config/opendm/xsessions and runs 'exec' on the user's choice
function sessionselect() {
    generatesessionlist
    # Use qarma to provide a GUI with a list of enabled sessions, OpenDM's settings menu, and ability to launch non listed session through 'Other...'
    case $1 in
        PASSWORD_CHECK)
            supasswordcheck || exit 0
            ;;
        *)
            if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                SESSION_CHOICE="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms --cancel-label="Logout" \
                --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>$USER@$HOST<br/></h2>" \
                --add-combo="" --combo-values=$SESSION_LIST)"
            else
                SESSION_CHOICE="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --align="center" --text-align="center" \
                --width=350 --height=200 --separator="" --form --item-separator="|" --image="/tmp/opendm.png" --button="Logout|gtk-cancel":1 --button=gtk-ok:0 \
                --field="OpenDM\n\n":LBL "OpenDM\n\n" --field="$USER@$HOST\n":LBL "$USER@$HOST\n" --field="":CB "$SESSION_LIST")"
            fi
            ;;
    esac
    # Go to logoutselect function if no choice was made; "LOGOUT" tells logoutselect function not to provide option to exit session and to return to sessionselect if no logout choice is made
    if [ -z "$SESSION_CHOICE" ]; then
        logoutselect "LOGOUT"
    else
        case $SESSION_CHOICE in
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
                # Export session variables (might not actually be helpful; maybe don't do this?)
                # export WINDOWMANAGER="$SESSION_START"
                # export XDG_CURRENT_DESKTOP="$SESSION_CHOICE"
                # export XDG_SESSION_DESKTOP="$(echo $SESSION_CHOICE | tr '[:upper:]' '[:lower:]')"
                # Run autostart script for chosen session if it is set in the session file and exists
                if [ ! -z "$SESSION_AUTOSTART" ] && [ -f "$HOME/.config/opendm/autostart/$SESSION_AUTOSTART" ]; then
                    "$HOME"/.config/opendm/autostart/"$SESSION_AUTOSTART"
                fi
                # Place the $SESSION_EXIT command in ~/.config/opendm/.currentsession"$OPENDM_TTY" so we know how to exit the chosen session in the logout menu
                # echo "SESSION_EXIT=\"$SESSION_EXIT\"" > /tmp/opendm/"$USER"/"$OPENDM_TTY"/currentsession
                cp "$HOME"/.config/opendm/xsessions/"$SESSION_CHOICE" /tmp/opendm/"$USER"/"$OPENDM_TTY"/currentsession
                # Run 'exec' on chosen session so that Xorg will exit when chosen session exits
                $SESSION_START
                ;;
            esac
    fi
}

# If $OPENDM_DEFAULT_SESSION is set, $OPENDM_AUTOSTART_DEFAULT is set to TRUE, the  configured default session will be launched on first login
# '/tmp/opendmautosession' is used to prevent the auto session from launching if the 'Exit' option is chosen in the logout menu
function autostart() {
    if [ -d "/tmp/opendm/$USER/$OPENDM_TTY" ] && [ -f "/tmp/opendm/$USER/$OPENDM_TTY/currentsession" ]; then
        mv /tmp/opendm/"$USER"/"$OPENDM_TTY"/currentsession /tmp/opendm/"$USER"/"$OPENDM_TTY"/lastsession
    elif [ ! -d "/tmp/opendm/$USER/$OPENDM_TTY" ]; then
        mkdir -p /tmp/opendm/"$USER"/"$OPENDM_TTY"
    fi
    if [ ! -z "$OPENDM_DEFAULT_SESSION" ] && [ -f "$HOME/.config/opendm/xsessions/$OPENDM_DEFAULT_SESSION" ] && [ ! -f "/tmp/opendm/$USER/$OPENDM_TTY/lastsession" ]; then
        . "$HOME"/.config/opendm/xsessions/"$OPENDM_DEFAULT_SESSION"
        # Not sure if these are helping; disabling for now...
        # export WINDOWMANAGER="$SESSION_START"
        # export XDG_CURRENT_DESKTOP="$SESSION_CHOICE"
        # export XDG_SESSION_DESKTOP="$(echo $SESSION_CHOICE | tr '[:upper:]' '[:lower:]')"
        if [ ! -z "$SESSION_AUTOSTART" ] && [ -f "$HOME/.config/opendm/autostart/$SESSION_AUTOSTART" ]; then
            "$HOME"/.config/opendm/autostart/"$SESSION_AUTOSTART"
        fi
        cp "$HOME"/.config/opendm/xsessions/"$OPENDM_DEFAULT_SESSION" /tmp/opendm/"$USER"/"$OPENDM_TTY"/currentsession
        $SESSION_START
    else
        sessionselect
    fi
}

# Provides a simple qarma entry box to run 'exec' on commands not listed in sessionselect
# Can be used for other DEs/WMs or even for running something like a browser quick without launching a whole DE/WM along with it
function othersession() {
    if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
        OTHER_CHOICE="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --entry --text="Enter a command to run" --entry-text="xterm")"
    else
        OTHER_CHOICE="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --align="center" --text-align="center" \
        --width=350 --height=200 --separator="" --entry --text="Enter a command to run" --entry-text="xterm")"
    fi
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
        case $1 in
            SHUTDOWN)
                if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                    LOGOUT_CHOICE="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms --cancel-label="Back" \
                    --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>Shutdown?<br/></h2>" \
                    --add-combo="" --combo-values="Restart|Shutdown")"
                else
                    LOGOUT_CHOICE="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --align="center" --text-align="center" \
                    --width=350 --height=200 --separator="" --form --item-separator="|" --image="/tmp/opendm.png" --button="Back|gtk-cancel":1 --button=gtk-ok:0 \
                    --field="OpenDM\n\n":LBL "OpenDM\n\n" --field="Shutdown?\n":LBL "Shutdown?\n" --field="":CB "Restart|Shutdown")"
                fi
                case $? in
                    1)
                        supasswordcheck
                        ;;
                esac
                ;;
            LOGOUT)
                if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                    LOGOUT_CHOICE="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms --cancel-label="Back" \
                    --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>Logout?<br/></h2>" \
                    --add-combo="" --combo-values="Logout|Restart|Shutdown")"
                else
                    LOGOUT_CHOICE="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --align="center" --text-align="center" \
                    --width=350 --height=200 --separator="" --form --item-separator="|" --image="/tmp/opendm.png" --button="Back|gtk-cancel":1 --button=gtk-ok:0 \
                    --field="OpenDM\n\n":LBL "OpenDM\n\n" --field="Logout?\n":LBL "Logout?\n" --field="":CB "Logout|Restart|Shutdown")"
                fi
                ;;
            *)
                if [ ! -f "/tmp/opendm/$USER/$OPENDM_TTY/currentsession" ]; then
                    if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                        qarma --error --title="OpenDM" --text="Current session was not started with OpenDM!"  --window-icon="/tmp/opendm.png"
                    else
                        yad --borders=10 --on-top --center --error --title="OpenDM" --text="Current session was not started with OpenDM!"  --window-icon="/tmp/opendm.png" --button=gtk-ok
                    fi
                    exit 1
                fi
                if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                    LOGOUT_CHOICE="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms \
                    --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>Exit Session?<br/></h2>" \
                    --add-combo="" --combo-values="Exit|Logout|Restart|Shutdown")"
                else
                    LOGOUT_CHOICE="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --align="center" --text-align="center" \
                    --width=350 --height=200 --separator="" --form --item-separator="|" --image="/tmp/opendm.png" --button="gtk-cancel":1 --button=gtk-ok:0 \
                    --field="OpenDM\n\n":LBL "OpenDM\n\n" --field="Exit Session?\n":LBL "Exit Session?\n" --field="":CB "Exit|Logout|Restart|Shutdown")"
                fi
                ;;
        esac
        case $LOGOUT_CHOICE in
            Exit*)
                # Source currentsession file to get $SESSION_EXIT
                . /tmp/opendm/"$USER"/"$OPENDM_TTY"/currentsession
                # Create opendmexit file so user's shell knows to restart OpenDM
                mv /tmp/opendm/"$USER"/"$OPENDM_TTY"/currentsession /tmp/opendm/"$USER"/"$OPENDM_TTY"/lastsession
                touch /tmp/opendm/exit
                # Run $SESSION_EXIT command
                $SESSION_EXIT
                ;;
            Logout)
                # Source currentsession file if it exists else set $SESSION_EXIT to 'exit 0'
                if [ -f "/tmp/opendm/$USER/$OPENDM_TTY/currentsession" ]; then
                    . /tmp/opendm/"$USER"/"$OPENDM_TTY"/currentsession
                else
                    SESSION_EXIT="exit 0"
                fi
                # Create '/tmp/opendm/logout' for use along with provided example function for running OpenDM automatically on login and after session exit
                touch /tmp/opendm/logout
                # Run $SESSION_EXIT; user's shell will take care of logging out if example 'opendmstart' function is used
                $SESSION_EXIT
                ;;
            Restart)
                # Set default $OPENDM_REBOOT_CMD if doesn't exist
                if [ -z "$OPENDM_REBOOT_CMD" ]; then
                    OPENDM_REBOOT_CMD="systemctl reboot"
                fi
                # Create '/tmp/opendm/reboot' and make it executable so user's shell can run the configured reboot command
                echo -e "#!/bin/bash\n$OPENDM_REBOOT_CMD\nexit 0" > /tmp/opendm/reboot
                chmod +x /tmp/opendm/reboot
                rm -rf /tmp/opendm/"$USER"/"$OPENDM_TTY"
                # Source currentsession file if it exists else set $SESSION_EXIT to 'exit 0'
                if [ -f "/tmp/opendm/$USER/$OPENDM_TTY/currentsession" ]; then
                    . /tmp/opendm/"$USER"/"$OPENDM_TTY"/currentsession
                else
                    SESSION_EXIT="systemctl reboot"
                fi
                # Run $SESSION_EXIT; user's shell will take care of restarting if 'opendmstart' function is used
                $SESSION_EXIT
                ;;
            Shutdown)
                # Set default $OPENDM_SHUTDOWM_CMD if doesn't exist
                if [ -z "$OPENDM_SHUTDOWN_CMD" ]; then
                    OPENDM_SHUTDOWN_CMD="systemctl poweroff"
                fi
                # Create '/tmp/opendm/shutdown' and make it executable so user's shell can run the configured shutdown command
                echo -e "#!/bin/bash\n$OPENDM_SHUTDOWN_CMD\nexit 0" > /tmp/opendm/shutdown
                chmod +x /tmp/opendm/shutdown
                rm -rf /tmp/opendm/"$USER"/"$OPENDM_TTY"
                # Source currentsession file if it exists else set $SESSION_EXIT to 'exit 0'
                if [ -f "/tmp/opendm/$USER/$OPENDM_TTY/currentsession" ]; then
                    . /tmp/opendm/"$USER"/"$OPENDM_TTY"/currentsession
                else
                    SESSION_EXIT="systemctl poweroff"
                fi
                # Remove leftover files
                # Run $SESSION_EXIT; user's shell will take care of shutdown if 'opendmstart' function is used
                $SESSION_EXIT
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

# Function to provide prompts for exit session, logout, reboot, and shutdown
function opendmquit() {
    if [ -z "$DISPLAY" ]; then
        echo '$DISPLAY is not set; exiting...'
        exit 1
    elif [ ! -f "/tmp/opendm/$USER/$OPENDM_TTY/currentsession" ]; then
        if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
            qarma --error --title="OpenDM" --text="Current session was not started with OpenDM!"  --window-icon="/tmp/opendm.png"
        else
            yad --borders=10 --on-top --center --error --title="OpenDM" --text="Current session was not started with OpenDM!"  --window-icon="/tmp/opendm.png" --button=gtk-ok:0
        fi
        exit 1
    fi
    case $1 in
        exit)
            # Use qarma to show a prompt asking to exit session
            if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                qarma --question --icon-name="/tmp/opendm.png" --title="OpenDM" --text="OpenDM<br><br>Would you like to exit the current X session?"  --window-icon="/tmp/opendm.png"
            else
                yad --borders=10 --on-top --center --question --image="/tmp/opendm.png" --title="OpenDM" --text="OpenDM\n\nWould you like to exit the current X session?"  --window-icon="/tmp/opendm.png" --button=gtk-no:1 --button=gtk-yes:0
            fi
            case $? in
                0)
                    # Source currentsession file to get $SESSION_EXIT
                    . /tmp/opendm/"$USER"/"$OPENDM_TTY"/currentsession
                    # Create opendmexit file so user's shell knows to restart OpenDM
                    mv /tmp/opendm/"$USER"/"$OPENDM_TTY"/currentsession /tmp/opendm/"$USER"/"$OPENDM_TTY"/lastsession
                    touch /tmp/opendm/exit
                    # Run $SESSION_EXIT command
                    $SESSION_EXIT
                    ;;
                1)
                    exit 0
                    ;;
            esac
            ;;
        logout)
            # Use qarma to show a prompt asking to logout
            if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                qarma --question --icon-name="/tmp/opendm.png" --title="OpenDM" --text="OpenDM<br><br>Would you like to logout?"  --window-icon="/tmp/opendm.png"
            else
                yad --borders=10 --on-top --center --question --image="/tmp/opendm.png" --title="OpenDM" --text="OpenDM\n\nWould you like to logout?"  --window-icon="/tmp/opendm.png" --button=gtk-no:1 --button=gtk-yes:0
            fi
            case $? in
                0)
                    # Source currentsession file if it exists else set $SESSION_EXIT to 'exit 0'
                    if [ -f "/tmp/opendm/$USER/$OPENDM_TTY/currentsession" ]; then
                        . /tmp/opendm/"$USER"/"$OPENDM_TTY"/currentsession
                    else
                        SESSION_EXIT="pkill -SIGTERM -f xinit"
                    fi
                    # Create '/tmp/opendm/logout' for use along with provided example function for running OpenDM automatically on login and after session exit
                    touch /tmp/opendm/logout
                    # Run $SESSION_EXIT; user's shell will take care of logging out if example 'opendmstart' function is used
                    $SESSION_EXIT
                    ;;
                1)
                    exit 0
                    ;;
            esac
            ;;
        reboot)
            # Use qarma to show a prompt asking to reboot
            if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                qarma --question --icon-name="/tmp/opendm.png" --title="OpenDM" --text="OpenDM<br><br>Would you like to reboot the PC?"  --window-icon="/tmp/opendm.png"
            else
                yad --borders=10 --on-top --center --question --image="/tmp/opendm.png" --title="OpenDM" --text="OpenDM\n\nWould you like to reboot the PC?"  --window-icon="/tmp/opendm.png" --button=gtk-no:1 --button=gtk-yes:0
            fi
            case $? in
                0)
                    # Set default $OPENDM_REBOOT_CMD if doesn't exist
                    if [ -z "$OPENDM_REBOOT_CMD" ]; then
                        OPENDM_REBOOT_CMD="systemctl reboot"
                    fi
                    # Create '/tmp/opendm/reboot' and make it executable so user's shell can run the configured reboot command
                    echo -e "#!/bin/bash\n$OPENDM_REBOOT_CMD\nexit 0" > /tmp/opendm/reboot
                    chmod +x /tmp/opendm/reboot
                    rm -rf /tmp/opendm/"$USER"/"$OPENDM_TTY"
                    # Source currentsession file if it exists else set $SESSION_EXIT to 'exit 0'
                    if [ -f "/tmp/opendm/$USER/$OPENDM_TTY/currentsession" ]; then
                        . /tmp/opendm/"$USER"/"$OPENDM_TTY"/currentsession
                    else
                        SESSION_EXIT="pkill -SIGTERM -f xinit"
                    fi
                    # Run $SESSION_EXIT; user's shell will take care of restarting if 'opendmstart' function is used
                    $SESSION_EXIT
                    ;;
                1)
                    exit 0
                    ;;
            esac
            ;;
        shutdown)
            # Use qarma to show a prompt asking to shutdown
            if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                qarma --question --icon-name="/tmp/opendm.png" --title="OpenDM" --text="OpenDM<br><br>Would you like to shutdown the PC?"  --window-icon="/tmp/opendm.png"
            else
                yad --borders=10 --on-top --center --question --image="/tmp/opendm.png" --title="OpenDM" --text="OpenDM\n\nWould you like to shutdown the PC?"  --window-icon="/tmp/opendm.png" --button=gtk-no:1 --button=gtk-yes:0
            fi
            case $? in
                0)
                    # Set default $OPENDM_SHUTDOWM_CMD if doesn't exist
                    if [ -z "$OPENDM_SHUTDOWN_CMD" ]; then
                        OPENDM_SHUTDOWN_CMD="systemctl poweroff"
                    fi
                    # Create '/tmp/opendm/shutdown' and make it executable so user's shell can run the configured shutdown command
                    echo -e "#!/bin/bash\n$OPENDM_SHUTDOWN_CMD\nexit 0" > /tmp/opendm/shutdown
                    chmod +x /tmp/opendm/shutdown
                    rm -rf /tmp/opendm/"$USER"/"$OPENDM_TTY"
                    # Source currentsession file if it exists else set $SESSION_EXIT to 'exit 0'
                    if [ -f "/tmp/opendm/$USER/$OPENDM_TTY/currentsession" ]; then
                        . /tmp/opendm/"$USER"/"$OPENDM_TTY"/currentsession
                    else
                        SESSION_EXIT="pkill -SIGTERM -f xinit"
                    fi
                    # Remove leftover files
                    # Run $SESSION_EXIT; user's shell will take care of shutdown if 'opendmstart' function is used
                    $SESSION_EXIT
                    ;;
                1)
                    exit 0
                    ;;
            esac
            ;;
    esac
}

# Use qarma entry boxes to provide ability to add new sessions that aren't included by default
# $SESSION_NAME cannot contain spaces.  $SESSION_NAME, $SESSION_START, and $SESSON_EXIT are required
# $SESSION_AUTOSTART is optional; will create autostart script if it does not exist and make it executable
function addsession() {
    if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
        SESSION_NAME="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --entry --text="OpenDM<br><br>Enter the name of the session (no spaces)")"
    else
        SESSION_NAME="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --entry --text="OpenDM\n\nEnter the name of the session (no spaces)")"
    fi
    if [ -z "$SESSION_NAME" ]; then
        if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
            qarma --title="OpenDM" --error --text="No session name was entered!"
        else
            yad --borders=10 --on-top --center --title="OpenDM" --error --text="No session name was entered!" --button=gtk-ok:0
        fi
        opendmconfig
        exit 0
    elif [ -f "$HOME/.config/opendm/xsessions/$SESSION_NAME" ]; then
        if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
            qarma --title="OpenDM" --error --text="$SESSION_NAME already exists!"
        else
            yad --borders=10 --on-top --center --title="OpenDM" --error --text="$SESSION_NAME already exists!" --button=gtk-ok:0
        fi
        opendmconfig
        exit 0
    fi
    if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
        SESSION_START="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --entry --text="OpenDM<br><br>Enter the command used to start this session")"
    else
        SESSION_START="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --entry --text="OpenDM\n\nEnter the command used to start this session")"
    fi
    if [ -z "$SESSION_START" ]; then
        if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
            qarma --title="OpenDM" --error --text="No session start command was entered!"
        else
            yad --borders=10 --on-top --center --title="OpenDM" --error --text="No session start command was entered!" --button=gtk-ok:0
        fi
        opendmconfig
        exit 0
    fi
    if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
        SESSION_EXIT="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --entry --text="OpenDM<br><br>Enter the command used to exit this session")"
    else
        SESSION_EXIT="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --entry --text="OpenDM\n\nEnter the command used to exit this session")"
    fi
    if [ -z "$SESSION_EXIT" ]; then
        if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
            qarma --title="OpenDM" --error --text="No session exit was entered!"
        else
            yad --borders=10 --on-top --center --title="OpenDM" --error --text="No session exit was entered!" --button=gtk-ok:0
        fi
        opendmconfig
        exit 0
    fi
    echo "SESSION_START=\"$SESSION_START\"" > "$HOME"/.config/opendm/xsessions/"$SESSION_NAME"
    echo "SESSION_EXIT=\"$SESSION_EXIT\"" >> "$HOME"/.config/opendm/xsessions/"$SESSION_NAME"
    if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
        SESSION_AUTOSTART="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --entry --text="OpenDM<br><br>Enter the file name in $HOME/.config/autostart/ for $SESSION_NAME <br>Leave the inputbox blank for no autostart file" --entry-text="autostart.sh")"
    else
        SESSION_AUTOSTART="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --entry --text="OpenDM\n\nEnter the file name in $HOME/.config/autostart/ for $SESSION_NAME \nLeave the inputbox blank for no autostart file" --entry-text="autostart.sh")"
    fi
    if [ ! -z "$SESSION_AUTOSTART" ]; then
        echo "SESSION_AUTOSTART=\"$SESSION_AUTOSTART\"" >> "$HOME"/.config/opendm/xsessions/"$SESSION_NAME"
        if [ ! -f "$HOME/.config/opendm/autostart/$SESSION_AUTOSTART" ]; then
            echo "#!/bin/bash" > "$HOME"/.config/opendm/autostart/"$SESSION_AUTOSTART"
            echo "# All long running commands must be followed with an '&' otherwise the session will not start!" >> "$HOME"/.config/opendm/autostart/"$SESSION_AUTOSTART"
            echo "# Ex:" >> "$HOME"/.config/opendm/autostart/"$SESSION_AUTOSTART"
            echo "# lxpanel &" >> "$HOME"/.config/opendm/autostart/"$SESSION_AUTOSTART"
            chmod +x "$HOME"/.config/opendm/autostart/"$SESSION_AUTOSTART"
        fi
    else
        echo "SESSION_AUTOSTART=\"\"" >> "$HOME"/.config/opendm/xsessions/"$SESSION_NAME"
    fi
    if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
        qarma --title="OpenDM" --info --text="$SESSION_NAME has been added!"
    else
        yad --borders=10 --on-top --center --title="OpenDM" --info --text="$SESSION_NAME has been added!" --button=gtk-ok:0
    fi
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
    if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
        SESSION_CHOICE="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>Edit Session<br/></h2>" --add-combo="" --combo-values=$SESSION_LIST)"
    else
        SESSION_CHOICE="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --align="center" --text-align="center" \
        --width=350 --height=200 --separator="" --form --item-separator="|" --image="/tmp/opendm.png" --button="gtk-cancel":1 --button=gtk-ok:0 \
        --field="OpenDM\n\n":LBL "OpenDM\n\n" --field="Edit Session\n":LBL "Edit Session\n" --field="":CB "$SESSION_LIST")"
    fi
    # If no choice, return to config
    if [ -z "$SESSION_CHOICE" ]; then
        opendmconfig
    else
        # qarma text input box to edit chosen session
        if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
            EDITED_SESSION="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --text-info --checkbox="Save Changes" --editable --filename=""$HOME"/.config/opendm/xsessions/"$SESSION_CHOICE"")"
        else
            EDITED_SESSION="$(yad --borders=10 --on-top --center --width=400 --height=400 --window-icon="/tmp/opendm.png" --title="OpenDM" --text-info --editable --filename=""$HOME"/.config/opendm/xsessions/"$SESSION_CHOICE"")"
        fi
        case $? in
            1)
                # Return to config without saving if canceled
                opendmconfig "Sessions"
                ;;
            0)
                # If no text input, display error and return to config else save changes
                if [ -z "$EDITED_SESSION" ]; then
                    if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                        qarma --title="OpenDM" --error --text="No text was entered!"
                    else
                        yad --borders=10 --on-top --center --title="OpenDM" --error --text="No text was entered!" --button=gtk-ok:0
                    fi
                    opendmconfig "Sessions"
                else
                    echo "$EDITED_SESSION" > "$HOME"/.config/opendm/xsessions/"$SESSION_CHOICE"
                    if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                        qarma --title="OpenDM" --info --text="Changes to $SESSION_CHOICE have been saved!"
                    else
                        yad --borders=10 --on-top --center --title="OpenDM" --info --text="Changes to $SESSION_CHOICE have been saved!" --button=gtk-ok:0
                    fi
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
    if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
        AUTOSTART_CHOICE="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>Edit Autostart File<br/></h2>" --add-combo="" --combo-values=$AUTOSTART_LIST)"
    else
        AUTOSTART_CHOICE="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --align="center" --text-align="center" \
        --width=350 --height=200 --separator="" --form --item-separator="|" --image="/tmp/opendm.png" --button="gtk-cancel":1 --button=gtk-ok:0 \
        --field="OpenDM\n\n":LBL "OpenDM\n\n" --field="Edit Autostart File\n":LBL "Edit Autostart File\n" --field="":CB "$AUTOSTART_LIST")"
    fi
    case $? in
        1)
            opendmconfig
            ;;
        0)
            if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                EDITED_AUTOSTART="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --text-info --checkbox="Save Changes" --editable --filename=""$HOME"/.config/opendm/autostart/"$AUTOSTART_CHOICE"")"
            else
                EDITED_AUTOSTART="$(yad --borders=10 --on-top --center --width=500 --height=500 --window-icon="/tmp/opendm.png" --title="OpenDM" --text-info --editable --filename=""$HOME"/.config/opendm/autostart/"$AUTOSTART_CHOICE"")"
            fi
            case $? in
                1)
                    opendmconfig "Autostart"
                    ;;
                0)
                    if [ -z "$EDITED_AUTOSTART" ]; then
                        if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                            qarma --title="OpenDM" --error --text="No text was entered!"
                        else
                            yad --borders=10 --on-top --center --title="OpenDM" --error --text="No text was entered!" --button=gtk-ok:0
                        fi
                        opendmconfig "Autostart"
                    else
                        echo "$EDITED_AUTOSTART" > "$HOME"/.config/opendm/autostart/"$AUTOSTART_CHOICE"
                        if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                            qarma --title="OpenDM" --info --text="Changes to $AUTOSTART_CHOICE have been saved!"
                        else
                            yad --borders=10 --on-top --center --title="OpenDM" --info --text="Changes to $AUTOSTART_CHOICE have been saved!" --button=gtk-ok:0
                        fi
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
    DIALOG_WIDTH=$(echo $CURRENT_WIDTH | awk '{print $1 * .50}')
    DIALOG_HEIGHT=$(echo $CURRENT_HEIGHT | awk '{print $1 * .50}')
    if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
        EDITED_VARIABLES="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --text-info --checkbox="Save Changes" --editable --width=$DIALOG_WIDTH --height=$DIALOG_HEIGHT --filename=""$HOME"/.config/opendm/variables.conf")"
    else
        EDITED_VARIABLES="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --text-info --editable --width=$DIALOG_WIDTH --height=$DIALOG_HEIGHT --filename=""$HOME"/.config/opendm/variables.conf")"
    fi
    case $? in
        1)
            opendmconfig
            ;;
        0)
            if [ -z "$EDITED_VARIABLES" ]; then
                if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                    qarma --title="OpenDM" --error --text="No text was entered!"
                else
                    yad --borders=10 --on-top --center --title="OpenDM" --error --text="No text was entered!" --button=gtk-ok:0
                fi
                opendmconfig
            else
                echo "$EDITED_VARIABLES" > "$HOME"/.config/opendm/variables.conf
                if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                    qarma --title="OpenDM" --info --text="Changes to OpenDM Variables have been saved.<br>Changes will take effect on next login!"
                else
                    yad --borders=10 --on-top --center --title="OpenDM" --info --text="Changes to OpenDM Variables have been saved.\nChanges will take effect on next login!" --button=gtk-ok:0
                fi
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
    DIALOG_WIDTH=$(echo $CURRENT_WIDTH | awk '{print $1 * .50}')
    DIALOG_HEIGHT=$(echo $CURRENT_HEIGHT | awk '{print $1 * .50}')
    if [ -d "$HOME/.local/share/xorg" ]; then
        if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
            XORGLOG_SELECTION="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --file-selection --filename="$HOME/.local/share/xorg/X")"
        else
            XORGLOG_SELECTION="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --file-selection --filename="$HOME/.local/share/xorg/X")"
        fi
        if [ ! -z "$XORGLOG_SELECTION" ]; then
            if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                qarma --title="OpenDM" --text-info --editable --width=$DIALOG_WIDTH --height=$DIALOG_HEIGHT --filename="$XORGLOG_SELECTION"
            else
                yad --borders=10 --on-top --center --title="OpenDM" --text-info --editable --width=$DIALOG_WIDTH --height=$DIALOG_HEIGHT --filename="$XORGLOG_SELECTION"
            fi
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
        if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
            XORGLOG_SELECTION="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --file-selection --filename="/var/log/X")"
        else
            XORGLOG_SELECTION="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --file-selection --filename="/var/log/X")"
        fi
        if [ ! -z "$XORGLOG_SELECTION" ]; then
            if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                qarma --title="OpenDM" --text-info --editable --width=$DIALOG_WIDTH --height=$DIALOG_HEIGHT --filename="$XORGLOG_SELECTION"
            else
                yad --borders=10 --on-top --center --title="OpenDM" --text-info --editable --width=$DIALOG_WIDTH --height=$DIALOG_HEIGHT --filename="$XORGLOG_SELECTION"
            fi
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

# Use qarma to provide a list of OpenDM's config options and route user's choice to relevant function
function opendmconfig() {
    if [ ! -z "$1" ]; then
        CONFIG_SELECTION="$1"
    else
        # CONFIG_SELECTION="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>Edit Settings<br/></h2>" --add-combo="" --combo-values='Enable or Disable Sessions|Sessions Editor|Add New Session|OpenDM Variables Editor|Autostart Files Editor|Xorg Log Viewer')"
        if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
            CONFIG_SELECTION="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>Edit Settings<br/></h2>" --add-combo="" --combo-values='Sessions Editor|Add New Session|OpenDM Variables Editor|Autostart Files Editor|Xorg Log Viewer')"
        else
            CONFIG_SELECTION="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --align="center" --text-align="center" \
            --width=350 --height=200 --separator="" --form --item-separator="|" --image="/tmp/opendm.png" --button="gtk-cancel":1 --button=gtk-ok:0 \
            --field="OpenDM\n\n":LBL "OpenDM\n\n" --field="Edit Settings\n":LBL "Edit Settings\n" --field="":CB "Sessions Editor|Add New Session|OpenDM Variables Editor|Autostart Files Editor|Xorg Log Viewer")"
        fi
    fi
    case $CONFIG_SELECTION in
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

# Start function to check if $DISPLAY is set and running on $OPENDM_TTY; use startx if $DISPLAY is not set and running on $OPENDM_TTY
function startchecks() {
    if [ -z "$DISPLAY" ] && [ -f "$HOME/.config/opendm/.opendminitrc" ] && [ "$(ps ax | grep $$ | grep -v grep | awk '{ print $2 }')" = "$OPENDM_TTY" ]; then
        if [ -d "/tmp/opendm/$USER/$OPENDM_TTY" ] && [ -f "/tmp/opendm/$USER/$OPENDM_TTY/currentsession" ]; then
            mv /tmp/opendm/"$USER"/"$OPENDM_TTY"/currentsession /tmp/opendm/"$USER"/"$OPENDM_TTY"/lastsession
        elif [ ! -d "/tmp/opendm/$USER/$OPENDM_TTY" ]; then
            mkdir -p /tmp/opendm/"$USER"/"$OPENDM_TTY"
        fi
        case $1 in
            # Allows OpenDM's config to be started from a TTY
            config)
                startx "$HOME"/.config/opendm/.opendminitrc --config-start 1>~/.xsession-errors 2>&1
                ;;
            # Normal start from a TTY
            *)
                startx "$HOME"/.config/opendm/.opendminitrc --session-select 1>~/.xsession-errors 2>&1
                ;;
        esac
    # If $DISPLAY is set, just run OpenDM's arguments without using startx
    elif [ ! -z "$DISPLAY" ]; then
        case $1 in
            config)
                opendmconfig
                ;;
            *)
                # Tell user that X session is running and provide option to launch config or exit session
                if [ "$OPENDM_USE_QARMA" = "TRUE" ]; then
                    RUNNING_SELECTION="$(qarma --window-icon="/tmp/opendm.png" --title="OpenDM" --forms --text="<h2 align='center'>OpenDM<br/><br/><img src='/tmp/opendm.png' width='64'/><br/><img src='/tmp/opendm.png' width='350' height='0'/><br/><br/>An X Session is already running.<br/></h2>" --add-combo="" --combo-values="Edit Settings|Exit Session")"
                else
                    RUNNING_SELECTION="$(yad --borders=10 --on-top --center --window-icon="/tmp/opendm.png" --title="OpenDM" --align="center" --text-align="center" \
                    --width=350 --height=200 --separator="" --form --item-separator="|" --image="/tmp/opendm.png" --button="gtk-cancel":1 --button=gtk-ok:0 \
                    --field="OpenDM\n\n":LBL "OpenDM\n\n" --field="An X Session is already running.\n":LBL "An X Session is already running.\n" --field="":CB "Edit Settings|Exit Session")"
                fi
                case $RUNNING_SELECTION in
                    Edit*)
                        opendmconfig
                        ;;
                    Exit*)
                        logoutselect
                        ;;
                    *)
                        exit 0
                        ;;
                esac
                ;;
        esac
    # Exit if not running on $OPENDM_TTY
    elif [ ! "$(ps ax | grep $$ | grep -v grep | awk '{ print $2 }')" = "$OPENDM_TTY" ]; then
        echo "OPENDM_TTY is set to $OPENDM_TTY; currently running on $(ps ax | grep $$ | grep -v grep | awk '{ print $2 }')."
        echo "Running OpenDM on multiple TTYs at the same time is currently not supported."
        echo "Please edit your shell's profile to change the 'export OPENDM_TTY=' line if you wish to use a different TTY."
        exit 1
    # Exit if ~/.config/opendm/.opendminitrc doesn't exist
    else
        echo '""$HOME"/.config/opendm/.opendminitrc does not exist!' 
        echo 'Please see https://github.com/simoniz0r/opendm/.opendminitrc for an example.'
        exit 1
    fi
}

# TODO better help function
function opendmhelp() {
    echo "TODO better help function"
    echo
    echo "Arguments:"
    echo "config            Show OpenDM's config menu"
    echo "exitmenu          Show OpenDM's exit session menu"
    echo "exit              Show a prompt asking to exit session"
    echo "logout            Show a prompt asking to logout"
    echo "reboot            Show a prompt asking to reboot"
    echo "shutdown          Show a prompt asking to shutdown"
}


# Check if startx and qarma are in $PATH
if ! type startx >/dev/null 2>&1; then
    echo "xinit is not installed; exiting..."
    exit 1
fi
# FIXME WHEN YAD DONE
if ! type yad >/dev/null 2>&1; then
    OPENDM_USE_QARMA="TRUE"
    if ! type qarma >/dev/null 2>&1; then
        echo "yad or qarma not installed; exiting..."
        exit 1
    fi
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
for xsession in $(dir -a -C -w 1 "$HOME"/.config/opendm/xsessions | tail -n +3); do
    . "$HOME"/.config/opendm/xsessions/"$xsession"
    case $xsession in
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
case $1 in
    # Used internally by OpenDM to execute the autostart function
    --auto-start)
        autostart
        ;;
    # Used internally by OpenDM to execute the supasswordcheck function
    --password-check)
        if [ -f "/tmp/opendm/$USER/$OPENDM_TTY/lastsession" ]; then
            sessionselect
        else
            sessionselect "PASSWORD_CHECK"
        fi
        ;;
    # Used internally by OpenDM to execute the config function
    --config-start)
        opendmconfig
        ;;
    # Used internally by OpenDM to execute the session select function
    --session-select)
        sessionselect
        ;;
    # Brings up OpenDM's exit session menu
    exitmenu)
        logoutselect
        ;;
    # Shows a prompt asking to exit session
    exit)
        opendmquit "exit"
        ;;
    # Shows a prompt asking to logout
    logout)
        opendmquit "logout"
        ;;
    # Shows a prompt asking to reboot
    reboot|restart)
        opendmquit "reboot"
        ;;
    # Shows a prompt asking to shutdown
    shutdown|poweroff)
        opendmquit "shutdown"
        ;;
    # Shows OpenDM's arguments when ran in a terminal
    help|--help)
        opendmhelp
        ;;
    # Any other arguments are routed to startchecks function
    *)
        startchecks "$1"
        ;;
esac
exit 0
