# Fase 1: Setup k3s su NixOS

**Durata stimata**: 1-2 giorni (se nuovo a k3s/NixOS)  
**Prerequisiti**: Accesso SSH al server NixOS  
**Obiettivo**: Cluster k3s funzionante con Flux CD e GitOps

---

## 📚 Cosa Imparerai

- Come configurare k3s in modo dichiarativo con NixOS
- Cos'è un cluster Kubernetes e come interagirci
- Namespaces e organizzazione risorse
- GitOps workflow con Flux CD
- Storage provisioning in k3s

---

## Panoramica Architettura

```
┌─────────────────────────────────────────┐
│         NixOS Host (elaine)             │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │   k3s systemd service             │  │
│  │   - API Server                    │  │
│  │   - Controller Manager            │  │
│  │   - Scheduler                     │  │
│  │   - Kubelet                       │  │
│  │   - Local Path Provisioner        │  │
│  └───────────────────────────────────┘  │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │   /var/lib/rancher/k3s/           │  │
│  │   (k3s data directory)            │  │
│  └───────────────────────────────────┘  │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │   /var/lib/homelab-k8s/           │  │
│  │   (persistent volumes)            │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

**Cosa installeremo**:
1. **k3s** - Distribution Kubernetes leggera
2. **kubectl** - CLI per interagire con il cluster
3. **Flux CD** - Tool GitOps per deployment automatici
4. **k9s** - Terminal UI per gestire il cluster (opzionale ma raccomandato)

---

## Parte 1: Preparazione

### 1.1 Connetti al Server

Dal tuo laptop/workstation:

```bash
ssh elaine  # O ip del server, es: ssh user@192.168.178.X
```

### 1.2 Verifica Sistema

Controlla NixOS version e configurazione:

```bash
# Verifica versione NixOS
nixos-version

# Trova dove è la configurazione NixOS
ls -la /etc/nixos/
```

**Output atteso**: Dovresti vedere file come `configuration.nix` e `hardware-configuration.nix`.

Se usi flakes, potresti avere invece un `flake.nix`.

### 1.3 Verifica Spazio Disco

```bash
df -h /
df -h /var
```

**Requisiti**:
- `/var`: Almeno 20GB liberi (k3s userà `/var/lib/rancher/k3s/`)
- `/home` o path separato: Spazio per persistent volumes

### 1.4 Verifica Rete

```bash
# Verifica IP del server
ip addr show

# Verifica connessione internet
ping -c 3 google.com

# Verifica risoluzione DNS
nslookup github.com
```

Annota l'IP del server sulla tua rete locale (es. `192.168.178.X`).

---

## Parte 2: Configurazione NixOS per k3s

### 2.1 Creare Modulo k3s

Creiamo un modulo NixOS dedicato per k3s per mantenere la configurazione organizzata.

```bash
# Crea file per configurazione k3s
sudo nano /etc/nixos/k3s.nix
```

Inserisci il seguente contenuto:

```nix
# /etc/nixos/k3s.nix
{ config, pkgs, ... }:

{
  # Abilita k3s
  services.k3s = {
    enable = true;
    role = "server";  # single-node cluster
    
    extraFlags = toString [
      # Disabilita Traefik built-in (useremo Caddy)
      "--disable=traefik"
      # Disabilita ServiceLB built-in (useremo MetalLB)
      "--disable=servicelb"
      # Abilita scrittura kubeconfig in path accessibile
      "--write-kubeconfig-mode=644"
    ];
  };

  # Apri porte firewall necessarie
  networking.firewall = {
    allowedTCPPorts = [
      6443  # k3s API server
      10250 # kubelet metrics
    ];
    # Interfacce trusted per k3s
    trustedInterfaces = [
      "cni0"       # Container Network Interface
      "flannel.1"  # Flannel overlay network (k3s default)
    ];
  };

  # Installa tool utili per gestire k3s
  environment.systemPackages = with pkgs; [
    kubectl   # CLI Kubernetes
    k9s       # Terminal UI (altamente raccomandato!)
    fluxcd    # Flux CLI per GitOps
    sops      # Secrets encryption (useremo dopo)
    age       # Encryption tool per SOPS
    git       # Per Flux
  ];

  # Crea directory per persistent volumes
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab-k8s 0755 root root -"
    "d /var/lib/homelab-k8s/pvcs 0755 root root -"
    "d /var/lib/homelab-k8s/configs 0755 root root -"
  ];

  # Permetti al tuo utente di usare kubectl senza sudo
  users.users.nic = {  # Sostituisci 'nic' con il tuo username
    extraGroups = [ "wheel" ];
  };

  # Environment variables per kubectl
  environment.variables = {
    KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
  };
}
```

**💡 Spiegazione**:

- `services.k3s.enable = true`: Abilita k3s come servizio systemd
- `role = "server"`: Questo nodo è sia control-plane che worker (single-node)
- `--disable=traefik`: Disabilitiamo Traefik incluso perché useremo Caddy
- `--disable=servicelb`: Disabilitiamo ServiceLB perché useremo MetalLB
- `--write-kubeconfig-mode=644`: Permette lettura kubeconfig a utenti non-root
- `networking.firewall`: Apriamo porte necessarie
- `trustedInterfaces`: Permettiamo traffico sulle interfacce k3s
- `environment.systemPackages`: Installiamo CLI tools
- `systemd.tmpfiles.rules`: Crea directory per i volumi
- `KUBECONFIG`: kubectl saprà dove trovare la configurazione

### 2.2 Importare il Modulo

Ora dobbiamo dire a NixOS di usare questo modulo.

```bash
sudo nano /etc/nixos/configuration.nix
```

Aggiungi l'import del modulo k3s nella lista degli imports:

```nix
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./k3s.nix  # <--- AGGIUNGI QUESTA RIGA
    # ... altri imports se presenti
  ];
  
  # ... resto della configurazione
}
```

### 2.3 Applicare la Configurazione

```bash
# Rebuild NixOS con la nuova configurazione
sudo nixos-rebuild switch
```

**Cosa succede**:
1. NixOS scarica e installa k3s
2. Crea il servizio systemd per k3s
3. Installa kubectl, k9s, flux, ecc.
4. Configura firewall
5. Crea le directory per storage
6. Avvia k3s

**Questo processo può richiedere 5-10 minuti** per download e build.

**Output atteso**:
```
building Nix derivation...
...
activating the configuration...
setting up /etc...
reloading systemd...
starting systemd services...
```

Se vedi errori, leggi attentamente il messaggio. Comuni:
- Syntax error nel `.nix`: controlla parentesi e punti e virgola
- Port già in uso: verifica che nessun servizio usi porta 6443

### 2.4 Verificare k3s Funziona

```bash
# Verifica servizio k3s è attivo
sudo systemctl status k3s

# Dovresti vedere: Active: active (running)
```

**Output atteso**:
```
● k3s.service - k3s
     Loaded: loaded (/etc/systemd/system/k3s.service; enabled)
     Active: active (running) since ...
```

Se vedi `failed` o `inactive`, guarda i log:

```bash
sudo journalctl -u k3s -n 50
```

---

## Parte 3: Primo Accesso al Cluster

### 3.1 Configurare kubectl

kubectl è il comando principale per interagire con Kubernetes.

```bash
# Verifica kubectl è installato
kubectl version --client

# Verifica accesso al cluster
kubectl cluster-info
```

**Output atteso**:
```
Kubernetes control plane is running at https://127.0.0.1:6443
CoreDNS is running at https://127.0.0.1:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

### 3.2 Verificare Nodi

```bash
kubectl get nodes
```

**Output atteso**:
```
NAME      STATUS   ROLES                  AGE   VERSION
elaine    Ready    control-plane,master   5m    v1.28.x+k3s1
```

**Spiegazione output**:
- `NAME`: hostname del nodo
- `STATUS`: `Ready` = nodo funzionante e pronto
- `ROLES`: questo nodo è sia control-plane che worker
- `AGE`: da quanto tempo il nodo è nel cluster
- `VERSION`: versione k3s/Kubernetes

### 3.3 Esplorare Namespaces

Kubernetes organizza le risorse in **namespaces** (come directory).

```bash
# Lista tutti i namespaces
kubectl get namespaces

# Forma abbreviata
kubectl get ns
```

**Output atteso**:
```
NAME              STATUS   AGE
default           Active   5m
kube-system       Active   5m
kube-public       Active   5m
kube-node-lease   Active   5m
```

**Spiegazione**:
- `default`: namespace di default per le tue app
- `kube-system`: componenti del cluster (DNS, storage, ecc.)
- `kube-public`: risorse pubblicamente accessibili
- `kube-node-lease`: heartbeat dei nodi

### 3.4 Vedere Pods di Sistema

I **Pods** sono le unità base in Kubernetes (container + metadata).

```bash
# Lista pods nel namespace kube-system
kubectl get pods -n kube-system

# Con più dettagli
kubectl get pods -n kube-system -o wide
```

**Output atteso**:
```
NAME                                     READY   STATUS    RESTARTS   AGE
coredns-xxx                              1/1     Running   0          5m
local-path-provisioner-xxx               1/1     Running   0          5m
metrics-server-xxx                       1/1     Running   0          5m
```

**Spiegazione**:
- `coredns`: DNS interno del cluster
- `local-path-provisioner`: storage provisioner (crea PersistentVolumes automaticamente)
- `metrics-server`: raccoglie metriche CPU/RAM dai pods

**READY 1/1** significa: 1 container pronto su 1 totale.

**STATUS Running** = tutto OK.

### 3.5 (Opzionale) Usare k9s

k9s è una UI terminale interattiva per Kubernetes. Molto più comoda di kubectl!

```bash
# Lancia k9s
k9s
```

**Comandi utili in k9s**:
- `:namespaces` o `:ns` - Lista namespaces
- `:pods` o `:po` - Lista pods
- `:services` o `:svc` - Lista services
- `/` - Cerca
- `d` - Describe (dettagli risorsa)
- `l` - Logs del pod selezionato
- `?` - Help
- `:quit` o `Ctrl+C` - Esci

**Prova**:
1. Premi `:` e scrivi `pods`
2. Usa frecce per navigare
3. Premi `Enter` su un pod per vedere dettagli
4. Premi `Esc` per tornare indietro

---

## Parte 4: Installare Flux CD (GitOps)

Flux CD monitora il tuo repository Git e applica automaticamente modifiche al cluster.

**Flusso GitOps**:
```
1. Fai modifiche ai manifest in k3s/apps/
2. Commit e push su GitHub
3. Flux rileva modifiche automaticamente
4. Flux applica modifiche al cluster
5. Stato cluster = stato repository Git
```

### 4.1 Preparare Repository Git

Sul tuo **laptop** (non sul server):

```bash
cd ~/code/homelab  # O dove hai il repository

# Pulisci la directory k3s dai vecchi esperimenti
rm -rf k3s/apps/*
rm -rf k3s/bootstrap/*

# Ricreiamo la struttura
mkdir -p k3s/bootstrap/flux-system
mkdir -p k3s/infrastructure
mkdir -p k3s/apps
mkdir -p k3s/secrets

# Crea un placeholder per testare Flux
cat > k3s/apps/placeholder.yaml <<EOF
# Questo file verrà sostituito con le vere applicazioni
# Serve solo per testare Flux
apiVersion: v1
kind: Namespace
metadata:
  name: homelab
EOF

# Commit
git add k3s/
git commit -m "Prepare k3s structure for Flux"
git push origin main  # O il nome del tuo branch
```

### 4.2 Verificare GitHub Access Token

Flux ha bisogno di accedere al tuo repository GitHub.

**Opzioni**:
1. **SSH Key** (raccomandato per repository privato)
2. **Personal Access Token** (più semplice)

**Usiamo SSH** (se il tuo repo è privato):

Sul **server** (via SSH):

```bash
# Verifica se hai già una chiave SSH
ls ~/.ssh/id_*

# Se non esiste, creala
ssh-keygen -t ed25519 -C "k3s-flux@elaine"

# Copia la chiave pubblica
cat ~/.ssh/id_ed25519.pub
```

**Aggiungi la chiave a GitHub**:
1. Vai su https://github.com/settings/keys
2. Click "New SSH key"
3. Titolo: "k3s flux elaine"
4. Incolla il contenuto di `id_ed25519.pub`
5. Clicca "Add SSH key"

**Testa accesso**:
```bash
ssh -T git@github.com
# Output: Hi Guybrush21! You've successfully authenticated...
```

### 4.3 Bootstrap Flux

Sul **server**:

```bash
# Esporta variabili per Flux
export GITHUB_USER="Guybrush21"  # Il tuo username GitHub
export GITHUB_REPO="homelab"      # Nome repository

# Bootstrap Flux
flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=$GITHUB_REPO \
  --branch=main \
  --path=k3s/bootstrap/flux-system \
  --personal
```

**Cosa succede**:
1. Flux crea un namespace `flux-system`
2. Installa i componenti Flux nel cluster
3. Crea deployment keys nel repository GitHub
4. Configura sync automatico

**Output atteso**:
```
► connecting to github.com
✔ repository cloned
► applying manifests
✔ reconciled source secret
✔ reconciled sync configuration
...
◎ waiting for Kustomization reconciliation
✔ Kustomization reconciled successfully
```

**Se errori**:
- **"failed to clone"**: Verifica SSH key aggiunta correttamente
- **"branch not found"**: Verifica nome branch (main vs master)
- **"path not found"**: Crea la directory `k3s/bootstrap/flux-system/` nel repo

### 4.4 Verificare Flux è Attivo

```bash
# Controlla stato Flux
flux check

# Lista componenti Flux
kubectl get pods -n flux-system
```

**Output atteso**:
```
► checking prerequisites
✔ Kubernetes 1.28.x >=1.26.0
✔ prerequisites checks passed

► checking controllers
✔ helm-controller: deployment ready
✔ kustomize-controller: deployment ready
✔ notification-controller: deployment ready
✔ source-controller: deployment ready
✔ all checks passed
```

### 4.5 Configurare Flux per Sincronizzare Apps

Creiamo una `GitRepository` e `Kustomization` per monitorare `k3s/apps/`.

Sul **laptop**:

```bash
cd ~/code/homelab

# Crea configurazione Flux per apps
cat > k3s/bootstrap/apps-sync.yaml <<'EOF'
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: homelab-apps
  namespace: flux-system
spec:
  interval: 1m0s
  ref:
    branch: main
  url: https://github.com/Guybrush21/homelab.git
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: homelab-apps
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./k3s/apps
  prune: true
  sourceRef:
    kind: GitRepository
    name: homelab-apps
  validation: client
EOF

# Commit e push
git add k3s/bootstrap/apps-sync.yaml
git commit -m "Configure Flux to sync k3s/apps"
git push
```

**Spiegazione**:
- `GitRepository`: dice a Flux dove è il repository
- `interval: 1m`: controlla modifiche ogni 1 minuto
- `Kustomization`: dice a Flux quali file applicare
- `path: ./k3s/apps`: applica tutto in questa directory
- `prune: true`: rimuovi risorse cancellate dal repo

### 4.6 Applicare Manualmente la Prima Volta

Sul **server**:

```bash
# Applica la configurazione sync
kubectl apply -f ~/code/homelab/k3s/bootstrap/apps-sync.yaml

# Oppure, se non hai il repo clonato sul server:
curl -s https://raw.githubusercontent.com/Guybrush21/homelab/main/k3s/bootstrap/apps-sync.yaml | kubectl apply -f -
```

**Attendi qualche secondo, poi verifica**:

```bash
# Controlla sincronizzazione Flux
flux get sources git

# Controlla kustomizations
flux get kustomizations
```

**Output atteso**:
```
NAME            REVISION        SUSPENDED       READY
homelab-apps    main@sha1:xxx   False           True
```

**READY True** = Flux ha sincronizzato con successo!

### 4.7 Verificare Namespace Creato da Flux

Ricordi il `placeholder.yaml` che creava il namespace `homelab`?

```bash
kubectl get namespace homelab
```

**Se esiste**, Flux funziona correttamente! 🎉

```
NAME      STATUS   AGE
homelab   Active   1m
```

---

## Parte 5: Testare il Workflow GitOps

Testiamo che il flusso Git → Flux → Cluster funzioni.

### 5.1 Creare un Test Pod

Sul **laptop**:

```bash
cd ~/code/homelab

cat > k3s/apps/test-nginx.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-nginx
  namespace: homelab
  labels:
    app: test
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
EOF

# Commit e push
git add k3s/apps/test-nginx.yaml
git commit -m "Add test nginx pod"
git push
```

### 5.2 Attendere Flux Sync

Flux controlla il repository ogni 1 minuto. Puoi:

**Opzione A**: Attendere 1 minuto

**Opzione B**: Forzare sync immediato

Sul **server**:

```bash
# Forza reconciliation immediata
flux reconcile kustomization homelab-apps --with-source
```

### 5.3 Verificare Pod Creato

```bash
# Controlla pod
kubectl get pods -n homelab

# Con dettagli
kubectl get pods -n homelab -o wide
```

**Output atteso**:
```
NAME         READY   STATUS    RESTARTS   AGE   IP           NODE
test-nginx   1/1     Running   0          30s   10.42.0.15   elaine
```

**Se vedi STATUS Running**, GitOps funziona! 🚀

### 5.4 Vedere Logs del Pod

```bash
kubectl logs -n homelab test-nginx
```

Output: logs di nginx che si avvia.

### 5.5 Pulire il Test

Sul **laptop**:

```bash
cd ~/code/homelab

# Rimuovi il test pod
git rm k3s/apps/test-nginx.yaml
git commit -m "Remove test nginx pod"
git push
```

Dopo ~1 minuto (o con `flux reconcile`), il pod sparirà:

```bash
kubectl get pods -n homelab
# Output: No resources found in homelab namespace.
```

**Questo è GitOps**: lo stato del cluster riflette lo stato di Git!

---

## Parte 6: Configurare Local Path Provisioner

k3s include già **Local Path Provisioner**, che crea automaticamente PersistentVolumes su disco locale.

### 6.1 Verificare Provisioner Attivo

```bash
kubectl get pods -n kube-system | grep local-path
```

**Output**:
```
local-path-provisioner-xxx   1/1     Running   0   20m
```

### 6.2 Verificare StorageClass

```bash
kubectl get storageclass
```

**Output atteso**:
```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer
```

**Spiegazione**:
- `local-path`: nome della StorageClass
- `(default)`: questa è la SC di default
- `RECLAIMPOLICY Delete`: quando cancelli il PVC, il volume viene eliminato
- `WaitForFirstConsumer`: crea il volume solo quando un pod lo usa

### 6.3 Cambiare Path di Default (Opzionale)

Di default, Local Path Provisioner crea volumi in `/var/lib/rancher/k3s/storage/`.

Se vuoi usare `/var/lib/homelab-k8s/pvcs/`:

```bash
kubectl edit configmap local-path-config -n kube-system
```

Modifica la riga:

```yaml
data:
  config.json: |-
    {
      "nodePathMap": [
        {
          "node": "DEFAULT_PATH_FOR_NON_LISTED_NODES",
          "paths": ["/var/lib/homelab-k8s/pvcs"]  # <-- Cambia qui
        }
      ]
    }
```

Salva e esci (`:wq` in vim).

**Riavvia il provisioner**:

```bash
kubectl rollout restart deployment local-path-provisioner -n kube-system
```

### 6.4 Testare PVC

Sul **laptop**:

```bash
cd ~/code/homelab

cat > k3s/apps/test-pvc.yaml <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: homelab
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pvc-pod
  namespace: homelab
spec:
  containers:
  - name: test
    image: busybox
    command: ["sh", "-c", "echo 'Hello from PVC' > /data/test.txt && sleep 3600"]
    volumeMounts:
    - name: storage
      mountPath: /data
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: test-pvc
EOF

git add k3s/apps/test-pvc.yaml
git commit -m "Test PVC"
git push
```

Sul **server** (dopo sync):

```bash
# Controlla PVC
kubectl get pvc -n homelab

# Controlla PV creato automaticamente
kubectl get pv
```

**Output PVC**:
```
NAME       STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
test-pvc   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   1Gi        RWO            local-path
```

**STATUS Bound** = volume creato e collegato!

**Verifica file creato**:

```bash
# Exec nel pod
kubectl exec -n homelab test-pvc-pod -- cat /data/test.txt
```

**Output**:
```
Hello from PVC
```

**Verifica su disco**:

```bash
sudo ls -lh /var/lib/homelab-k8s/pvcs/
# (o /var/lib/rancher/k3s/storage/ se non hai cambiato path)
```

Vedrai una directory `pvc-xxxxx/` con il file `test.txt`.

**Pulisci**:

```bash
# Sul laptop
git rm k3s/apps/test-pvc.yaml
git commit -m "Clean test PVC"
git push
```

---

## Parte 7: Accesso da Laptop (Opzionale)

Se vuoi usare `kubectl` dal tuo laptop invece che via SSH:

### 7.1 Copiare Kubeconfig

Sul **laptop**:

```bash
# Copia kubeconfig dal server
scp elaine:/etc/rancher/k3s/k3s.yaml ~/.kube/config-homelab

# Modifica per puntare all'IP del server invece di 127.0.0.1
sed -i 's/127.0.0.1/192.168.178.X/g' ~/.kube/config-homelab
# Sostituisci 192.168.178.X con l'IP reale del tuo server

# Merge con kubeconfig esistente (se ne hai uno)
export KUBECONFIG=~/.kube/config:~/.kube/config-homelab
kubectl config view --flatten > ~/.kube/config-merged
mv ~/.kube/config-merged ~/.kube/config

# Oppure usa solo homelab
export KUBECONFIG=~/.kube/config-homelab
```

### 7.2 Testare Accesso

```bash
kubectl get nodes
```

Se funziona, puoi gestire il cluster dal tuo laptop! 🎉

---

## Riepilogo e Verifica Finale

### ✅ Checklist

A questo punto dovresti avere:

- [ ] k3s installato e configurato in NixOS
- [ ] `kubectl get nodes` mostra `elaine Ready`
- [ ] Flux CD installato e funzionante
- [ ] `flux check` tutto verde
- [ ] GitOps funziona: modifiche in Git → applicate nel cluster
- [ ] Namespace `homelab` creato
- [ ] Local Path Provisioner crea PVC automaticamente
- [ ] Tool installati: kubectl, k9s, flux, sops, age

### 📊 Comandi Utili da Ricordare

```bash
# Status cluster
kubectl get nodes
kubectl get namespaces
kubectl get pods --all-namespaces

# Status Flux
flux check
flux get sources git
flux get kustomizations

# Forzare sync Flux
flux reconcile kustomization homelab-apps --with-source

# Logs di un pod
kubectl logs -n <namespace> <pod-name>

# Describe (dettagli)
kubectl describe pod -n <namespace> <pod-name>

# Exec in un pod
kubectl exec -it -n <namespace> <pod-name> -- /bin/sh

# k9s (UI interattiva)
k9s
```

### 🧹 Pulizia Placeholder

Prima di passare alla Fase 2, rimuovi il placeholder:

Sul **laptop**:

```bash
cd ~/code/homelab
git rm k3s/apps/placeholder.yaml
git commit -m "Remove placeholder, ready for Phase 2"
git push
```

---

## Troubleshooting

### Problema: k3s non si avvia

```bash
# Controlla logs
sudo journalctl -u k3s -n 100

# Controlla porte
sudo ss -tulpn | grep 6443
```

**Soluzioni**:
- Porta 6443 già in uso: ferma servizio che la usa
- Errori firewall: verifica `networking.firewall` in NixOS config

### Problema: kubectl "connection refused"

**Causa**: k3s non ha scritto kubeconfig o permessi errati.

```bash
# Verifica file esiste
ls -la /etc/rancher/k3s/k3s.yaml

# Verifica permessi
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

# Verifica KUBECONFIG
echo $KUBECONFIG

# Forza variabile
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

### Problema: Flux non sincronizza

```bash
# Controlla logs Flux
kubectl logs -n flux-system deploy/source-controller
kubectl logs -n flux-system deploy/kustomize-controller

# Forza sync
flux reconcile source git homelab-apps
flux reconcile kustomization homelab-apps
```

**Soluzioni**:
- Errore autenticazione GitHub: verifica SSH key
- Path non trovato: verifica `k3s/apps/` esiste nel repo
- Manifests invalid: controlla sintassi YAML

### Problema: PVC rimane "Pending"

```bash
# Controlla eventi
kubectl describe pvc -n homelab <pvc-name>

# Controlla provisioner
kubectl get pods -n kube-system | grep local-path
kubectl logs -n kube-system deploy/local-path-provisioner
```

**Causa comune**: Nessun pod usa il PVC. Con `WaitForFirstConsumer`, il volume viene creato solo quando un pod lo richiede.

---

## Prossimi Passi

🎉 **Congratulazioni!** Hai un cluster k3s funzionante con GitOps!

**Fase 2**: [Networking & Ingress](./02-networking-ingress.md)

Installeremo:
- MetalLB per LoadBalancer IPs
- Caddy come Ingress Controller
- Certificati SSL con Cloudflare DNS challenge

Ci vediamo lì! 🚀
