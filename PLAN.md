# Homelab migration plan — docker-compose → k3s

Host `elaine`, NixOS 26.05, single-node k3s + Flux, public repo `Guybrush21/homelab`.

## Current state

- **k3s + Flux working.** Traefik v3 (LB `192.168.178.55`, ACME via Cloudflare DNS-01), MetalLB, homer deployed.
- **`homelab-apps` Kustomization is broken.** `k3s/apps/ddclient/kustomization.yaml` lists `secret.yaml`, which `k3s/.gitignore` excludes — kustomize build fails, so no app updates.
- **ddclient is dead** → `elaine.pw` A record is stale (`151.49.109.67`, actual WAN `151.95.199.212`) → every `*.elaine.pw` name is unreachable. Homer itself is healthy; this is the only reason it looks broken.
- Local checkout is 23 commits behind `origin/master` and still holds abandoned ArgoCD manifests.
- No backups. All state on the non-redundant SSD.

## Target

| Layer | Components |
|---|---|
| Infra | Traefik, MetalLB, AdGuard Home, ddclient |
| Apps | Homer, Jellyfin, Deluge, Immich, Paperless-ngx, Umami, Netdata, Minecraft |
| Host (NixOS) | NFS, restic, Samba (later) |
| Dropped | all `_`-prefixed, gitea, bookstack, keycloak, couchdb, dand, taskwarrior, photoview, prometheus, portainer, watchtower, nginx-proxy-manager, caddy, pihole, wireguard, tesla |

### Layout

```
~/code/homelab/            git repo, code only
/var/lib/homelab-data/     all app state (SSD, ~3 GB today)
/var/lib/homelab-data/secrets/age.agekey   0600, never committed
/mnt/murray/media/         RAID: film, tvseries, music, foto
/mnt/murray/immich/        RAID: Immich managed library
/mnt/murray/backup/restic/ RAID: nightly restic of homelab-data
```

### Network

- MetalLB pool `192.168.178.51-59` (DHCP starts at .100). Traefik `.55`, AdGuard `.51`.
- AdGuard wildcard rewrite `*.elaine.pw → 192.168.178.55`; Fritz!Box hands AdGuard out as LAN DNS. LAN traffic stops hairpinning.
- Internet-facing: **umami**, **minecraft**. Everything else LAN-only.

### Secrets — SOPS + age

One age keypair. Public key in `.sops.yaml` (safe to publish). Private key on disk at `/var/lib/homelab-data/secrets/age.agekey` + password manager, and as k8s secret `sops-age` in `flux-system`. Flux Kustomizations get `spec.decryption.provider: sops`. Edit with `sops k3s/apps/<svc>/secret.enc.yaml`.

Existing `cloudflare-token` and `dashboard-users` are read out of the cluster and re-encrypted as-is — no rotation needed, no disruption.

---

## Phases

Each phase leaves the system working.

### 0 — Repo hygiene

- `git reset --hard origin/master`; delete dead ArgoCD manifests, `k3s/doc/`, `nixos-migration.md`.
- Move repo to `~/code/homelab`.
- Move data `/var/lib/homelab/<svc>/container-data/` → `/var/lib/homelab-data/<svc>/`, preserving ownership.
- Old compose dirs → `archive/` (restorable if this goes badly).
- Consolidate to **one** GitRepository + Kustomizations `infrastructure` → `apps` (`dependsOn`), so a broken app can no longer block infra.

### 1 — Unbreak Flux, restore DNS

- Generate age key, write `.sops.yaml`, create `sops-age` secret, enable decryption on both Kustomizations.
- Re-encrypt `cloudflare-token`, `dashboard-users` into git.
- Commit ddclient's `secret.enc.yaml` → apps sync goes green → ddclient deploys → A record updates.
- **Homer reachable again.**

### 2 — AdGuard + split-horizon DNS

- Widen MetalLB pool to `.51-.59`.
- AdGuard on `.51`, reusing `adguardhome/container-data/{conf,work}` (14 MB).
- Wildcard rewrite; point Fritz!Box DNS at `.51`.

### 3 — Jellyfin + Deluge

- Jellyfin: reuse `config` + `cache` (845 MB). hostPath `/mnt/murray/media/{film,tvseries,music,book}` read-only. iGPU transcoding via `/dev/dri/renderD128` (needs `hardware.graphics.enable`, render gid 303, video gid 26).
- Deluge: reuse `config` (29 MB). Downloads → `/mnt/murray/media`. Keep ports 50101-50300.

### 4 — Immich

- **External library**, read-only, over `/mnt/murray/media/foto` — DSLR archive stays exactly as it is, Immich never moves or deletes files.
- Managed library at `/mnt/murray/immich/` for anything uploaded later.
- Postgres (pgvecto.rs) + Redis, state on SSD. LAN-only.

### 5 — Remaining apps

- Paperless-ngx: reuse `data,media,export,consume,pgdata` (97 MB), stays on SSD.
- Umami + postgres: reuse `umami-db-data` (65 MB). Public.
- Netdata: reuse `netdataconfig`. Drop the docker-socket-proxy — read containerd instead.
- Minecraft: reuse `data` (348 MB). Public port.

### 6 — Operations

- restic timer: `/var/lib/homelab-data` → `/mnt/murray/backup/restic`, nightly, declared in NixOS. Covers SSD failure and deletion, not fire/theft — off-site target later.
- Fix `mdmonitor.service` (currently failed: no alert destination).
- Re-enable `zramSwap` once memtest86+ has passed.

## Open

- mdmonitor alert channel: `wall` + journal, or ntfy/Telegram push?
- memtest86+ result — unknown. If RAM is still suspect, stop after phase 1.
