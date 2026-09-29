# elaine Home Lab

Personal homelab running on **k3s**, managed with **Flux** GitOps. This repo is
the source of truth: both the Kubernetes manifests and the NixOS system config
live here.

Previously this was a pile of docker-compose files. Those are still in
`archive/` in case I need to go back.

## Server

AMD Ryzen 3 3200G, 16 GB RAM, NixOS 26.05. Hostname **elaine**.

| Disk                                  | Use                                                 |
| ------------------------------------- | --------------------------------------------------- |
| 238 GB SSD                            | `/` and `/var/lib/homelab-data` (all service state) |
| 2x2 TB HDD, RAID1 mdadm (`md/murray`) | `/mnt/murray` — media, backups                      |

## How it works

```
GitHub -> Flux -> k3s -> MetalLB -> Traefik -> pods
```

One `GitRepository` (`flux-system`) feeds two Kustomizations:

- `homelab-infrastructure` → `k3s/infrastructure` (MetalLB, Traefik, monitoring, Flux Operator)
- `homelab-apps` → `k3s/apps`, which `dependsOn` infrastructure

Flux do some magic in order to update the cluster according to the desired state that is this repository.

To see what the magic is doing: `flux.elaine.pw` (Flux Operator Web UI, behind
the Traefik dashboard login), `flux get all -A`, or Flux's own logs in Grafana
with `{namespace="flux-system"}`. The operator is installed **only** for the UI
and its metrics - there is no `FluxInstance`, so it doesn't manage Flux, which
is still the one from `flux bootstrap`.

## Repo structure

```
k3s/
  bootstrap/        flux itself + the two sync manifests
  infrastructure/   metallb, traefik, monitoring, flux-operator
  apps/             one folder per service
nixos/              system config - /etc/nixos symlinks here
archive/            the old docker-compose setup
```

Service state is **not** in this repo. It lives in `/var/lib/homelab-data/<service>/`
and gets mounted into pods with `hostPath`. Single node for now, so no reason to get
clever. One day...

Media lives on the RAID at `/mnt/murray/media/{film,tvseries,music,books,foto}`.

## NixOS

`/etc/nixos` is a symlink to `nixos/` in this repo, so `nixos-rebuild switch`
works normally and the system config is versioned like everything else.

```
nixos/configuration.nix   base system, firewall, NFS, RAID
nixos/k3s.nix             k3s server
nixos/backup.nix          restic
```

## Secrets

**SOPS + age.** Secrets are committed encrypted, which is why this repo can stay
public, hopefully. Files are named `*.enc.yaml` and Flux decrypts them on apply, still some magic.

```bash
sops k3s/apps/foo/secret.enc.yaml    # opens plaintext in $EDITOR, re-encrypts on save
```

The private key is at `/var/lib/homelab-data/secrets/age.agekey` and in my
password manager. Lose both and every secret in this repo is gone forever.

## Networking and DNS

`elaine.pw`, bought on namecheap in honor of governor Elaine from Monkey Island,
DNS on Cloudflare. `cloudflare-ddns` keeps the A record pointed at my dynamic
home IP.

MetalLB hands out `192.168.178.51-59`:

| IP    | Service          |
| ----- | ---------------- |
| `.51` | AdGuard (DNS)    |
| `.55` | Traefik (80/443) |

Traefik terminates TLS with Let's Encrypt via Cloudflare DNS-01, so certificates
work for LAN-only services without exposing anything.

**Split-horizon:** AdGuard rewrites `*.elaine.pw` → `192.168.178.55`, so traffic
from inside the house goes straight to Traefik instead of out to the ISP and
back. The Fritz!Box forwards to AdGuard (Internet → Account Information → DNS
Server, both fields `192.168.178.51`).

> Two gotchas that each cost me some time. **DNS Rebind Protection**
> silently drops upstream answers pointing at private IPs — `elaine.pw` has to
> be added to the hostname exceptions or nothing resolves. And if the DNSv6
> field has public resolvers in it, the router uses those and bypasses AdGuard
> entirely.

Only 80 and 443 are forwarded from the router.

## Monitoring

Grafana + Prometheus + Loki, in `k3s/infrastructure/monitoring`. Plain
manifests, no Helm, no Operator: every scrape target and every alert is in a
file you can read.

```
node-exporter, smartctl-exporter,  --scrape-->  Prometheus  --+
kube-state-metrics, kubelet/cAdvisor                          |
                                                              +-->  Grafana  (dashboards, Explore, alert rules)
/var/log/pods, systemd journal  --Alloy-->  Loki  ------------+
```

- **Grafana** at `grafana.elaine.pw`, user `admin`. Dashboards (folder
  _Homelab_), datasources and alert rules are provisioned from
  `config/` and `dashboards/` - edit them in git, not in the UI.
- **Logs**: the _Logs_ dashboard, or Explore → Loki, e.g.
  `{namespace="homelab", pod=~"immich.*"} |= "error"` or
  `{job="systemd-journal", unit="restic-backups-homelab.service"}`.
- **Alerts** (`config/grafana-alerting.yaml`): RAID degraded, SMART failing,
  disk or RAM almost full, backup failed or not run in 30h, pod in
  CrashLoopBackOff, scrape target down. Nothing is sent anywhere yet: the
  _Alerts_ dashboard (Grafana's home page) shows what is firing.
- 15 days of retention for both metrics and logs. Their data dirs are
  excluded from restic; Grafana's DB is not.

The admin password is in the secret:

```bash
sops -d k3s/infrastructure/monitoring/secret-grafana.enc.yaml   # GF_SECURITY_ADMIN_PASSWORD
```

To have an app scraped, give its pod the annotation `prometheus.io/scrape: "true"`
and name the container port `metrics`.

## Backup

`restic`, nightly, via a systemd timer defined in `nixos/backup.nix`. Keeps
7 daily / 4 weekly / 6 monthly.

```bash
restic -r /mnt/murray/backup/restic --password-file /var/lib/homelab-data/secrets/restic-password snapshots
```

Backed up: `/var/lib/homelab-data` and this repo. **Not** backed up: everything
in `/mnt/murray/media`. The photos and media files in particular sit on RAID1 and nothing else.
This is enough for now. It would be graeat to have a second location.

The restic password lives on the SSD, and the backup that would restore it is
encrypted with it. So it's in the password manager too.

TODO:

- [ ] off-site repository
- [ ] back up the media/foto

## Services

|                 |                                         |
| --------------- | --------------------------------------- |
| Homer           | `homer.elaine.pw` — dashboard           |
| AdGuard Home    | `adguard.elaine.pw` — DNS + ad blocking |
| Umami           | `umami.elaine.pw` — analytics           |
| Traefik         | `traefik.elaine.pw` — dashboard         |
| Flux Web UI     | `flux.elaine.pw` — GitOps status        |
| cloudflare-ddns | no UI                                   |
| Jellyfin        | `jellyfin.elaine.pw` — media            |
| Deluge          | `deluge.elaine.pw` — torrents           |
| Grafana         | `grafana.elaine.pw` — metrics, logs, alerts |

Coming: Paperless, Minecraft.

## Adding a service

```bash
mkdir k3s/apps/foo
# foo.yaml            Deployment + Service + IngressRoute
# secret.enc.yaml     secrets, via sops
# kustomization.yaml
```

**One file per component, not one per kind.** Everything belonging to the same
workload — its Deployment, Service and IngressRoute — lives in one file,
separated by `---` with a comment before each. This is what the Kubernetes docs
recommend ("put resources related to the same microservice or application tier
into the same file"), and it means removing a component is deleting one file
instead of hunting its pieces across three.

Apps with several components get one file each: `immich/` has `server.yaml`,
`database.yaml`, `redis.yaml`, `machine-learning.yaml`.

Add it to `k3s/apps/kustomization.yaml`, check it builds, push:

```bash
kubectl kustomize k3s/apps
```

If state needs to persist, put it in `/var/lib/homelab-data/foo/` and mount it
with `hostPath`. It'll get backed up automatically.
