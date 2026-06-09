# Kubernetes (k3s) Configuration for Homelab

Configurazione Kubernetes per il migration del homelab da Docker Compose a k3s.

---

## 📂 Struttura Directory

```
k3s/
├── docs/                           # 📚 Documentazione completa
│   ├── 00-migration-guide.md       # Guida principale - INIZIA QUI
│   ├── 01-setup-k3s-nixos.md       # Fase 1: Setup k3s
│   ├── 02-networking-ingress.md    # Fase 2: Networking & Ingress
│   ├── kubernetes-concepts.md      # Glossario concetti k8s
│   └── docker-to-k8s-cheatsheet.md # Conversione Docker→k8s
│
├── bootstrap/                      # ⚙️ Configurazione Flux CD
│   ├── flux-system/                # (Generato da Flux)
│   ├── apps-sync.yaml              # Sync k3s/apps/
│   └── infrastructure-sync.yaml    # Sync k3s/infrastructure/
│
├── infrastructure/                 # 🏗️ Componenti cluster-wide
│   ├── metallb/                    # LoadBalancer IP pool
│   ├── caddy-ingress/              # Ingress controller + SSL
│   └── (future: cert-manager, monitoring, backup)
│
├── apps/                           # 🚀 Applicazioni homelab
│   ├── homer/                      # Dashboard
│   ├── umami/                      # Analytics
│   ├── jellyfin/                   # Media server
│   └── ...                         # Altri servizi
│
└── templates/                      # 📋 Template per nuovi servizi
    └── service-template/
```

---

## 🚀 Quick Start

### Prima Volta

1. **Leggi la guida principale**:
   ```bash
   cat k3s/docs/00-migration-guide.md
   ```

2. **Segui le fasi in ordine**:
   - **Fase 1**: Setup k3s + Flux CD → `docs/01-setup-k3s-nixos.md`
   - **Fase 2**: Networking + Caddy → `docs/02-networking-ingress.md`
   - **Fase 3+**: Migrazione servizi (guide in arrivo)

### Aggiungere un Nuovo Servizio

```bash
# 1. Copia template
cp -r k3s/templates/service-template k3s/apps/myservice

# 2. Personalizza i file (vedi template/README.md)
cd k3s/apps/myservice
# Modifica deployment.yaml, service.yaml, ecc.

# 3. Commit e push (Flux applica automaticamente)
git add k3s/apps/myservice/
git commit -m "Add myservice"
git push
```

---

## 📖 Documentazione

### Guide Passo-Passo

| Guida | Descrizione | Quando Usarla |
|-------|-------------|---------------|
| [00-migration-guide.md](./docs/00-migration-guide.md) | **⭐ Inizia qui** - Panoramica completa | Prima di tutto |
| [01-setup-k3s-nixos.md](./docs/01-setup-k3s-nixos.md) | Setup k3s su NixOS + Flux CD | Fase 1 |
| [02-networking-ingress.md](./docs/02-networking-ingress.md) | MetalLB + Caddy + SSL | Fase 2 |

### Riferimenti

| Documento | Descrizione | Quando Usarlo |
|-----------|-------------|---------------|
| [kubernetes-concepts.md](./docs/kubernetes-concepts.md) | Glossario oggetti k8s | Quando non capisci un concetto |
| [docker-to-k8s-cheatsheet.md](./docs/docker-to-k8s-cheatsheet.md) | Conversione docker-compose → k8s | Durante migrazione servizi |

---

## 🛠️ Comandi Utili

### Verifica Stato Cluster

```bash
# Nodi
kubectl get nodes

# Tutti i pod
kubectl get pods -A

# Stato Flux
flux check
flux get kustomizations
```

### Deploy Manuale (per test)

```bash
# Applica singolo file
kubectl apply -f k3s/apps/myservice/deployment.yaml

# Applica directory intera (con Kustomize)
kubectl apply -k k3s/apps/myservice/

# Cancella
kubectl delete -k k3s/apps/myservice/
```

### Forza Sync Flux

```bash
# Sync apps
flux reconcile kustomization homelab-apps --with-source

# Sync infrastructure
flux reconcile kustomization homelab-infrastructure --with-source
```

### Debug

```bash
# Logs di un pod
kubectl logs -n homelab <pod-name>

# Shell in un pod
kubectl exec -it -n homelab <pod-name> -- /bin/sh

# Eventi recenti
kubectl get events -n homelab --sort-by='.lastTimestamp'

# Describe per dettagli
kubectl describe pod -n homelab <pod-name>
```

### k9s (UI Interattiva)

```bash
# Lancia k9s
k9s

# Comandi in k9s:
# :pods    - Lista pods
# :svc     - Lista services
# :deploy  - Lista deployments
# /        - Cerca
# l        - Logs
# d        - Describe
# Ctrl+C   - Esci
```

---

## 🗺️ Roadmap Migrazione

### ✅ Fase 0: Preparazione
- [x] Struttura repository
- [x] Documentazione completa
- [x] Template per servizi

### 🚧 Fase 1: Setup Base (In Corso)
- [ ] k3s configurato in NixOS
- [ ] Flux CD installato e funzionante
- [ ] Storage provisioner attivo

### 📋 Fase 2: Networking (Prossima)
- [ ] MetalLB per LoadBalancer
- [ ] Caddy Ingress Controller
- [ ] Certificati SSL automatici

### 📋 Fase 3-6: Migrazione Servizi
- [ ] Servizi semplici (Homer, Umami)
- [ ] Servizi storage (Jellyfin, Deluge, Paperless)
- [ ] Gestione avanzata (Secrets, Monitoring, Backup)
- [ ] Servizi rimanenti (~20 servizi)

---

## 🎯 Obiettivi

### Obiettivi di Apprendimento
- ✅ Capire i concetti fondamentali di Kubernetes
- ✅ Padroneggiare kubectl e gestione cluster
- ⏳ GitOps workflow con Flux
- ⏳ Gestione storage persistente
- ⏳ Networking e Ingress
- ⏳ Secrets management
- ⏳ Monitoring e observability

### Obiettivi Tecnici
- ✅ Cluster k3s single-node funzionante
- ⏳ Tutti i servizi Docker Compose migrati
- ⏳ SSL automatico con Let's Encrypt
- ⏳ Backup automatici
- ⏳ Documentazione completa per manutenzione
- 🔮 (Futuro) Espansione a multi-node

---

## 📊 Stato Servizi

| Servizio | Stato | Note |
|----------|-------|------|
| k3s cluster | ⏳ In setup | Fase 1 |
| Flux CD | ⏳ In setup | Fase 1 |
| MetalLB | 📋 Pianificato | Fase 2 |
| Caddy Ingress | 📋 Pianificato | Fase 2 |
| Homer | 📋 Pianificato | Fase 3 |
| Umami | 📋 Pianificato | Fase 3 |
| Jellyfin | 📋 Pianificato | Fase 4 |
| Deluge | 📋 Pianificato | Fase 4 |
| Paperless-ng | 📋 Pianificato | Fase 4 |
| Altri (~20) | 📋 Pianificato | Fase 6 |

**Legenda**:
- ✅ Completato
- 🚧 In corso
- ⏳ In setup
- 📋 Pianificato
- 🔮 Futuro

---

## 🤝 Contribuire

Questa è una guida viva! Durante la migrazione:

1. **Annota problemi** in `docs/troubleshooting.md`
2. **Migliora guide** con dettagli che avresti voluto sapere
3. **Aggiungi esempi** di servizi migrati
4. **Commit** tutto per reference futuro

---

## 📚 Risorse Esterne

### Kubernetes
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Kubernetes Basics Tutorial](https://kubernetes.io/docs/tutorials/kubernetes-basics/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)

### k3s
- [k3s Documentation](https://docs.k3s.io/)
- [k3s GitHub](https://github.com/k3s-io/k3s)

### Flux CD
- [Flux Documentation](https://fluxcd.io/docs/)
- [Flux Get Started](https://fluxcd.io/flux/get-started/)

### Homelab
- [Awesome Home Kubernetes](https://github.com/k8s-at-home/awesome-home-kubernetes)
- [k8s-at-home Charts](https://github.com/k8s-at-home/charts)

### Tools
- [k9s - Terminal UI](https://k9scli.io/)
- [Lens - Desktop UI](https://k8slens.dev/)
- [Kompose - Docker Compose converter](https://kompose.io/)

---

## 🆘 Help

**Domande?**
1. Controlla `docs/kubernetes-concepts.md` per concetti
2. Controlla `docs/docker-to-k8s-cheatsheet.md` per conversioni
3. Leggi la sezione Troubleshooting nelle guide
4. Cerca su [Stack Overflow](https://stackoverflow.com/questions/tagged/kubernetes)
5. Consulta [k8s Slack](https://kubernetes.slack.com/)

**Problemi?**
```bash
# Debug checklist
kubectl get pods -A                    # Tutti i pod running?
kubectl describe pod -n homelab <pod>  # Eventi e errori
kubectl logs -n homelab <pod>          # Logs applicazione
flux check                             # Flux funziona?
flux get kustomizations                # Sync OK?
```

---

**Inizia la tua migrazione**: [00-migration-guide.md](./docs/00-migration-guide.md)

**Buona fortuna! 🚀**
