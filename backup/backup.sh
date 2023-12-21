#!/bin/sh
export RESTIC_PASSWORD=restic
restic -r /home/jigen/backup/restic-homelab --verbose backup /home/vol-docker
restic -r /home/jigen/backup//restic-homelab forget --keep-last 12 --prune
