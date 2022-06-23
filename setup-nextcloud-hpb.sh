#!/bin/bash

set -eo pipefail

# Sane defaults (Don't override these settings here!)
# Can be overridden by specifying a settings file as first parameter.
# See settings.sh
DRY_RUN=false
UNATTENTED_INSTALL=false
NEXTCLOUD_SERVER_FQDN="" # Ask user
SERVER_FQDN=""           # Ask user
SSL_CERT_PATH="/etc/ssl/certs/nextcloud-hpb.crt"
SSL_CERT_KEY_PATH="/etc/ssl/private/nextcloud-hpb.key"
LOGFILE_PATH="setup-nextcloud-hpb-$(date +%Y-%m-%dT%H:%M:%SZ).log"
TMP_DIR_PATH="./tmp"
SECRETS_FILE_PATH="" # Ask user

function show_dialogs() {
    if [ "$DRY_RUN" = "" ]; then
        if [ "$UNATTENTED_INSTALL" = true ]; then
            log "Can't go on since this is an unattended install and  I'm missing DRY_RUN!"
            exit 1
        fi

        if whiptail --title "Dry-Run Mode" --yesno "Do you want to run in dry $(
        )mode? This will ensure that no serious changes get done to your $(
        )system." 10 65 --defaultno; then
            DRY_RUN=true
        else
            DRY_RUN=true
        fi
    fi
    log "Using '$DRY_RUN' for DRY_RUN".

    if [ "$NEXTCLOUD_SERVER_FQDN" = "" ]; then
        if [ "$UNATTENTED_INSTALL" = true ]; then
            log "Can't go on since this is an unattended install and I'm" \
                "missing NEXTCLOUD_SERVER_FQDN!"
            exit 1
        fi

        NEXTCLOUD_SERVER_FQDN=$(
            whiptail --title "Nextcloud Server Domain" \
                --inputbox "Please input your Nextcloud Server domain. $(
                )No http(s) or similar! And don't input the domain for $(
                )the High-Performance backend yet!" 10 65 \
                "nextcloud.example.org" 3>&1 1>&2 2>&3
        )
    fi
    log "Using '$NEXTCLOUD_SERVER_FQDN' for NEXTCLOUD_SERVER_FQDN".

    if [ "$SERVER_FQDN" = "" ]; then
        if [ "$UNATTENTED_INSTALL" = true ]; then
            log "Can't go on since this is an unattended install and I'm" \
                "missing SERVER_FQDN!"
            exit 1
        fi

        SERVER_FQDN=$(
            whiptail --title "High-Performance Backend Server Domain" \
                --inputbox "Please input your High-Performance backend $(
                )server domain. (No http(s) or similar!)\n$(
                )Also please note that this domain should already exist $(
                )or else SSL certificate creation will fail!" \
                10 65 "nc-workhorse.example.org" 3>&1 1>&2 2>&3
        )
    fi
    log "Using '$SERVER_FQDN' for SERVER_FQDN".

    if [ "$SSL_CERT_PATH" = "" ]; then
        if [ "$UNATTENTED_INSTALL" = true ]; then
            log "Can't go on since this is an unattended install and I'm" \
                "missing SSL_CERT_PATH!"
            exit 1
        fi

        SSL_CERT_PATH=$(
            whiptail --title "SSL Certificate file path" \
                --inputbox "Please input a path where the SSL certificate $(
                )(.crt) should be saved." \
                10 65 "/path/to/ssl/certificate.crt" 3>&1 1>&2 2>&3
        )
    fi
    log "Using '$SSL_CERT_PATH' for SSL_CERT_PATH".

    if [ "$SSL_CERT_KEY_PATH" = "" ]; then
        if [ "$UNATTENTED_INSTALL" = true ]; then
            log "Can't go on since this is an unattended install and I'm" \
                "missing SSL_CERT_KEY_PATH!"
            exit 1
        fi

        SSL_CERT_KEY_PATH=$(
            whiptail --title "SSL Certificate key-file path" \
                --inputbox "Please input a path where the SSL certificate $(
                )key file (.key) should be saved." \
                10 65 "/path/to/ssl/private-key.key" 3>&1 1>&2 2>&3
        )
    fi
    log "Using '$SSL_CERT_KEY_PATH' for SSL_CERT_KEY_PATH".

    if [ "$LOGFILE_PATH" = "" ]; then
        if [ "$UNATTENTED_INSTALL" = true ]; then
            log "Can't go on since this is an unattended install and I'm" \
                "missing LOGFILE_PATH!"
            exit 1
        fi

        LOGFILE_PATH=$(
            whiptail --title "Logfile path" \
                --inputbox "Please input a path to which this script can put $(
                )a logging file. The directory, it's parents and the file get $(
                )created automatically." 10 65 \
                "setup-nextcloud-hpb-$(date +%Y-%m-%dT%H:%M:%SZ).log" \
                3>&1 1>&2 2>&3
        )
    fi
    log "Using '$LOGFILE_PATH' for LOGFILE_PATH"

    if [ "$TMP_DIR_PATH" = "" ]; then
        if [ "$UNATTENTED_INSTALL" = true ]; then
            log "Can't go on since this is an unattended install and I'm" \
                "missing TMP_DIR_PATH!"
            exit 1
        fi

        TMP_DIR_PATH=$(
            whiptail --title "Temporary directory for configuration" \
                --inputbox "Please input a directory path in which this "$(
                )"script can put temporary configuration files. "$(
                )"The directory and it's parents get created automatically." \
                10 65 "./tmp" 3>&1 1>&2 2>&3
        )
    fi
    log "Using '$TMP_DIR_PATH' for TMP_DIR_PATH".

    if [ "$SECRETS_FILE_PATH" = "" ]; then
        if [ "$UNATTENTED_INSTALL" = true ]; then
            log "Can't go on since this is an unattended install and I'm" \
                "missing SECRETS_FILE_PATH!"
            exit 1
        fi

        SECRETS_FILE_PATH=$(
            whiptail --title "Secrets, passwords and configuration file" \
                --inputbox "Please input a path to a file in which all "$(
                )"secrets, passwords and configuration should be stored.\n"$(
                )"The directory and it's parents get created automatically." \
                10 65 "./nextcloud-hpb.secrets" 3>&1 1>&2 2>&3
        )
    fi
    log "Using '$SECRETS_FILE_PATH' for SECRETS_FILE_PATH".
}

function log() {
    echo -e "$@" 2>&1 | tee -a $LOGFILE_PATH
}

# Deploys target_file_path to source_file_path while respecting
# potential custom user config. The user will be asked before overwriting files.
# param 1: source_file_path
# param 2: target_file_path
# returns: 1 if already deployed and 0 if not.
function deploy_file() {
    source_file_path="$1"
    target_file_path="$2"
    log "Deploying $target_file_path"
    if [[ -s "$target_file_path" ]]; then
        checksum_deployed=$(sha256sum "$target_file_path" | cut -d " " -f1)
        checksum_expected=$(sha256sum "$source_file_path" | cut -d " " -f1)
        if [ "${checksum_deployed}" = "${checksum_expected}" ]; then
            log "$target_file_path was already deployed."
            return 1
        else
            if [ "$UNATTENTED_INSTALL" = true ]; then
                cp "$source_file_path" "$target_file_path"
            else
                read -p "Overwrite file '$target_file_path'? [YyNn] " -n 1 -r && echo
                if [[ $REPLY =~ ^[YyJj]$ ]]; then
                    log "$target_file_path to be updated deployed."
                    is_dry_run || cp "$source_file_path" "$target_file_path"
                else
                    log "$target_file_path won't be updated."
                fi
            fi
        fi
    else
        # Target file is empty or doesn't exist.
        is_dry_run || cp "$source_file_path" "$target_file_path"
    fi
    return 0
}

function check_root_perm() {
    if [[ $(id -u) -ne 0 ]]; then
        log "Please run the this (setup-nextcloud-hpb) script as root."
        exit 1
    fi
}

function check_debian_system() {
    # File exists and not empty
    if ! [ -s /etc/debian_version ]; then
        log "Couldn't read /etc/debian_version! Is this a debian system?"
        exit 1
    else
        DEBIAN_VERSION=$(cat /etc/debian_version)

        # Quick hack for debian testing (currently bookworm)
        if [[ "$DEBIAN_VERSION" = "bookworm/sid" ]]; then
            DEBIAN_VERSION="11.3"
        fi

        if ! [[ $DEBIAN_VERSION =~ [0-9] ]]; then
            log "Debian version '$DEBIAN_VERSION' not supported!"
            exit 1
        fi

        DEBIAN_MAJOR_VERSION=$(echo $DEBIAN_VERSION | grep -o -E "[0-9][0-9]")
    fi
}

function is_dry_run() {
    if [ "$DRY_RUN" == true ]; then
        return 0
    else
        return 1
    fi
}

function main() {
    check_root_perm

    check_debian_system

    # Load Settings (hopefully vars above get overwritten!)
    SETTINGS_FILE="$1"
    if [ -s "$SETTINGS_FILE" ]; then
        log "Loading settings file '$SETTINGS_FILE'…"
        source "$SETTINGS_FILE"
    else
        log "No settings file specified using defaults or asking user for input."
    fi

    # Let's check if we should open dialogs.
    if [ "$UNATTENTED_INSTALL" != true ]; then
        CHOICES=$(whiptail --title "Select services" --separate-output \
            --checklist "Please select/deselect the services you want to $(
            )install with the space key." 15 110 2 \
            "1" "Install Collabora (coolwsd, nginx, certbot)" ON \
            "2" "Install Signaling (nats-server, coturn, janus, nextcloud-spreed-signaling, nginx, certbot)" ON \
            3>&1 1>&2 2>&3)

        if [ -z "$CHOICES" ]; then
            log "No service was selected (user hit Cancel or unselected all options) Exiting…"
            exit 0
        else
            for CHOICE in $CHOICES; do
                case "$CHOICE" in
                "1")
                    log "Collabora will be installed."
                    SHOULD_INSTALL_COLLABORA=true
                    SHOULD_INSTALL_NGINX=true
                    SHOULD_INSTALL_CERTBOT=true
                    ;;
                "2")
                    log "Signaling will be installed."
                    SHOULD_INSTALL_SIGNALING=true
                    SHOULD_INSTALL_NGINX=true
                    SHOULD_INSTALL_CERTBOT=true
                    ;;
                *)
                    log "Unsupported service $CHOICE!" >&2
                    exit 1
                    ;;
                esac
            done
        fi
    fi

    show_dialogs

    if [ -s "$LOGFILE_PATH" ]; then
        rm -v $LOGFILE_PATH |& tee -a $LOGFILE_PATH
    fi

    log "$(date)"

    is_dry_run &&
        log "Running in dry-mode. This script won't actually do anything on" \
            "your system!"

    if [ "$UNATTENTED_INSTALL" = true ]; then
        log "Trying unattented installation."
    fi

    if ! [ -e "$TMP_DIR_PATH" ]; then
        log "Creating '$TMP_DIR_PATH'."
        mkdir -p "$TMP_DIR_PATH" 2>&1 | tee -a $LOGFILE_PATH
    else
        REPLY=""
        while ! [[ $REPLY =~ ^[YyJj]$ ]]; do
            if [ "$UNATTENTED_INSTALL" = false ]; then
                read -p "Delete * in '$TMP_DIR_PATH'? [Yy] " -n 1 -r && echo
            else
                break
            fi
        done

        log "Deleted contents of '$TMP_DIR_PATH'."
        rm -vr "$TMP_DIR_PATH"/* 2>&1 | tee -a $LOGFILE_PATH || true
    fi

    log "Moving config files into '$TMP_DIR_PATH'."
    cp -rv data/* "$TMP_DIR_PATH" 2>&1 | tee -a $LOGFILE_PATH

    log "Deleting every '127.0.1.1' entry in /etc/hosts."
    is_dry_run || sed -i "/127.0.1.1/d" /etc/hosts

    entry="127.0.1.1 $SERVER_FQDN $(hostname)"
    log "Deploying '$entry' in /etc/hosts."
    is_dry_run || echo "$entry" >>/etc/hosts

    scripts=('src/setup-collabora.sh' 'src/setup-signaling.sh'
        'src/setup-nginx.sh' 'src/setup-certbot.sh')
    for script in "${scripts[@]}"; do
        log "Sourcing '$script'."
        source "$script"
    done

    install_collabora
    install_signaling
    install_nginx
    install_certbot

    log "Every installation completed."

    log "======================================================================"
    collabora_print_info &&
        log "======================================================================"
    signaling_print_info &&
        log "======================================================================"
    nginx_print_info &&
        log "======================================================================"
    certbot_print_info
    log "======================================================================"

    is_dry_run || mkdir -p "$(dirname "$SECRETS_FILE_PATH")"
    is_dry_run || touch "$SECRETS_FILE_PATH"
    is_dry_run || chmod 0640 "$SECRETS_FILE_PATH"

    echo -e "This file contains secrets, passwords and configuration" \
        "generated by the Nextcloud High-Performance backend setup." \
        >$SECRETS_FILE_PATH
    collabora_write_secrets_to_file "$SECRETS_FILE_PATH"
    signaling_write_secrets_to_file "$SECRETS_FILE_PATH"
    nginx_write_secrets_to_file "$SECRETS_FILE_PATH"
    certbot_write_secrets_to_file "$SECRETS_FILE_PATH"

    log "\nThank you for using this script.\n"
}

# Execute main function.
main "$1"

set +eo pipefail
