#!/bin/bash

CONFIG="$HOME/SVXLinkJP/config/config.ini"

load_config()
{
    source "$CONFIG"
}

save_value()
{
    KEY=$1
    VALUE=$2

    sed -i "s|^${KEY}=.*|${KEY}=${VALUE}|" "$CONFIG"
}

backup_config()
{
    mkdir -p "$HOME/SVXLinkJP/backup"

    cp "$CONFIG" \
    "$HOME/SVXLinkJP/backup/config_$(date +%Y%m%d_%H%M%S).ini"
}
