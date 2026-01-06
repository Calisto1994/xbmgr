#!/bin/bash

#######################
#     XBOX MANAGER    #
# for Aurora-enabled  #
#   Xbox360 systems   #
#######################
source spinner.sh; # include our little, animated best friend

## Required directories. Create if not existing. Do not complain if they exist. ##
mkdir -p ./Ext/ &> /dev/null || { spinner_failuremsg 0 "Failed to create directory './Ext/'"; exit 1; }
mkdir -p ./Unext/ &> /dev/null || { spinner_failuremsg 0 "Failed to create directory './Unext/'"; exit 1; }
mkdir -p ./dump/ &> /dev/null || { spinner_failuremsg 0 "Failed to create directory './dump/'"; exit 1; }
mkdir -p ./logs/ &> /dev/null || { spinner_failuremsg 0 "Failed to create directory './logs/'"; exit 1; }

# HELPER FUNCTIONS #

makeConfig () {
    if [[ $1 -eq "missing" ]]; then
        echo "No configuration file was found. Let's create one.";
    fi

    configFile=$(cat <<EOF
#!/bin/bash

######### XBOX MANAGER CONFIG FILE #########
# Generated using XBOX MANAGER SETUP TOOL  #
############################################
# Aurora ftp user
xbuser=%q;

#Aurora ftp password
xbpass=%q;

#host or IP of the Xbox360 console utilizing Aurora
xbhost=%q;

# Path where to put the games on the Xbox360
xbpath=%q;

EOF
);

read -p "Xbox FTP Username: " xbuser;
read -p "Xbox FTP Password: " xbpass;
read -p "Xbox Host/IP: " xbhost;
read -p "Xbox Path: " xbpath;

printf "${configFile}" "${xbuser}" "${xbpass}" "${xbhost}" "${xbpath}" > config.sh

echo "Config file written.";

exit 0;

}

source config.sh &>/dev/null || makeConfig missing;

params () {
    echo;
    for argument in "$@"; do
        argument=$(echo $argument | tr '[:upper:]' '[:lower:]'); # convert all command line arguments to lowercase
        case "$argument" in
            --upload|-u)
                echo "Transfer games directly to ${xbuser}@${xbhost} (using password: ${isUsingPassword}) ...";
                do_uploads;
                exit;
                ;;
            --help|-h)
                ######## HERE COMES THE HEREDOC ########
cat << EOF
Usage:
 ${0} [options / flags]

Available options:
 --upload / -u           Upload prepared game files from ./Unext/
 --list / -l             List all (extracted) games in ./Unext/
 --help / -h             Show this help
 --rename / -r           Interactively rename/shorten game directories
 --get / -g              EXPERIMENTAL: Download all games from your console to an ./Ext/ folder.
 --setup                 Allows you to create a new configuration file. Will overwrite the previous one.
 --showconfig / -s       Shows your configuration file.
 -y                      "Assume Yes"-mode (will only shorten names instead of interactive rename and
                         upload the files to the Xbox360 afterwards. Made for automation/batch processing.)
                         - does work with the skip flags below!
Additional flags:
 --skip-renaming        Entirely skips the interactive renaming of the games
 --skip-uploads         Entirely skips the uploading of games
 --skip                 Both options from above.
EOF
                ######## ######## ######## ######## ########
                exit;
                ;;
            --rename|-r)
                skipRename=0; # if the user triggers this directly, we don't want it to be skipped.
                echo "Running interactive renaming...";
                interactiveRename;
                exit;
                ;;
            --list|-l)
                listGames;         
                exit;
                ;;
            --get|-g)
                getGames;
                exit;
                ;;
            --skip-renaming)
                skipRename=1;
                ;;
            --skip-uploads)
                skipUploads=1;
                ;;
            --skip)
                skipRename=1;
                skipUploads=1;
                ;;
            --setup)
                makeConfig;
                exit;
                ;;
            --showconfig|-s)
                echo -e "Your config file looks like this:\n\e[1;35m";
                cat "./config.sh";
                echo -e "\e[0m";
                exit;
                ;;
            -y)
                assumeYes=1;
                ;;
            *)
                spinner_failuremsg 0 "Unknown command line argument \"${argument}\". Exiting.";
                exit 1;
                ;;
        esac
    done;
}

check_xbox () {
    (fping -t 250 -r 1 -qa "${xbhost}" &> /dev/null) & spinner $! "Checking whether console is online";
    if [[ $? != 0 ]]; then
        spinner_failuremsg 0 "Host is unreachable. (Is your Xbox360 online and Aurora started?)";
        exit 1;
    fi
}

listGames () {
    if [[ $(gameCount) -gt 0 ]]; then
        echo "$(gameCount) games found:"; echo "";

        for fName in ./Unext/*; do
            if [[ -d "$fName" ]]; then
                printf "%-25s | %s\n" "$(basename "${fName}")" "$(du -sh "$fName" | cut -f 1)";
            fi
        done

        total=$(du -sh ./Unext/ | cut -f1)
        echo "Total games size: ${total}";
    else
        echo "There are currently no games in ./Unext/";K-Drama
    fi       
}

getGames () {
    check_xbox;
    (lftp -e "set ftp:ssl-allow no; set net:max-retries 2; set net:reconnect-interval-base 5; cd ${xbpath}; mirror --parallel=4 -c ./ ./Ext/" "${xbuser}:${xbpass}@${xbhost}" &> ./logs/lftp_dl.log) & spinner $! "Downloading games from console";
}

do_uploads () {
    if [[ $(gameCount) -lt 1 ]]; then
        spinner_failuremsg 0 "There's nothing to upload. Exiting.";
        exit 1;
    fi

    check_xbox;

    (lftp -e "set ftp:ssl-allow no; set net:max-retries 2; set net:reconnect-interval-base 5; cd ${xbpath}; mirror --parallel=4 -R -c ./Unext/ ./" "${xbuser}:${xbpass}@${xbhost}" &> ./logs/lftp.log) & spinner $! "Transferring game files"; # transfer all game files to the Xbox360 recursively
    if [[ $? != 0 ]]; then
        spinner_failuremsg 0 "Transfer failed. Aborting...";
        exit 1;
    fi

    echo "Cleaning up...";
    if [[ -d "./Unext" ]]; then
        rm -rf ./Unext/*
    fi
}

interactiveRename () {
    if [[ $skipRename == 1 ]]; then return; fi # if the user wishes so, no interactive renaming!
    if [[ $(gameCount) -lt 1 ]]; then
        spinner_failuremsg 0 "Nothing to rename. Exiting...";
        exit 1;
    fi
    export ASSUME_YES=$assumeYes;

    find ./Unext/ -maxdepth 1 -mindepth 1 -type d -exec bash -c '
    oldName=$(basename "$0");
    if [[ $ASSUME_YES != 1 ]]; then
        read -t 15 -p "How to re-name \"${oldName}\" (max 20 chars!): " newName < /dev/tty;
    fi

    if [[ -n $newName ]]; then
        newName="${newName:0:20}"; # make sure the name does not exceed 20 characters
        echo "Newly entered name is: ${newName} (${#newName} characters long)";
        mv "$0" "./Unext/${newName}";
    else
        newName="${oldName:0:20}";
        if [[ $newName != $oldName ]]; then
            echo "Skipping $oldName... just shortening.";
            echo "New name is: ${newName} (${#newName} characters long)";
            mv "$0" "./Unext/${newName}";
        else
            echo "Skipping $oldName... Nothing has changed, name is already short enough (${#oldName} characters)";
        fi
    fi
' {} \;
    # above code: rename all of the ".ext" directories we just created to be 20 characters long - interactively.
    # per game, a timeout of 15 seconds is set, before the script continues automatically.
    # this makes sure that, if you're using this script to convert all your games while idle, it'll still get the job done.
}

gameCount () {
    find ./Unext/ -maxdepth 1 -mindepth 1 -type d | wc -l; # detect whether there are extracted games in ./Unext/ (and how many)
}

getFileCount () {
    find ./Unext/ -maxdepth 1 -mindepth 1 -type f -iname "${1}" | wc -l;
}

check_deps () {
    for tool in "$@"; do
        if ! command -v "$tool" &> /dev/null; then
            spinner_failuremsg 0 "Error: Dependency '${tool}' couldn't be satisfied. Aborting.";
            exit 1;
        fi
    done
}

#######################
#######################

cat <<-EOF
#######################
#     XBOX MANAGER    #
# for Aurora-enabled  #
#   Xbox360 systems   #
#######################
EOF

(sleep .2) & spinner $! "Welcome to the Xbox Manager";

isUsingPassword=$([[ -z $xbpass ]] && echo "no" || echo "yes"); # we don't want to show the password in terminal. We're just telling if one was used or not.
successfulFiles=0;

check_deps "fping" "7z" "lftp" "./extract-xiso";

params "$@"; # parse command-line arguments

( sleep .05; ) & spinner $! "Preparing to extract $(getFileCount "*.7z") .7z archives";
successful7zs=0;
for file in ./Unext/*.7z; do
    [ -e "$file" ] || continue;
    bfile=$(basename "$file"); # for the 7zip process, so it may find the proper file after going into ./Unext/
    (cd "./Unext" && 7z e "$bfile" -y > ../logs/7z.log) & spinner $! "Extracting ${file}...";

    if [[ $? != 0 ]]; then mv "${file}" "./dump"; # move archives which couldn't be extracted out of the way
    else ((successful7zs++)); ((successfulFiles++)); fi
done
if [[ $successful7zs -eq $(getFileCount "*.7z") ]]; then ( sleep .05; ) & spinner $! "Successfully extracted all files."; fi
(find ./Unext/ -maxdepth 1 ! -iname "*.iso" -type f -exec rm -f {} \; >/dev/null) & spinner $! "Cleaning up"; # delete all 7z archives and files other than the iso's from the Unext directory
if [[ $? != 0 ]]; then spinner_failuremsg 0 "Error: Cleaning up failed. Aborting."; exit 1; fi
( sleep .05; ) & spinner $! "Preparing to extract $(getFileCount "*.iso") .iso images";
successfulIsos=0;
for file in ./Unext/*.iso; do
    [ -e "$file" ] || continue;
    (./extract-xiso "${file}" -d "${file}.ext" > ./logs/extract-xiso.log) & spinner $! "Extracting ${file}...";

    if [[ $? != 0 ]]; then mv "${file}" "./dump"; # move isos which couldn't be extracted out of the way
    else ((successfulIsos++)); ((successfulFiles++)); fi
done
if [[ $successfulIsos -eq $(getFileCount "*.iso") ]]; then ( sleep .05; ) & spinner $! "Successfully extracted all files."; fi
(find ./Unext/ -maxdepth 1 -iname "*.iso" -exec rm -f {} \; > /dev/null) & spinner $! "Cleaning up"; # delete the .iso files since they're not required anymore.
if [[ $? != 0 ]]; then spinner_failuremsg 0 "Error: Cleaning up failed. Aborting."; exit 1; fi

interactiveRename;

[[ $skipUploads != 1 && $assumeYes != 1 ]] && # don't ask the user whether to upload anything if he already stated he wants to skip that (or do it (assume yes)).
    read -t 10 -n1 -p "Transfer games directly to ${xbuser}@${xbhost} (using password: ${isUsingPassword})? [y/N]" doTransfer &&
    echo "";

if [[ $assumeYes -eq 1 && $skipUploads != 1 ]]; then doTransfer="y"; fi
# here, we set a 10 seconds timeout. if nothing's typed, it'll just leave the games in the Unext/ directory.
case $doTransfer in
    "y")
    do_uploads;
    ;;
    *)
    echo "No transfer, not cleaning up. Extracted games remain in './Unext/'!";
    echo "If you want to transfer, run this script using the --upload (or -u) option!";
    ;;
esac

( sleep .2; ) & spinner_successmsg 0 "Done. Processed ${successfulFiles} files.";

#######################