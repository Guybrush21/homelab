#!/bin/sh
# password redatta - il repository che proteggeva (/mnt/murray/backup/restic-homelab)
# e stato eliminato il 2026-09-22. Sostituito da restic via nixos/backup.nix.
export RESTIC_PASSWORD=<redacted>
restic -r /home/jigen/backup/restic-homelab --verbose backup /home/vol-docker
restic -r /home/jigen/backup//restic-homelab forget --keep-last 12 --prune
