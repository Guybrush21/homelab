# Concetti Fondamentali di Kubernetes

Guida di riferimento rapido ai concetti chiave di Kubernetes.

---

## Architettura Cluster

### Cluster
Un **cluster Kubernetes** è un insieme di macchine (nodi) che eseguono applicazioni containerizzate.

**Componenti**:
- **Control Plane**: Il "cervello" del cluster (API server, scheduler, controller manager)
- **Worker Nodes**: Macchine che eseguono i container

**Nel tuo homelab**:
- Single-node cluster: un nodo è sia control plane che worker

---

## Oggetti Base

### Pod

**Cos'è**: L'unità più piccola in Kubernetes. Wrappa uno o più container.

**Caratteristiche**:
- Condivide network namespace (stesso IP)
- Condivide storage volumes
- Effimero (può morire e essere ricreato)
- Non si crea mai direttamente (si usa Deployment)

**Esempio**:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
```

**Comandi utili**:
```bash
kubectl get pods
kubectl get pods -n <namespace>
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl logs <pod-name> -c <container-name>  # Se multi-container
kubectl exec -it <pod-name> -- /bin/sh
kubectl delete pod <pod-name>
```

---

### Deployment

**Cos'è**: Gestisce un set di Pod identici (replica set).

**Funzioni**:
- Crea e gestisce Pod
- Mantiene il numero desiderato di repliche
- Rolling updates (aggiorna senza downtime)
- Rollback automatico se fallisce

**Esempio**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 3  # Numero di pod desiderati
  selector:
    matchLabels:
      app: nginx
  template:  # Template del Pod
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.24
        ports:
        - containerPort: 80
```

**Comandi utili**:
```bash
kubectl get deployments
kubectl describe deployment <name>
kubectl scale deployment <name> --replicas=5
kubectl rollout status deployment <name>
kubectl rollout history deployment <name>
kubectl rollout undo deployment <name>
```

**Quando usare**:
- App stateless
- Serve auto-scaling
- Serve rolling updates

---

### StatefulSet

**Cos'è**: Come Deployment, ma per applicazioni stateful.

**Differenze da Deployment**:
- Pod hanno **identity stabile** (nome fisso: pod-0, pod-1, pod-2...)
- Storage persistente legato al pod specifico
- Ordine di creazione/eliminazione garantito

**Quando usare**:
- Database (PostgreSQL, MySQL, MongoDB)
- App che richiedono storage persistente per pod
- App che richiedono network identity stabile

**Esempio**:
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:  # PVC per ogni replica
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 10Gi
```

---

### Service

**Cos'è**: Espone un set di Pod con un IP/DNS stabile.

**Problema**: Pod hanno IP dinamici che cambiano quando vengono ricreati.  
**Soluzione**: Service fornisce un endpoint stabile.

**Tipi di Service**:

#### ClusterIP (default)
- IP interno al cluster
- Non accessibile dall'esterno
- Usa DNS: `<service-name>.<namespace>.svc.cluster.local`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80        # Porta del Service
    targetPort: 8080  # Porta del container
```

#### NodePort
- Espone service su una porta di ogni nodo (30000-32767)
- Accessibile via `<NODE-IP>:<NODE-PORT>`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-nodeport
spec:
  type: NodePort
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30080  # Opzionale, altrimenti random
```

#### LoadBalancer
- Richiede IP esterno (cloud provider o MetalLB)
- Nel tuo homelab: MetalLB assegna IP locale

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-lb
spec:
  type: LoadBalancer
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 8080
```

**Comandi utili**:
```bash
kubectl get services
kubectl get svc  # Abbreviato
kubectl describe svc <name>
kubectl get endpoints <service-name>  # Vedi Pod collegati
```

---

### Ingress

**Cos'è**: Regole di routing HTTP/HTTPS per esporre servizi all'esterno.

**Funzioni**:
- Routing basato su hostname (homer.elaine.pw → homer-service)
- Routing basato su path (/api → api-service, /web → web-service)
- SSL/TLS termination

**Richiede**: Ingress Controller (Caddy, Traefik, nginx-ingress)

**Esempio**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: homer-ingress
  namespace: homelab
spec:
  rules:
  - host: homer.elaine.pw
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: homer-service
            port:
              number: 80
  tls:
  - hosts:
    - homer.elaine.pw
    secretName: homer-tls  # Secret con certificato SSL
```

**Comandi utili**:
```bash
kubectl get ingress
kubectl describe ingress <name>
```

---

## Storage

### Volume

**Cos'è**: Directory montata in un container.

**Tipi comuni**:

**emptyDir**: Volume temporaneo, vive quanto il Pod
```yaml
volumes:
- name: cache
  emptyDir: {}
```

**hostPath**: Monta directory dall'host (nodo)
```yaml
volumes:
- name: data
  hostPath:
    path: /mnt/data
    type: Directory
```

**configMap**: Monta ConfigMap come file
```yaml
volumes:
- name: config
  configMap:
    name: app-config
```

**secret**: Monta Secret come file
```yaml
volumes:
- name: secrets
  secret:
    secretName: db-credentials
```

**persistentVolumeClaim**: Usa PVC
```yaml
volumes:
- name: data
  persistentVolumeClaim:
    claimName: my-pvc
```

---

### PersistentVolume (PV)

**Cos'è**: Storage provisioned nel cluster (disco, NFS, cloud storage).

**Chi lo crea**:
- Admin manualmente
- Storage provisioner automaticamente (Local Path Provisioner in k3s)

**Esempio**:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-example
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/data
```

**Access Modes**:
- `ReadWriteOnce` (RWO): Montato R/W da un solo nodo
- `ReadOnlyMany` (ROX): Montato R/O da più nodi
- `ReadWriteMany` (RWX): Montato R/W da più nodi (richiede NFS o storage condiviso)

---

### PersistentVolumeClaim (PVC)

**Cos'è**: Richiesta di storage da parte di un Pod.

**Flusso**:
1. Pod → richiede PVC
2. PVC → cerca PV disponibile (o provisioner ne crea uno)
3. PVC ↔ PV → binding
4. Pod usa storage

**Esempio**:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: local-path  # StorageClass da usare
```

**Uso nel Pod**:
```yaml
spec:
  containers:
  - name: postgres
    image: postgres:15
    volumeMounts:
    - name: data
      mountPath: /var/lib/postgresql/data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: postgres-pvc
```

**Comandi utili**:
```bash
kubectl get pv
kubectl get pvc
kubectl describe pvc <name>
```

---

### StorageClass

**Cos'è**: Template per provisioning automatico di PV.

**k3s default**: `local-path` (crea directory su disco locale)

**Esempio**:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: kubernetes.io/no-provisioner
parameters:
  type: ssd
volumeBindingMode: WaitForFirstConsumer
```

**Comandi**:
```bash
kubectl get storageclass
kubectl get sc  # Abbreviato
```

---

## Configurazione

### ConfigMap

**Cos'è**: Configurazione key-value per app.

**Uso**:
- File di configurazione (nginx.conf, Caddyfile, ecc.)
- Environment variables
- Command-line arguments

**Esempio**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  # Key-value semplici
  DATABASE_HOST: postgres-service
  DATABASE_PORT: "5432"
  
  # File completi
  app.conf: |
    server {
      listen 80;
      server_name example.com;
    }
```

**Uso come env variables**:
```yaml
spec:
  containers:
  - name: app
    envFrom:
    - configMapRef:
        name: app-config
```

**Uso come file**:
```yaml
spec:
  containers:
  - name: nginx
    volumeMounts:
    - name: config
      mountPath: /etc/nginx/nginx.conf
      subPath: nginx.conf
  volumes:
  - name: config
    configMap:
      name: nginx-config
```

**Comandi**:
```bash
kubectl get configmap
kubectl describe configmap <name>
kubectl create configmap my-config --from-file=config.yaml
kubectl create configmap my-config --from-literal=key=value
```

---

### Secret

**Cos'è**: Come ConfigMap, ma per dati sensibili (password, token, chiavi).

**Differenze da ConfigMap**:
- Valori base64-encoded (non crittografati di default!)
- Linee guida best practice per storage sicuro

**Tipi**:
- `Opaque`: generico (default)
- `kubernetes.io/dockerconfigjson`: credenziali Docker registry
- `kubernetes.io/tls`: certificati TLS

**Esempio**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
data:
  username: cG9zdGdyZXM=  # "postgres" in base64
  password: c2VjcmV0MTIz    # "secret123" in base64
```

**Creazione da CLI**:
```bash
kubectl create secret generic db-credentials \
  --from-literal=username=postgres \
  --from-literal=password=secret123
```

**Uso come env**:
```yaml
spec:
  containers:
  - name: app
    env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: password
```

**Uso come file**:
```yaml
spec:
  containers:
  - name: app
    volumeMounts:
    - name: secrets
      mountPath: /etc/secrets
      readOnly: true
  volumes:
  - name: secrets
    secret:
      secretName: db-credentials
```

**⚠️ Sicurezza**: In Fase 5 userai SOPS per cifrare Secret in Git!

---

## Organizzazione

### Namespace

**Cos'è**: Isolamento virtuale all'interno del cluster.

**Uso**:
- Separare ambienti (dev, staging, prod)
- Separare team/progetti
- Resource quotas per namespace

**Namespaces di sistema**:
- `default`: namespace di default
- `kube-system`: componenti k8s
- `kube-public`: risorse pubbliche
- `kube-node-lease`: heartbeat nodi

**Esempio**:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: homelab
```

**Comandi**:
```bash
kubectl get namespaces
kubectl get ns  # Abbreviato
kubectl create namespace dev
kubectl config set-context --current --namespace=homelab  # Cambia default
kubectl get pods --all-namespaces  # Tutti i namespace
kubectl get pods -A  # Abbreviato
```

**DNS tra namespace**:
```
<service-name>.<namespace>.svc.cluster.local

Esempi:
- homer-service.homelab.svc.cluster.local
- postgres.database.svc.cluster.local
```

---

### Labels e Selectors

**Labels**: Key-value pairs attaccati a oggetti.

**Uso**:
- Selezionare oggetti
- Organizzare risorse
- Routing (Service → Pod)

**Esempio**:
```yaml
metadata:
  labels:
    app: nginx
    environment: production
    version: "1.24"
```

**Selector** in Service:
```yaml
spec:
  selector:
    app: nginx  # Seleziona tutti i Pod con label app=nginx
```

**Query con labels**:
```bash
kubectl get pods -l app=nginx
kubectl get pods -l environment=production
kubectl get pods -l 'app in (nginx,apache)'
kubectl get pods -l app!=nginx
```

---

### Annotations

**Cos'è**: Metadata key-value non usati per selezione.

**Uso**:
- Informazioni per tool esterni
- Configurazione Ingress Controller
- Policy e configuration

**Esempio**:
```yaml
metadata:
  annotations:
    description: "Homer dashboard for homelab"
    maintainer: "nic@elaine.pw"
    # Ingress annotations
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
```

---

## Scheduling e Lifecycle

### initContainers

**Cos'è**: Container che eseguono prima dei container principali.

**Uso**:
- Setup iniziale (es. migration database)
- Aspettare dipendenze (es. DB pronto)
- Scaricare file

**Esempio**:
```yaml
spec:
  initContainers:
  - name: wait-for-db
    image: busybox
    command: ['sh', '-c', 'until nslookup postgres; do sleep 2; done']
  
  containers:
  - name: app
    image: myapp:latest
```

**Ordine**:
1. initContainers eseguono in sequenza
2. Se uno fallisce, Pod non si avvia
3. Quando tutti completano, container principali partono

---

### Probes

**Cos'è**: Health check per container.

**Tipi**:

**Liveness Probe**: Controlla se container è alive
- Se fallisce: k8s riavvia container

**Readiness Probe**: Controlla se container è pronto a ricevere traffico
- Se fallisce: k8s rimuove pod da Service endpoints

**Startup Probe**: Per app con startup lento
- Disabilita liveness/readiness fino a primo successo

**Esempio**:
```yaml
spec:
  containers:
  - name: app
    livenessProbe:
      httpGet:
        path: /healthz
        port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
    
    readinessProbe:
      httpGet:
        path: /ready
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 5
    
    startupProbe:
      httpGet:
        path: /startup
        port: 8080
      failureThreshold: 30
      periodSeconds: 10
```

**Metodi**:
- `httpGet`: HTTP request
- `tcpSocket`: TCP connection
- `exec`: Esegue comando

---

### Resources

**Cos'è**: Limiti CPU/RAM per container.

**Requests**: Risorse garantite al container  
**Limits**: Massimo che il container può usare

**Esempio**:
```yaml
spec:
  containers:
  - name: app
    resources:
      requests:
        memory: "128Mi"
        cpu: "250m"  # 0.25 CPU
      limits:
        memory: "256Mi"
        cpu: "500m"  # 0.5 CPU
```

**Unità**:
- CPU: millicores (1000m = 1 CPU core)
- Memory: Ki, Mi, Gi (o K, M, G)

**Behavior**:
- Se supera limit memory: Pod killed (OOMKilled)
- Se supera limit CPU: throttled (rallentato)

---

## Jobs e CronJobs

### Job

**Cos'è**: Esegue un task una volta fino a completamento.

**Uso**:
- Migration database
- Batch processing
- Backup one-time

**Esempio**:
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pi-calculation
spec:
  template:
    spec:
      containers:
      - name: pi
        image: perl
        command: ["perl", "-Mbignum=bpi", "-wle", "print bpi(2000)"]
      restartPolicy: Never
  backoffLimit: 4
```

### CronJob

**Cos'è**: Esegue Job su schedule (come cron Linux).

**Uso**:
- Backup periodici
- Cleanup job
- Report generation

**Esempio**:
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup
spec:
  schedule: "0 2 * * *"  # Ogni giorno alle 02:00
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: backup-tool:latest
            command: ["/bin/backup.sh"]
          restartPolicy: OnFailure
```

**Schedule format**: Cron standard `* * * * *` (min hour day month weekday)

---

## Security

### ServiceAccount

**Cos'è**: Identity per Pod (come "user" per processi).

**Uso**:
- Accesso API Kubernetes da dentro Pod
- RBAC permissions

**Esempio**:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
---
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  serviceAccountName: my-app-sa
  containers:
  - name: app
    image: myapp:latest
```

### SecurityContext

**Cos'è**: Impostazioni security per Pod/container.

**Esempio**:
```yaml
spec:
  securityContext:
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
  
  containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
```

---

## Comandi kubectl Essenziali

### Get Resources
```bash
kubectl get <resource>
kubectl get pods
kubectl get pods -n homelab
kubectl get pods -A  # All namespaces
kubectl get pods -o wide  # Più info
kubectl get pods -o yaml  # Output YAML
kubectl get pods -w  # Watch (live updates)
```

### Describe (dettagli)
```bash
kubectl describe <resource> <name>
kubectl describe pod nginx-xxx
```

### Logs
```bash
kubectl logs <pod-name>
kubectl logs <pod-name> -c <container-name>
kubectl logs <pod-name> -f  # Follow (tail -f)
kubectl logs <pod-name> --previous  # Container crashato
```

### Exec (esegui comando in pod)
```bash
kubectl exec <pod-name> -- <command>
kubectl exec nginx-xxx -- ls /usr/share/nginx/html
kubectl exec -it nginx-xxx -- /bin/sh  # Interactive shell
```

### Apply/Delete
```bash
kubectl apply -f manifest.yaml
kubectl apply -f directory/  # Tutti i file nella dir
kubectl delete -f manifest.yaml
kubectl delete pod <name>
kubectl delete pod <name> --force --grace-period=0  # Force
```

### Port Forward (accesso temporaneo)
```bash
kubectl port-forward pod/<pod-name> 8080:80
kubectl port-forward svc/<service-name> 8080:80
# Accesso: http://localhost:8080
```

### Edit (modifica risorsa)
```bash
kubectl edit <resource> <name>
kubectl edit deployment nginx
```

### Scale
```bash
kubectl scale deployment <name> --replicas=3
```

### Rollout (gestione deployment)
```bash
kubectl rollout status deployment/<name>
kubectl rollout history deployment/<name>
kubectl rollout undo deployment/<name>
kubectl rollout restart deployment/<name>
```

---

## Abbreviazioni Comuni

```bash
# Resources
po = pods
svc = services
deploy = deployments
rs = replicasets
ns = namespaces
pv = persistentvolumes
pvc = persistentvolumeclaims
cm = configmaps
sa = serviceaccounts

# Flags
-n = --namespace
-A = --all-namespaces
-o = --output
-w = --watch
-l = --selector (labels)
```

---

## Debugging Flow

**Pod non parte**:
```bash
kubectl get pods
kubectl describe pod <name>  # Eventi
kubectl logs <name>  # Se container è partito
```

**Service non funziona**:
```bash
kubectl get svc <name>
kubectl get endpoints <name>  # Verifica pod collegati
kubectl describe svc <name>
```

**Connectivity test**:
```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
# Dentro pod:
nslookup <service-name>
wget -O- http://<service-name>
```

**Resource usage**:
```bash
kubectl top nodes
kubectl top pods -n homelab
```

---

## Risorse per Approfondire

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Kubernetes API Reference](https://kubernetes.io/docs/reference/kubernetes-api/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [k3s Documentation](https://docs.k3s.io/)

---

Torna alla [Guida Principale](./00-migration-guide.md)
