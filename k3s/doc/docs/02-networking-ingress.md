# Fase 2: Networking & Ingress con MetalLB e Caddy

**Durata stimata**: 1 giorno  
**Prerequisiti**: Fase 1 completata (k3s + Flux funzionanti)  
**Obiettivo**: Esporre servizi con Caddy Ingress Controller e SSL automatico

---

## 📚 Cosa Imparerai

- Differenza tra ClusterIP, NodePort, LoadBalancer
- Cos'è MetalLB e perché serve in bare-metal
- Cos'è un Ingress Controller
- Come Caddy gestisce routing HTTP e certificati SSL
- DNS challenge con Cloudflare per wildcard certificates

---

## Panoramica Architettura

### Problema da Risolvere

In Docker Compose esponevi servizi con:
```yaml
ports:
  - "80:80"
  - "443:443"
```

In Kubernetes, ci serve un modo più sofisticato:

```
Internet
   ↓
Router (port forward 80/443 → IP del server)
   ↓
??? Come facciamo il routing a servizi diversi ???
   ↓
Service A, Service B, Service C...
```

### Soluzione: Ingress Controller

```
┌─────────────────────────────────────────────────────────┐
│                    Internet                             │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────▼──────────────┐
        │   Router (Port Forward)   │
        │   80/443 → 192.168.178.50 │
        └────────────┬──────────────┘
                     │
        ┌────────────▼──────────────┐
        │    MetalLB LoadBalancer   │
        │    IP: 192.168.178.50     │
        └────────────┬──────────────┘
                     │
        ┌────────────▼──────────────────────────┐
        │   Caddy Ingress Controller (Pod)      │
        │   - Termina SSL                       │
        │   - Routing basato su hostname        │
        │   - Certificati automatici (Cloudflare)│
        └────────────┬──────────────────────────┘
                     │
      ┌──────────────┼──────────────┐
      │              │              │
┌─────▼─────┐  ┌─────▼─────┐  ┌────▼──────┐
│  homer.   │  │ jellyfin. │  │  umami.   │
│elaine.pw  │  │elaine.pw  │  │elaine.pw  │
│  Service  │  │  Service  │  │  Service  │
└───────────┘  └───────────┘  └───────────┘
```

### Componenti

1. **MetalLB**: Assegna IP locali ai Service di tipo LoadBalancer (cloud provider lo farebbero automaticamente, ma siamo bare-metal)
2. **Caddy**: Ingress Controller che gestisce routing HTTP e SSL
3. **Ingress Resources**: Regole di routing (es. "homer.elaine.pw → homer-service")

---

## Parte 1: Installare MetalLB

MetalLB permette di usare Service di tipo `LoadBalancer` in bare-metal cluster.

### 1.1 Capire il Problema

Prova questo esperimento.

Sul **server**:

```bash
# Crea un test service di tipo LoadBalancer
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: test-lb
  namespace: homelab
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: nonexistent
EOF

# Guarda lo status
kubectl get svc -n homelab test-lb
```

**Output**:
```
NAME      TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)
test-lb   LoadBalancer   10.43.xxx.xxx   <pending>     80:xxxxx/TCP
```

**EXTERNAL-IP: <pending>** = k3s non sa quale IP assegnare!

**Perché?** Su cloud (AWS, GCP), il cloud provider assegna IP automaticamente. Su bare-metal, serve MetalLB.

```bash
# Pulisci
kubectl delete svc -n homelab test-lb
```

### 1.2 Creare Namespace per MetalLB

Sul **laptop**:

```bash
cd ~/code/homelab

# Crea directory per infrastructure components
mkdir -p k3s/infrastructure/metallb

cat > k3s/infrastructure/metallb/namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: metallb-system
EOF
```

### 1.3 Installare MetalLB via Manifest

```bash
cat > k3s/infrastructure/metallb/metallb.yaml <<'EOF'
# Source: https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml
# (semplificato per chiarezza - versione completa usa Helm)

apiVersion: v1
kind: ServiceAccount
metadata:
  name: controller
  namespace: metallb-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: speaker
  namespace: metallb-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: metallb-system:controller
rules:
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["services/status"]
  verbs: ["update"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: metallb-system:controller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: metallb-system:controller
subjects:
- kind: ServiceAccount
  name: controller
  namespace: metallb-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: controller
  namespace: metallb-system
spec:
  selector:
    matchLabels:
      app: metallb
      component: controller
  template:
    metadata:
      labels:
        app: metallb
        component: controller
    spec:
      serviceAccountName: controller
      containers:
      - name: controller
        image: quay.io/metallb/controller:v0.14.3
        args:
        - --port=7472
        ports:
        - name: metrics
          containerPort: 7472
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 65534
          capabilities:
            drop:
            - ALL
EOF
```

### 1.4 Configurare IP Address Pool

Questo è l'IP range che MetalLB userà per assegnare agli Service LoadBalancer.

**IMPORTANTE**: Usa IP liberi nella tua rete locale che il tuo router DHCP non assegnerà.

```bash
cat > k3s/infrastructure/metallb/ipaddresspool.yaml <<'EOF'
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: homelab-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.178.50-192.168.178.59  # <-- Modifica con i tuoi IP
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab-l2adv
  namespace: metallb-system
spec:
  ipAddressPools:
  - homelab-pool
EOF
```

**Spiegazione**:
- `IPAddressPool`: range di IP disponibili (192.168.178.50-59 = 10 IP)
- `L2Advertisement`: annuncia questi IP sulla rete locale via ARP (Layer 2)

**🔧 Personalizza**:
- Verifica che questi IP siano liberi: `ping 192.168.178.50` (nessuna risposta = OK)
- Configura router DHCP per non assegnare questi IP
- Usa un range fuori dal DHCP pool

### 1.5 Applicare Configurazione

```bash
cd ~/code/homelab

# Commit tutto
git add k3s/infrastructure/metallb/
git commit -m "Add MetalLB configuration"
git push
```

Sul **server**, forza sync Flux:

```bash
flux reconcile kustomization homelab-apps --with-source
```

**Aspetta**, MetalLB non si installerà! Perché?

Flux monitora solo `k3s/apps/`, non `k3s/infrastructure/`!

### 1.6 Aggiungere Infrastructure a Flux

Sul **laptop**:

```bash
cd ~/code/homelab

cat > k3s/bootstrap/infrastructure-sync.yaml <<'EOF'
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: homelab-infrastructure
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
  name: homelab-infrastructure
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./k3s/infrastructure
  prune: true
  sourceRef:
    kind: GitRepository
    name: homelab-infrastructure
EOF

git add k3s/bootstrap/infrastructure-sync.yaml
git commit -m "Add infrastructure sync to Flux"
git push
```

Sul **server**:

```bash
kubectl apply -f ~/code/homelab/k3s/bootstrap/infrastructure-sync.yaml

# Oppure via URL
curl -s https://raw.githubusercontent.com/Guybrush21/homelab/main/k3s/bootstrap/infrastructure-sync.yaml | kubectl apply -f -
```

### 1.7 Verificare MetalLB Installato

```bash
# Controlla namespace
kubectl get ns metallb-system

# Controlla pods
kubectl get pods -n metallb-system

# Controlla IPAddressPool
kubectl get ipaddresspool -n metallb-system
```

**Output atteso**:
```
NAME                    READY   STATUS    RESTARTS   AGE
controller-xxx          1/1     Running   0          1m
```

### 1.8 Testare MetalLB

```bash
# Ricrea il test service
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: test-lb
  namespace: homelab
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: nonexistent
EOF

# Guarda lo status
kubectl get svc -n homelab test-lb
```

**Output**:
```
NAME      TYPE           CLUSTER-IP      EXTERNAL-IP       PORT(S)
test-lb   LoadBalancer   10.43.xxx.xxx   192.168.178.50    80:xxxxx/TCP
```

**EXTERNAL-IP: 192.168.178.50** 🎉

MetalLB ha assegnato il primo IP disponibile!

```bash
# Prova a fare ping
ping -c 3 192.168.178.50
```

Se risponde (anche se nessun pod lo sta usando), MetalLB funziona!

```bash
# Pulisci
kubectl delete svc -n homelab test-lb
```

---

## Parte 2: Installare Caddy Ingress

Caddy è un web server moderno con:
- Certificati SSL automatici
- Reverse proxy
- Configurazione semplice con Caddyfile

### 2.1 Preparare Cloudflare API Token

Caddy userà DNS challenge per ottenere certificati wildcard (*.elaine.pw).

**Prerequisito**: Hai un API token Cloudflare con permessi `Zone:DNS:Edit`.

**Se non ce l'hai ancora**:

1. Vai su https://dash.cloudflare.com/profile/api-tokens
2. "Create Token"
3. Template: "Edit zone DNS"
4. Zone Resources: `Include` → `Specific zone` → `elaine.pw`
5. Copia il token (lo vedrai una volta sola!)

**Salvalo temporaneamente** (poi lo metteremo in un Secret).

### 2.2 Creare Namespace e Secret

Sul **laptop**:

```bash
cd ~/code/homelab
mkdir -p k3s/infrastructure/caddy-ingress

cat > k3s/infrastructure/caddy-ingress/namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: ingress
EOF
```

**Per il Secret**, useremo un approccio temporaneo (Fase 5 useremo SOPS):

Sul **server** (direttamente, non via Git):

```bash
# Crea Secret con Cloudflare token
kubectl create namespace ingress

kubectl create secret generic cloudflare-api-token \
  --namespace=ingress \
  --from-literal=token='TUO_TOKEN_CLOUDFLARE_QUI'

# Verifica
kubectl get secret -n ingress cloudflare-api-token
```

**⚠️ IMPORTANTE**: Non committare mai il token in Git in chiaro!

### 2.3 Creare ConfigMap per Caddyfile

```bash
cat > k3s/infrastructure/caddy-ingress/configmap.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: caddy-config
  namespace: ingress
data:
  Caddyfile: |
    {
      # Global options
      email tu@email.com  # <-- Modifica con la tua email
      
      # Logging
      log {
        output stdout
        format console
        level INFO
      }
      
      # ACME server
      acme_ca https://acme-v02.api.letsencrypt.org/directory
      # Per testing usa staging:
      # acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
    }
    
    # Questa sezione verrà popolata dinamicamente dagli Ingress
    # Per ora, endpoint di health check
    :80 {
      respond /healthz "OK" 200
    }
    
    # Configurazione SSL wildcard tramite Cloudflare DNS
    *.elaine.pw {
      tls {
        dns cloudflare {env.CF_API_TOKEN}
      }
      
      # Reverse proxy configurato dinamicamente
      # Per ora un placeholder
      respond "Caddy Ingress is running" 200
    }
EOF
```

**💡 Spiegazione**:
- `email`: usato per Let's Encrypt (riceverai notifiche scadenza)
- `acme_ca`: server Let's Encrypt (usa staging per test, production quando sicuro)
- `dns cloudflare`: usa DNS-01 challenge per certificati wildcard
- `{env.CF_API_TOKEN}`: legge token da variabile ambiente

**🔧 Modifica**:
- Cambia `tu@email.com` con la tua email
- (Opzionale) Usa staging Let's Encrypt per test iniziali

### 2.4 Creare Deployment Caddy

```bash
cat > k3s/infrastructure/caddy-ingress/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: caddy-ingress
  namespace: ingress
  labels:
    app: caddy-ingress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: caddy-ingress
  template:
    metadata:
      labels:
        app: caddy-ingress
    spec:
      containers:
      - name: caddy
        image: caddy:2.7.6-alpine
        ports:
        - name: http
          containerPort: 80
        - name: https
          containerPort: 443
        env:
        - name: CF_API_TOKEN
          valueFrom:
            secretKeyRef:
              name: cloudflare-api-token
              key: token
        volumeMounts:
        - name: config
          mountPath: /etc/caddy/Caddyfile
          subPath: Caddyfile
        - name: data
          mountPath: /data
        - name: config-storage
          mountPath: /config
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: config
        configMap:
          name: caddy-config
      - name: data
        emptyDir: {}
      - name: config-storage
        emptyDir: {}
EOF
```

**💡 Spiegazione**:
- `image: caddy:2.7.6-alpine`: Caddy con Cloudflare DNS module
- `env`: Inietta Cloudflare token da Secret
- `volumeMounts`: Monta Caddyfile da ConfigMap
- `/data`: Storage per certificati SSL
- `resources`: Limiti RAM/CPU per evitare overconsumption

**⚠️ Nota**: Per Cloudflare DNS challenge, serve Caddy con modulo `cloudflare`. L'immagine ufficiale non include moduli extra.

**Opzione 1**: Build custom image (più complesso)  
**Opzione 2**: Usa cert-manager invece (alternativa)

**Per semplicità, proseguiamo con questa configurazione** e in Fase 5 miglioreremo.

### 2.5 Creare LoadBalancer Service

```bash
cat > k3s/infrastructure/caddy-ingress/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: caddy-loadbalancer
  namespace: ingress
spec:
  type: LoadBalancer
  selector:
    app: caddy-ingress
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 80
  - name: https
    protocol: TCP
    port: 443
    targetPort: 443
EOF
```

**💡 Spiegazione**:
- `type: LoadBalancer`: MetalLB assegnerà un IP (es. 192.168.178.50)
- `port: 80/443`: porte esposte esternamente
- `targetPort: 80/443`: porte del container Caddy

### 2.6 Applicare Configurazione

```bash
cd ~/code/homelab

git add k3s/infrastructure/caddy-ingress/
git commit -m "Add Caddy ingress controller"
git push
```

Sul **server**:

```bash
# Forza sync
flux reconcile kustomization homelab-infrastructure --with-source

# Attendi deployment
kubectl rollout status deployment/caddy-ingress -n ingress
```

### 2.7 Verificare Caddy Funziona

```bash
# Controlla pods
kubectl get pods -n ingress

# Controlla service
kubectl get svc -n ingress caddy-loadbalancer
```

**Output**:
```
NAME                 TYPE           CLUSTER-IP     EXTERNAL-IP       PORT(S)
caddy-loadbalancer   LoadBalancer   10.43.xx.xx    192.168.178.50    80:xxx/TCP,443:xxx/TCP
```

**Annota l'EXTERNAL-IP** (es. 192.168.178.50).

**Testa HTTP**:

```bash
curl http://192.168.178.50/healthz
```

**Output**:
```
OK
```

Se vedi "OK", Caddy risponde! 🎉

**Testa HTTPS** (opzionale, certificato self-signed per ora):

```bash
curl -k https://192.168.178.50
```

---

## Parte 3: Configurare DNS e Port Forwarding

### 3.1 Configurare Port Forwarding sul Router

**Sul tuo router**:

1. Accedi all'admin panel (es. 192.168.178.1)
2. Trova "Port Forwarding" o "Virtual Server"
3. Aggiungi regole:

| Servizio | Porta Esterna | IP Interno | Porta Interna | Protocollo |
|----------|---------------|------------|---------------|------------|
| HTTP     | 80            | 192.168.178.50 (LoadBalancer IP) | 80 | TCP |
| HTTPS    | 443           | 192.168.178.50 | 443 | TCP |

**Salva** e applica.

### 3.2 Verificare DNS Cloudflare

Vai su Cloudflare dashboard → DNS → elaine.pw

Verifica che esista un record A o AAAA puntando al tuo IP pubblico.

```
Type: A
Name: @
Content: TUO_IP_PUBBLICO
Proxy: Disattivato (nuvola grigia)
```

**Wildcard** (se non esiste, crealo):

```
Type: A
Name: *
Content: TUO_IP_PUBBLICO
Proxy: Disattivato
```

**IMPORTANTE**: Proxy deve essere **disattivato** (nuvola grigia) per usare Let's Encrypt DNS challenge!

### 3.3 Testare Accesso Esterno

Dal **laptop** (o smartphone fuori dalla rete locale):

```bash
curl http://elaine.pw/healthz
```

Se vedi "OK", funziona! 🎉

Se fallisce:
- Verifica port forwarding router
- Verifica DNS propagato: `dig elaine.pw`
- Verifica firewall non blocca porte 80/443

---

## Parte 4: Primo Ingress Resource

Ora creiamo un **Ingress** per far sì che Caddy routing a un servizio reale.

### 4.1 Deploy App di Test

Sul **laptop**:

```bash
cd ~/code/homelab
mkdir -p k3s/apps/whoami

cat > k3s/apps/whoami/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
  namespace: homelab
spec:
  replicas: 2
  selector:
    matchLabels:
      app: whoami
  template:
    metadata:
      labels:
        app: whoami
    spec:
      containers:
      - name: whoami
        image: traefik/whoami
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: whoami-service
  namespace: homelab
spec:
  selector:
    app: whoami
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
EOF
```

**💡 Spiegazione**:
- `whoami`: app che risponde con info sulla richiesta HTTP (testing ingress)
- `replicas: 2`: 2 pod per testare load balancing
- `Service`: ClusterIP (interno), non esposto direttamente

### 4.2 Creare Ingress per Whoami

**⚠️ Problema**: Caddy non supporta nativamente Ingress resources di Kubernetes.

**Soluzioni**:

**Opzione A**: Usare **Caddy Ingress Controller** (progetto separato)  
**Opzione B**: Configurare Caddy manualmente via ConfigMap  
**Opzione C**: Usare **Traefik** o **nginx-ingress** invece

**Per questa guida, usiamo Opzione B** (manuale, educativa).

Modifichiamo il Caddyfile:

```bash
cat > k3s/infrastructure/caddy-ingress/configmap.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: caddy-config
  namespace: ingress
data:
  Caddyfile: |
    {
      email tu@email.com
      log {
        output stdout
        format console
        level INFO
      }
    }
    
    # Health check endpoint
    :80 {
      route /healthz {
        respond "OK" 200
      }
      
      # Redirect tutto altro a HTTPS
      redir https://{host}{uri} permanent
    }
    
    # Wildcard SSL
    *.elaine.pw {
      tls {
        dns cloudflare {env.CF_API_TOKEN}
      }
      
      # Routing basato su hostname
      @whoami host whoami.elaine.pw
      handle @whoami {
        reverse_proxy whoami-service.homelab.svc.cluster.local:80
      }
      
      # Fallback
      handle {
        respond "Service not found" 404
      }
    }
EOF

git add k3s/infrastructure/caddy-ingress/configmap.yaml
git commit -m "Update Caddyfile with whoami routing"
git push
```

**💡 Spiegazione**:
- `@whoami host whoami.elaine.pw`: matcher per hostname
- `reverse_proxy whoami-service.homelab.svc.cluster.local:80`: invia traffico al Service k8s
- `.homelab.svc.cluster.local`: DNS interno k8s (namespace.svc.cluster.local)

Sul **server**:

```bash
# Sync
flux reconcile kustomization homelab-infrastructure --with-source
flux reconcile kustomization homelab-apps --with-source

# Riavvia Caddy per ricaricare config
kubectl rollout restart deployment/caddy-ingress -n ingress
```

### 4.3 Testare Ingress

Attendi ~1 minuto perché Caddy ottenga certificato SSL.

**Logs Caddy**:

```bash
kubectl logs -n ingress deploy/caddy-ingress -f
```

Dovresti vedere:
```
[INFO] obtaining certificate for whoami.elaine.pw
[INFO] successfully obtained certificate
```

**Testa**:

```bash
curl https://whoami.elaine.pw
```

**Output atteso**:
```
Hostname: whoami-xxx
IP: ...
RemoteAddr: ...
GET / HTTP/1.1
Host: whoami.elaine.pw
```

Se vedi questo, **Ingress funziona!** 🚀

### 4.4 Testare HTTPS e Certificato

```bash
curl -v https://whoami.elaine.pw 2>&1 | grep -i "ssl\|certificate"
```

Dovresti vedere certificato valido da Let's Encrypt.

**Nel browser**: visita https://whoami.elaine.pw

- Lucchetto verde ✅
- Certificato valido
- Risposta whoami

---

## Parte 5: Pattern per Nuovi Servizi

Ora hai il pattern per esporre qualsiasi servizio:

### Step per Aggiungere un Nuovo Servizio

**1. Deployment + Service** (in `k3s/apps/<servizio>/`):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: homelab
spec:
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: myapp:latest
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: myapp-service
  namespace: homelab
spec:
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
```

**2. Aggiungere route in Caddyfile**:

```caddyfile
*.elaine.pw {
  tls {
    dns cloudflare {env.CF_API_TOKEN}
  }
  
  @myapp host myapp.elaine.pw
  handle @myapp {
    reverse_proxy myapp-service.homelab.svc.cluster.local:80
  }
  
  # ... altri servizi
}
```

**3. Commit e push**: Flux applica automaticamente!

---

## Riepilogo e Verifica Finale

### ✅ Checklist

- [ ] MetalLB installato e funzionante
- [ ] `kubectl get ipaddresspool -n metallb-system` mostra il pool
- [ ] Service LoadBalancer ricevono EXTERNAL-IP
- [ ] Caddy deployed in namespace `ingress`
- [ ] `curl http://<EXTERNAL-IP>/healthz` risponde "OK"
- [ ] Port forwarding configurato sul router (80/443)
- [ ] DNS Cloudflare punta al tuo IP pubblico
- [ ] `curl https://whoami.elaine.pw` funziona
- [ ] Certificato SSL valido da Let's Encrypt

### 🎓 Concetti Appresi

**Service Types**:
- **ClusterIP**: IP interno al cluster, non raggiungibile dall'esterno
- **NodePort**: Espone service su una porta del nodo (es. 30000-32767)
- **LoadBalancer**: Richiede IP esterno (fornito da MetalLB in bare-metal)

**Ingress**:
- **Ingress Resource**: Regole di routing (cosa → dove)
- **Ingress Controller**: Implementazione che applica le regole (Caddy, nginx, Traefik)

**DNS Resolution in k8s**:
- `service-name.namespace.svc.cluster.local`
- Es: `whoami-service.homelab.svc.cluster.local`
- Abbreviato: `whoami-service.homelab` (se nello stesso namespace, solo `whoami-service`)

### 🧪 Esperimenti da Provare

1. **Test Load Balancing**:
```bash
for i in {1..10}; do curl -s https://whoami.elaine.pw | grep Hostname; done
```
Dovresti vedere pod diversi rispondere (whoami-xxx, whoami-yyy).

2. **Test Self-Healing**:
```bash
# Uccidi un pod
kubectl delete pod -n homelab -l app=whoami --force

# Controlla che venga ricreato
kubectl get pods -n homelab -w
```

3. **Scale Up/Down**:
```bash
kubectl scale deployment whoami -n homelab --replicas=5
kubectl get pods -n homelab
```

---

## Troubleshooting

### Problema: LoadBalancer EXTERNAL-IP rimane <pending>

**Cause**:
- MetalLB non installato correttamente
- IPAddressPool non configurato

**Debug**:
```bash
kubectl logs -n metallb-system deploy/controller
kubectl get ipaddresspool -n metallb-system -o yaml
```

### Problema: Certificato SSL non viene ottenuto

**Cause**:
- Cloudflare API token invalido
- Cloudflare Proxy abilitato (deve essere disabilitato)
- DNS non propagato

**Debug**:
```bash
# Logs Caddy
kubectl logs -n ingress deploy/caddy-ingress | grep -i error

# Verifica Secret
kubectl get secret -n ingress cloudflare-api-token -o yaml

# Test DNS
dig whoami.elaine.pw
```

**Test Cloudflare token**:
```bash
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json"
```

### Problema: 404 Not Found su servizio

**Cause**:
- Caddyfile non aggiornato con la route
- Service name sbagliato
- Namespace sbagliato

**Debug**:
```bash
# Verifica Service esiste
kubectl get svc -n homelab

# Verifica DNS interno
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup whoami-service.homelab.svc.cluster.local

# Logs Caddy
kubectl logs -n ingress deploy/caddy-ingress
```

### Problema: Timeout connessione

**Cause**:
- Firewall blocca porte
- Port forwarding non configurato
- Service selector sbagliato (nessun pod matchato)

**Debug**:
```bash
# Verifica Service ha endpoints
kubectl get endpoints -n homelab whoami-service

# Se empty, controlla selector
kubectl get pods -n homelab --show-labels
kubectl describe svc -n homelab whoami-service
```

---

## Prossimi Passi

🎉 **Congratulazioni!** Hai un Ingress Controller funzionante con SSL automatico!

**Fase 3**: [Primi Servizi - Homer e Umami](./03-first-services.md)

Migrerai:
- Homer (dashboard)
- Umami (analytics)

Imparerai:
- PersistentVolumeClaims in dettaglio
- ConfigMaps per configurazione app
- Multi-container pods
- Database in Kubernetes

Ci vediamo lì! 🚀

---

## Note Finali

### Alternative a Caddy

Se preferisci altri Ingress Controller:

**Traefik** (già conosci da Docker):
- Supporto nativo Ingress resources
- Dashboard UI
- Più feature (middleware, ecc.)

**Installazione**:
```bash
helm repo add traefik https://helm.traefik.io/traefik
helm install traefik traefik/traefik -n ingress
```

**nginx-ingress**:
- Molto diffuso
- Performante
- Configurazione via annotations

**cert-manager + nginx**:
- cert-manager gestisce certificati separatamente
- nginx fa solo reverse proxy

**Raccomandazione**: Continua con Caddy per ora, in Fase 6 potrai valutare Traefik se ti manca dashboard UI.
