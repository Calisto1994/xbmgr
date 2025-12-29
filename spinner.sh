#!/bin/bash

cleanup () {
    tput cnorm; # show the cursor again
    if [[ $hadFooter == 1 ]]; then ## this only needs to run if there ever was a footer generated.
        printf "\e[r"; # restore the terminal height
        clear; # clean the terminal entirely.
    fi
}

spinner_relative() {
    local pid=$1;
    local msg=$2;
    local delay=.05;
    local spinstr='|/-\';
    
    # Hide the cursor so it looks cleaner
    tput civis;

    trap cleanup INT HUP EXIT;

    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?};
        printf "%s [%c] " "$msg" "$spinstr";
        local spinstr=$temp${spinstr%"$temp"};
        sleep $delay;
        printf "\r"; # go back to the start of the line and overwrite.
    done

    # Wait for the PID to actually finish and catch its exit code
    wait "$pid"
    local exit_code=$?

    # Show the cursor again
    tput cnorm 

    # Clean up the spinner space and show final status
    if [[ $exit_code -eq 0 ]]; then
        printf "%s [\e[1;32m\u2714\e[0m]  \n" "$msg"  # Green check
        printf "\a"; # successful.
    else
        printf "%s [\e[1;31m\u2718\e[0m]  \n" "$msg"  # Red cross
        for i in {1..3}; do printf "\a"; sleep .2; done; # failure.
    fi

    return $exit_code; # throw back the exit code.
}

spinner_footer() {
    hadFooter=1;
    local pid=$1;
    local msg=$2;
    local delay=.05;
    local spinstr='|/-\';
    
    # Hide the cursor so it looks cleaner
    tput civis;

    local bottom=$(tput lines); # get the maximum lines of our terminal
    printf "\e[1;$((bottom - 1))r"; # reduce it by one line so we may create a footer.

    trap cleanup INT HUP EXIT;

    while kill -0 "$pid" 2>/dev/null; do
        tput sc;
        tput cup $bottom 0; # go to our footer

        local temp=${spinstr#?};
        printf "%s [%c] " "$msg" "$spinstr";
        local spinstr=$temp${spinstr%"$temp"};
        sleep $delay;
        printf "\r"; # go back to the start of the line and overwrite.

        tput rc;
    done

    tput sc
    tput cup $bottom 0;
    printf "\e[K";
    tput rc;

    # Wait for the PID to actually finish and catch its exit code
    wait "$pid"
    local exit_code=$?

    # Show the cursor again
    tput cnorm 

    # Clean up the spinner space and show final status
    if [[ $exit_code -eq 0 ]]; then
        printf "%s [\e[1;32m\u2714\e[0m]  \n" "$msg"  # Green check
        printf "\a"; # successful.
    else
        printf "%s [\e[1;31m\u2718\e[0m]  \n" "$msg"  # Red cross
        for i in {1..3}; do printf "\a"; sleep .2; done; # failure.
    fi

    return $exit_code; # throw back the exit code.
}

spinner_successmsg () {
    msg=$2;
    printf "%s [\e[1;33m\u2B50\e[0m]  \n" "$msg"  # Yellow Star
}

spinner_failuremsg () {
    msg=$2;
    printf "%s [\e[1;31m\u274C\e[0m]  \n" "$msg"; # Red, large cross
}

spinner () {
    if [[ $3 == "f" ]]; then
        spinner_footer "$@";
    else
        spinner_relative "$@";
    fi
}