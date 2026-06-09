# Guida Migrazione Homelab: Da Docker Compose a Kubernetes (k3s)

**Autore**: Nic  
**Server**: elaine (NixOS)  
**Data Inizio**: Giugno 2026  
**Obiettivo**: Imparare Kubernetes migrando progressivamente i servizi del homelab

---

## 📋 Indice

1. [Introduzione](#introduzione)
2. [Architettura Finale](#architettura-finale)
3. [Roadmap di Migrazione](#roadmap-di-migrazione)
4. [Guide Dettagliate per Fase](#guide-dettagliate)
5. [Risorse e Riferimenti](#risorse)

---

## Introduzione

### Situazione Attuale

**Hardware**:

- AMD Ryzen 3 3200G
- 16GB RAM (12GB + 3GB swap/zram)
- Storage:
  - 250GB NVMe (nvme0n1p2: `/`, nvme0n1p3: `/home`)
  - RAID1 2TB per media (precedentemente su Arch, da verificare su NixOS)

**Software**:

- OS: NixOS (migrato da Arch Linux)
- Container Runtime: Docker con ~27 servizi in docker-compose
- Reverse Proxy: Traefik con Cloudflare DNS
- Dominio: elaine.pw

**Servizi Principali**:

- **Media**: Jellyfin, Deluge
- **Productivity**: Paperless-ng, Bookstack, Gitea
- **Infrastructure**: Traefik, PostgreSQL, Samba
- **Monitoring**: Netdata, Prometheus
- **Altri**: Homer, Umami, AdGuard Home, Portainer, Wireguard, ecc.

### Perché Kubernetes?

**Motivazioni**:

1. **Apprendimento**: Esperienza pratica con Kubernetes per crescita professionale
2. **Riproducibilità**: Configurazione dichiarativa + GitOps
3. **Scalabilità futura**: Possibilità di aggiungere nodi
4. **Auto-healing**: Riavvio automatico container crashati
5. **NixOS synergy**: Configurazione dichiarativa a livello OS + cluster

**Perché k3s?**:

- Leggero: ~50MB binario unico vs centinaia di MB Kubernetes standard
- Single-node ready: Perfetto per homelab
- Production-ready: Usato da Rancher in produzione
- Batteries included: Traefik, Local Path Provisioner, ServiceLB built-in

---

## Architettura Finale

### Stack Tecnologico

```
┌─────────────────────────────────────────────────────────┐
│                    NixOS (Host OS)                      │
│  - Configurazione dichiarativa in /etc/nixos/          │
│  - k3s gestito come servizio systemd                   │
└─────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────┐
│                   k3s Cluster                           │
│                                                         │
│  ┌────────────────┐  ┌──────────────────┐              │
│  │  Flux CD       │  │  MetalLB         │              │
│  │  (GitOps)      │  │  (LoadBalancer)  │              │
│  └────────────────┘  └──────────────────┘              │
│                                                         │
│  ┌────────────────────────────────────────┐            │
│  │  Caddy Ingress Controller              │            │
│  │  - SSL/TLS (Cloudflare DNS challenge)  │            │
│  │  - Routing *.elaine.pw                 │            │
│  └────────────────────────────────────────┘            │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │           Applicazioni Homelab                  │   │
│  │  ┌─────────┐ ┌─────────┐ ┌──────────┐          │   │
│  │  │ Homer   │ │ Jellyfin│ │ Paperless│ ...      │   │
│  │  └─────────┘ └─────────┘ └──────────┘          │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  ┌────────────────────────────────────────┐            │
│  │  Storage                               │            │
│  │  - Local Path Provisioner              │            │
│  │  - HostPath per media (read-only)      │            │
│  │  - PersistentVolumes in /var/lib/      │            │
│  └────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────┘
```

### Flusso Richiesta HTTP

```
Internet
   ↓
Cloudflare DNS (elaine.pw → IP pubblico homelab)
   ↓
Router (port forward 80/443 → 192.168.178.X)
   ↓
MetalLB LoadBalancer IP (es. 192.168.178.50)
   ↓
Caddy Ingress Controller (Pod)
   ↓
Routing basato su hostname (homer.elaine.pw, jellyfin.elaine.pw, ...)
   ↓
Service (ClusterIP)
   ↓
Pod dell'applicazione
```

### Storage Strategy

**Persistent data** (`/var/lib/homelab-k8s/`):

- Gestito da k3s Local Path Provisioner
- PersistentVolumeClaim per ogni servizio
- Backup con Velero (futuro)

**Media files** (read-only):

- HostPath mount: `/home/jigen/media/` → pod Jellyfin, Deluge
- Nessuna modifica tramite k8s (solo lettura/scrittura da Deluge)

**Secrets**:

- SOPS + Age encryption
- File secrets cifrati in Git
- Flux decryption automatica al deploy

---

## Roadmap di Migrazione

### Approccio: Progressivo e Educativo

**Principio**: Imparare facendo, un passo alla volta.

Ogni fase introduce nuovi concetti Kubernetes con servizi di complessità crescente.

### Fase 0: Preparazione (1-2 ore)

**Obiettivo**: Familiarizzare con i concetti base

- [ ] Leggere [kubernetes-concepts.md](./kubernetes-concepts.md)
- [ ] Leggere [docker-to-k8s-cheatsheet.md](./docker-to-k8s-cheatsheet.md)
- [ ] Backup dei dati critici da Docker Compose
- [ ] Verificare che Git repository sia aggiornato

**Output**: Comprensione teorica dei concetti base

---

### Fase 1: Setup k3s + Flux CD (1-2 giorni)

**Guida**: [01-setup-k3s-nixos.md](./01-setup-k3s-nixos.md)

**Obiettivo**: Cluster k3s funzionante con GitOps

**Task**:

- [ ] Configurare k3s in NixOS (modulo declarativo)
- [ ] Installare kubectl e verificare accesso cluster
- [ ] Bootstrap Flux CD collegato al repository GitHub
- [ ] Configurare storage con Local Path Provisioner
- [ ] Testare sync automatico Git → Cluster

**Concetti appresi**:

- Cosa è un cluster Kubernetes
- Namespaces
- kubectl basics
- GitOps workflow con Flux

**Deliverable**:

- k3s attivo e gestito da systemd
- `kubectl get nodes` mostra il nodo ready
- Flux sincronizza da `k3s/apps/`
- Directory `/var/lib/homelab-k8s/` creata

---

### Fase 2: Networking & Ingress (1 giorno)

**Guida**: [02-networking-ingress.md](./02-networking-ingress.md)

**Obiettivo**: Caddy Ingress con SSL funzionante

**Task**:

- [ ] Deploy MetalLB per LoadBalancer support
- [ ] Configurare IP pool (192.168.178.50-59)
- [ ] Deploy Caddy come Ingress Controller
- [ ] Configurare Cloudflare DNS challenge per SSL
- [ ] Creare primo Ingress di test

**Concetti appresi**:

- Service types (ClusterIP, NodePort, LoadBalancer)
- Ingress e Ingress Controller
- ConfigMap per configuration files
- Secrets per credenziali

**Deliverable**:

- MetalLB assegna IP al LoadBalancer
- Caddy risponde su http://192.168.178.50
- Certificati SSL wildcard \*.elaine.pw funzionanti

---

### Fase 3: Primi Servizi (2-3 giorni)

**Guida**: [03-first-services.md](./03-first-services.md)

**Obiettivo**: Migrare Homer e Umami

**Task Homer**:

- [ ] Creare namespace `homelab`
- [ ] Definire PersistentVolumeClaim per config
- [ ] Creare Deployment
- [ ] Esporre con Service
- [ ] Configurare Ingress (homer.elaine.pw)
- [ ] Testare accesso

**Task Umami**:

- [ ] Deploy PostgreSQL dedicato (o riutilizzare esistente)
- [ ] Configurare Secret per DB credentials
- [ ] Deploy Umami con env variables
- [ ] Ingress per umami.elaine.pw

**Concetti appresi**:

- Deployment e ReplicaSet
- Pod lifecycle
- PersistentVolume e PersistentVolumeClaim
- Service discovery interno
- Environment variables e Secrets

**Deliverable**:

- Homer accessibile da browser
- Umami funzionante con tracking analytics
- Comprensione completa del workflow Deployment → Service → Ingress

---

### Fase 4: Servizi con Storage Complesso (2-3 giorni)

**Guida**: [04-storage-services.md](./04-storage-services.md)

**Obiettivo**: Jellyfin, Deluge, Paperless-ng

**Jellyfin**:

- [ ] GPU passthrough (`/dev/dri/*`)
- [ ] HostPath mount per media (read-only)
- [ ] PVC per config
- [ ] SecurityContext per group membership
- [ ] Ingress con WebSocket support

**Deluge**:

- [ ] Port range exposure (50101-50300)
- [ ] Shared volume per download
- [ ] StatefulSet vs Deployment

**Paperless-ng**:

- [ ] Multi-container pod (app + Redis)
- [ ] Multiple PVCs
- [ ] initContainer per DB readiness
- [ ] Ingress per WebUI

**Concetti appresi**:

- SecurityContext (fsGroup, supplementalGroups)
- Device mounting
- StatefulSet
- initContainers
- Multi-container pods
- Volume types (emptyDir, hostPath, PVC)

**Deliverable**:

- Jellyfin con hardware acceleration funzionante
- Deluge scarica in `/home/jigen/media/`
- Paperless-ng con gestione documenti

---

### Fase 5: Gestione Avanzata (3-4 giorni)

**Guida**: [05-advanced-management.md](./05-advanced-management.md)

**Obiettivo**: Secrets, Monitoring, Backup

**Secrets Management**:

- [ ] Installare SOPS + Age
- [ ] Generare encryption key
- [ ] Configurare `.sops.yaml`
- [ ] Migrare secrets da `.env` a SOPS
- [ ] Flux decryption automatica

**Monitoring**:

- [ ] Deploy Kubernetes Dashboard
- [ ] Installare Prometheus + Grafana (opzionale)
- [ ] Configurare alert su Discord/Email

**Backup**:

- [ ] Installare Velero
- [ ] Configurare backup schedule
- [ ] Backup su `/home/backup/` (RAID1)
- [ ] Testare restore

**Concetti appresi**:

- Secrets encryption at rest
- RBAC (Role-Based Access Control)
- ServiceAccount
- CronJob
- DaemonSet (per monitoring agents)

**Deliverable**:

- Secrets cifrati in Git
- Dashboard k8s accessibile
- Backup automatici notturni
- Recovery testato con successo

---

### Fase 6: Migrazione Servizi Rimanenti (variabile)

**A questo punto sei autonomo!**

Servizi da migrare (in ordine suggerito):

**Gruppo A - Semplici** (1 giorno):

- [ ] Netdata
- [ ] Portainer → Lens o k9s
- [ ] Watchtower → Flux Image Automation
- [ ] AdGuard Home

**Gruppo B - Medi** (2-3 giorni):

- [ ] Gitea
- [ ] Bookstack
- [ ] PostgreSQL condiviso (se non già fatto)
- [ ] Samba (o meglio NFS server in k8s?)
- [ ] Wireguard

**Gruppo C - Complessi** (caso per caso):

- [ ] Keycloak (SSO)
- [ ] Minecraft server (StatefulSet)
- [ ] Servizi con build custom (\_appsmith, \_budibase)
- [ ] Servizi deprecati (valuta se mantenere)

**Approccio per ogni servizio**:

1. Analizza `docker-compose.yaml`
2. Identifica componenti: volumes, env, networks, ports, depends_on
3. Traduci in k8s: PVC, ConfigMap/Secret, Service, Ingress
4. Usa template in `k3s/templates/service-template/`
5. Crea manifest in `k3s/apps/[service-name]/`
6. Commit e push (Flux lo deploya automaticamente)
7. Testa funzionalità
8. Se OK, ferma container Docker
9. Documenta eventuali differenze/workaround

---

## Guide Dettagliate

Le guide sono organizzate per fase con istruzioni passo-passo:

1. **[Setup k3s su NixOS](./01-setup-k3s-nixos.md)** - Installazione e configurazione cluster
2. **[Networking & Ingress](./02-networking-ingress.md)** - MetalLB + Caddy + SSL
3. **[Primi Servizi](./03-first-services.md)** - Homer e Umami (servizi semplici)
4. **[Servizi Storage](./04-storage-services.md)** - Jellyfin, Deluge, Paperless (complessi)
5. **[Gestione Avanzata](./05-advanced-management.md)** - Secrets, Monitoring, Backup

### Documenti di Riferimento

- **[Concetti Kubernetes](./kubernetes-concepts.md)** - Glossario e spiegazione oggetti k8s
- **[Docker → k8s Cheatsheet](./docker-to-k8s-cheatsheet.md)** - Comparazione docker-compose vs k8s
- **[Troubleshooting](./troubleshooting.md)** - Problemi comuni e soluzioni

---

## Risorse

### Documentazione Ufficiale

- [Kubernetes Docs](https://kubernetes.io/docs/)
- [k3s Documentation](https://docs.k3s.io/)
- [Flux CD Docs](https://fluxcd.io/docs/)
- [Caddy Documentation](https://caddyserver.com/docs/)

### Tools Essenziali

**CLI**:

- `kubectl` - Kubernetes CLI
- `k9s` - Terminal UI per Kubernetes (altamente raccomandato!)
- `flux` - Flux CD CLI
- `sops` - Secrets encryption

**Install su NixOS**:

```nix
environment.systemPackages = with pkgs; [
  kubectl
  k9s
  fluxcd
  sops
  age  # per SOPS encryption
];
```

### Learning Resources

**Kubernetes Basics**:

- [Kubernetes Basics Tutorial](https://kubernetes.io/docs/tutorials/kubernetes-basics/)
- [Play with Kubernetes](https://labs.play-with-k8s.com/) - Playground online

**GitOps**:

- [Flux Getting Started](https://fluxcd.io/flux/get-started/)
- [GitOps Principles](https://opengitops.dev/)

**Homelab Specifici**:

- [Awesome Home Kubernetes](https://github.com/k8s-at-home/awesome-home-kubernetes)
- [k8s-at-home Charts](https://github.com/k8s-at-home/charts)

---

## Note Finali

### Coesistenza Docker + k3s

Durante la migrazione, Docker e k3s coesisteranno:

- **Docker**: Continua a gestire servizi non ancora migrati
- **k3s**: Gestisce servizi nuovi migrati

**Port conflicts**: Assicurati che servizi non usino stesse porte.

**Network isolation**: Docker usa bridge network, k3s usa CNI (Flannel di default).

### Rollback Plan

Se qualcosa va male:

1. **Servizio singolo**: `kubectl delete -f k3s/apps/[service-name]/`
2. **Cluster completo**:
   ```bash
   sudo systemctl stop k3s
   # Torna a usare Docker Compose
   ```
3. **NixOS rollback**: Riavvia e seleziona generazione precedente in GRUB

### Performance Considerations

Con 8GB RAM:

- k3s: ~500MB
- Flux: ~100MB
- Caddy: ~50MB
- **Totale overhead**: ~650MB vs ~200MB Docker

**Rimangono ~4.3GB** per le applicazioni (vs ~4.8GB con Docker).

Consideriamo accettabile per benefici ottenuti.

### Quando Considerare Espansione

Aggiungi nodi quando:

- Superi 80% utilizzo RAM costante
- Vuoi alta disponibilità (multi-replica)
- Vuoi separare workload (es. nodo per media, nodo per productivity)

---

## Contributi e Feedback

Questa è una guida viva. Mentre procedi:

- Annota problemi incontrati in `troubleshooting.md`
- Migliora le guide con dettagli mancanti
- Commit tutto nel repository per reference futuro

**Buona migrazione! 🚀**

---

**Prossimo Step**: Leggi [01-setup-k3s-nixos.md](./01-setup-k3s-nixos.md) e inizia!
