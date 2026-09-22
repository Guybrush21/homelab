# Nightly restic backup of everything that is not reproducible from git.
{ config, pkgs, ... }:

{
  services.restic.backups.homelab = {
    initialize = true;
    repository = "/mnt/murray/backup/restic";
    passwordFile = "/var/lib/homelab-data/secrets/restic-password";

    paths = [
      # All service state: databases, configs, everything the apps write.
      "/var/lib/homelab-data"
      # The git repo itself, which is also where /etc/nixos points. Covers the
      # system config even when GitHub is unreachable. Backed up by its real
      # path because restic stores symlinks as symlinks, so /etc/nixos would
      # save the link and none of the contents.
      "/home/jigen/code/homelab"
    ];

    exclude = [
      # Regenerable caches - Jellyfin's in particular gets large.
      "/var/lib/homelab-data/*/cache"
      "/var/lib/homelab-data/adguardhome/work/data/filters"
    ];

    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;          # catch up if the box was off
      RandomizedDelaySec = "45m";
    };

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];
  };
}
