#!/bin/bash

tun_count=$(ip -o link show | grep -c 'tun')
gpg_count=$(find $VPN_SECRET_DIR -maxdepth 1 -type f -name '*.gpg' | wc -l)
[ "$tun_count" -eq "$gpg_count" ]
