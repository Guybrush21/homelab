# Nightly restic backup of everything that is not reproducible from git.
{ config, pkgs, ... }:

let
  kubectl = "${pkgs.kubectl}/bin/kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml";
  sqlite3 = "${pkgs.sqlite}/bin/sqlite3";
  dumpDir = "/var/lib/homelab-data/dumps";

  # Copying a live database's files gives you whatever was half-written at that
  # instant; restoring it may or may not work. These are consistent snapshots
  # taken right before restic runs, and they are what to restore from.
  #
  # Every database is attempted even if one fails, and a failed dump keeps the
  # previous good file. The unit still exits non-zero so the Grafana alert
  # fires, but the backup itself runs anyway.
  dumpScript = pkgs.writeShellScript "homelab-db-dump" ''
    set -uo pipefail
    umask 077
    mkdir -p ${dumpDir}
    failed=0

    # pg_dumpall runs inside the pod, so the client always matches the server
    # version. POSTGRES_USER is the superuser the image created.
    postgres() {
      local name=$1 deploy=$2 out=${dumpDir}/$1.sql
      if ${kubectl} -n homelab exec deploy/"$deploy" -c postgres -- \
          sh -c 'pg_dumpall --clean --if-exists -U "$POSTGRES_USER"' > "$out.tmp" \
          && [ -s "$out.tmp" ]; then
        mv "$out.tmp" "$out"
        echo "$name: $(du -h "$out" | cut -f1)"
      else
        rm -f "$out.tmp"
        echo "$name: dump FAILED" >&2
        failed=1
      fi
    }

    # .backup takes the SQLite lock properly, so it's safe while the app writes.
    sqlite() {
      local name=$1 src=$2 out=${dumpDir}/$1.sqlite
      if ${sqlite3} "$src" ".timeout 30000" ".backup '$out.tmp'"; then
        mv "$out.tmp" "$out"
        echo "$name: $(du -h "$out" | cut -f1)"
      else
        rm -f "$out.tmp"
        echo "$name: backup FAILED" >&2
        failed=1
      fi
    }

    postgres immich immich-db
    postgres umami  umami-db

    sqlite papra    /var/lib/homelab-data/papra/app-data/db/db.sqlite
    sqlite grafana  /var/lib/homelab-data/monitoring/grafana/grafana.db
    sqlite jellyfin /var/lib/homelab-data/jellyfin/config/data/data/jellyfin.db

    exit $failed
  '';
in
{
  systemd.services.homelab-db-dump = {
    description = "Consistent dumps of the homelab databases, for restic";
    after = [ "k3s.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = dumpScript;
    };
  };

  # Wants, not Requires: a failed dump must not skip the whole night's backup.
  # After on a oneshot waits for it to finish, so the dumps are fresh.
  systemd.services.restic-backups-homelab = {
    wants = [ "homelab-db-dump.service" ];
    after = [ "homelab-db-dump.service" ];
  };

  services.restic.backups.homelab = {
    initialize = true;
    repository = "/mnt/murray/backup/restic";
    passwordFile = "/var/lib/homelab-data/secrets/restic-password";

    paths = [
      # All service state: databases, configs, everything the apps write.
      # Includes dumps/, written just before by homelab-db-dump.
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
      # Metrics and logs: large, churn every minute, and only worth anything
      # while the box is alive. Grafana's DB is still backed up.
      "/var/lib/homelab-data/monitoring/prometheus"
      "/var/lib/homelab-data/monitoring/loki"
      "/var/lib/homelab-data/monitoring/alloy"
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
