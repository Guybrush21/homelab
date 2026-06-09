# Docker Compose → Kubernetes Cheatsheet

Guida di traduzione rapida da Docker Compose a Kubernetes manifest.

---

## Struttura File

### Docker Compose
```
service-name/
├── docker-compose.yaml  # Tutto in un file
├── .env                 # Secrets e config
└── container-data/      # Volumes
```

### Kubernetes
```
service-name/
├── namespace.yaml       # Namespace (opzionale)
├── deployment.yaml      # Deployment
├── service.yaml         # Service
├── ingress.yaml         # Ingress (se HTTP)
├── configmap.yaml       # Config files
├── secret.yaml          # Secrets (cifrati con SOPS)
├── pvc.yaml             # Storage
└── kustomization.yaml   # Kustomize (opzionale)
```

---

## Mappatura Concetti

| Docker Compose | Kubernetes | Note |
|----------------|------------|------|
| `services:` | `Deployment` | O `StatefulSet` se stateful |
| `ports:` | `Service` + `Ingress` | Separati in k8s |
| `volumes:` | `PersistentVolumeClaim` | O `hostPath`, `emptyDir` |
| `environment:` | `ConfigMap` / `Secret` | Separati per type |
| `networks:` | `Service` (DNS interno) | Network automatico in k8s |
| `depends_on:` | `initContainer` | O health probes |
| `restart:` | Deployment gestisce | Automatico in k8s |
| `.env` file | `Secret` | Mai committare in Git! |

---

## Esempi di Conversione

### 1. Servizio Semplice (Stateless)

#### Docker Compose
```yaml
version: "3"
services:
  nginx:
    image: nginx:alpine
    container_name: nginx
    ports:
      - "8080:80"
    volumes:
      - ./html:/usr/share/nginx/html
    environment:
      - NGINX_HOST=example.com
    restart: unless-stopped
    networks:
      - reverseproxy

networks:
  reverseproxy:
    external: true
```

#### Kubernetes

**deployment.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: homelab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        env:
        - name: NGINX_HOST
          value: "example.com"
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        persistentVolumeClaim:
          claimName: nginx-html
```

**service.yaml**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: homelab
spec:
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
```

**pvc.yaml**:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nginx-html
  namespace: homelab
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

**ingress.yaml** (se esposto via HTTP):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: homelab
spec:
  rules:
  - host: nginx.elaine.pw
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-service
            port:
              number: 80
```

---

### 2. Servizio con Database (Multi-container)

#### Docker Compose
```yaml
version: "3"
services:
  app:
    image: myapp:latest
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgresql://user:pass@db:5432/mydb
    depends_on:
      - db
    networks:
      - app-network

  db:
    image: postgres:15
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: mydb
    volumes:
      - db-data:/var/lib/postgresql/data
    networks:
      - app-network

volumes:
  db-data:

networks:
  app-network:
```

#### Kubernetes

**secret.yaml** (crea con kubectl, non committare!):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: homelab
type: Opaque
stringData:
  username: user
  password: pass
  database: mydb
```

**postgres-deployment.yaml**:
```yaml
apiVersion: apps/v1
kind: StatefulSet  # StatefulSet per database
metadata:
  name: postgres
  namespace: homelab
spec:
  serviceName: postgres
  replicas: 1
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
        env:
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: username
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: database
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 10Gi
```

**postgres-service.yaml**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: homelab
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
  clusterIP: None  # Headless service per StatefulSet
```

**app-deployment.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: homelab
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      initContainers:
      - name: wait-for-db
        image: busybox
        command: ['sh', '-c', 'until nslookup postgres; do sleep 2; done']
      
      containers:
      - name: app
        image: myapp:latest
        ports:
        - containerPort: 3000
        env:
        - name: DATABASE_URL
          value: "postgresql://$(DB_USER):$(DB_PASS)@postgres:5432/$(DB_NAME)"
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: username
        - name: DB_PASS
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
        - name: DB_NAME
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: database
```

---

### 3. Volumes e Storage

#### Docker Compose

**Named Volume**:
```yaml
services:
  app:
    volumes:
      - app-data:/data

volumes:
  app-data:
```

**Kubernetes (PVC)**:
```yaml
# pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi

---
# In deployment
volumeMounts:
- name: data
  mountPath: /data
volumes:
- name: data
  persistentVolumeClaim:
    claimName: app-data
```

---

#### Docker Compose

**Bind Mount (host path)**:
```yaml
services:
  jellyfin:
    volumes:
      - /home/jigen/media:/media:ro  # Read-only
```

**Kubernetes (hostPath)**:
```yaml
# In deployment
volumeMounts:
- name: media
  mountPath: /media
  readOnly: true
volumes:
- name: media
  hostPath:
    path: /home/jigen/media
    type: Directory
```

---

#### Docker Compose

**Config file mount**:
```yaml
services:
  nginx:
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
```

**Kubernetes (ConfigMap)**:
```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  nginx.conf: |
    server {
      listen 80;
      ...
    }

---
# In deployment
volumeMounts:
- name: config
  mountPath: /etc/nginx/nginx.conf
  subPath: nginx.conf
volumes:
- name: config
  configMap:
    name: nginx-config
```

---

### 4. Environment Variables

#### Docker Compose

**Inline**:
```yaml
services:
  app:
    environment:
      - APP_ENV=production
      - DEBUG=false
```

**From file**:
```yaml
services:
  app:
    env_file:
      - .env
```

#### Kubernetes

**Inline**:
```yaml
env:
- name: APP_ENV
  value: "production"
- name: DEBUG
  value: "false"
```

**From ConfigMap**:
```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  APP_ENV: production
  DEBUG: "false"

---
# In deployment
envFrom:
- configMapRef:
    name: app-config
```

**From Secret**:
```yaml
env:
- name: API_KEY
  valueFrom:
    secretKeyRef:
      name: api-secrets
      key: api-key
```

---

### 5. Networking

#### Docker Compose

**Expose ports**:
```yaml
services:
  web:
    ports:
      - "8080:80"     # Host:Container
      - "443:443"
```

#### Kubernetes

**LoadBalancer Service** (espone IP esterno):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-lb
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
  - name: http
    port: 80
    targetPort: 80
  - name: https
    port: 443
    targetPort: 443
```

**Ingress** (HTTP routing):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
spec:
  rules:
  - host: web.elaine.pw
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

---

#### Docker Compose

**Internal network**:
```yaml
services:
  app:
    networks:
      - backend
  
  db:
    networks:
      - backend

networks:
  backend:
```

#### Kubernetes

**Automatico via Service DNS**:

```yaml
# app può raggiungere db via:
# - db-service (stesso namespace)
# - db-service.homelab (specificando namespace)
# - db-service.homelab.svc.cluster.local (FQDN)

# Nessuna configurazione network necessaria!
```

---

### 6. Health Checks

#### Docker Compose
```yaml
services:
  app:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

#### Kubernetes
```yaml
# In deployment
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 40
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
```

---

### 7. Resource Limits

#### Docker Compose
```yaml
services:
  app:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M
```

#### Kubernetes
```yaml
# In deployment
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

---

### 8. Restart Policy

#### Docker Compose
```yaml
services:
  app:
    restart: unless-stopped
    # Opzioni: no, always, on-failure, unless-stopped
```

#### Kubernetes

**Deployment**: Restart automatico sempre abilitato

**Pod restart policy**:
```yaml
spec:
  restartPolicy: Always  # Always, OnFailure, Never
```

**Per Job**:
```yaml
spec:
  template:
    spec:
      restartPolicy: OnFailure
```

---

## Mapping Completo di un Servizio Reale

### Docker Compose: Jellyfin

```yaml
version: "3"
services:
  jellyfin:
    image: lscr.io/linuxserver/jellyfin
    container_name: jellyfin
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Rome
    volumes:
      - ./container-data/config:/config
      - /home/jigen/media/film:/data/movies:ro
      - /home/jigen/media/tvseries:/data/tvseries:ro
    devices:
      - /dev/dri/renderD128:/dev/dri/renderD128
    ports:
      - "8096:8096"
    restart: unless-stopped
    networks:
      - reverseproxy
    labels:
      traefik.enable: "true"
      traefik.http.routers.jellyfin.rule: "Host(`jellyfin.elaine.pw`)"

networks:
  reverseproxy:
    external: true
```

### Kubernetes: Jellyfin

**namespace.yaml**:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: homelab
```

**pvc.yaml**:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jellyfin-config
  namespace: homelab
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

**deployment.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jellyfin
  namespace: homelab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jellyfin
  template:
    metadata:
      labels:
        app: jellyfin
    spec:
      securityContext:
        fsGroup: 1000  # PGID
        supplementalGroups: [44, 109]  # video, render groups
      
      containers:
      - name: jellyfin
        image: lscr.io/linuxserver/jellyfin
        env:
        - name: PUID
          value: "1000"
        - name: PGID
          value: "1000"
        - name: TZ
          value: "Europe/Rome"
        
        ports:
        - containerPort: 8096
          name: http
        
        volumeMounts:
        - name: config
          mountPath: /config
        - name: movies
          mountPath: /data/movies
          readOnly: true
        - name: tvseries
          mountPath: /data/tvseries
          readOnly: true
        - name: dri
          mountPath: /dev/dri
        
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "4Gi"
            cpu: "2000m"
      
      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: jellyfin-config
      - name: movies
        hostPath:
          path: /home/jigen/media/film
          type: Directory
      - name: tvseries
        hostPath:
          path: /home/jigen/media/tvseries
          type: Directory
      - name: dri
        hostPath:
          path: /dev/dri
          type: Directory
```

**service.yaml**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: jellyfin-service
  namespace: homelab
spec:
  selector:
    app: jellyfin
  ports:
  - protocol: TCP
    port: 8096
    targetPort: 8096
```

**ingress.yaml** (o entry in Caddyfile):
```yaml
# Nel Caddyfile di Caddy:
# @jellyfin host jellyfin.elaine.pw
# handle @jellyfin {
#   reverse_proxy jellyfin-service.homelab.svc.cluster.local:8096
# }
```

---

## Checklist di Traduzione

Quando converti un servizio da Docker Compose a k8s:

- [ ] **Image**: Stessa immagine Docker funziona in k8s
- [ ] **Namespace**: Crea o usa namespace esistente
- [ ] **Deployment**: Crea Deployment (o StatefulSet se stateful)
- [ ] **Service**: Crea Service (ClusterIP se interno, LoadBalancer se esposto)
- [ ] **Volumes**: Traduci in PVC, hostPath, o ConfigMap
- [ ] **Environment**: Usa ConfigMap per config, Secret per credenziali
- [ ] **Ports**: Service + Ingress per HTTP, LoadBalancer per altre porte
- [ ] **Networks**: DNS automatico via Service, nessuna config extra
- [ ] **depends_on**: Usa initContainer per wait
- [ ] **Health checks**: Aggiungi livenessProbe e readinessProbe
- [ ] **Resources**: Imposta requests/limits CPU/RAM
- [ ] **Secrets**: Non committare in Git! Usa kubectl create secret o SOPS
- [ ] **Labels**: Aggiungi labels per organization
- [ ] **Security**: SecurityContext per user/group, capabilities

---

## Tips e Best Practices

### 1. Un servizio = Una directory

```
k3s/apps/
├── jellyfin/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── pvc.yaml
│   └── kustomization.yaml
├── homer/
│   └── ...
```

### 2. Usa Kustomize per organizzare

```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
  - pvc.yaml
```

Applica tutto:
```bash
kubectl apply -k k3s/apps/jellyfin/
```

### 3. Naming convention

```yaml
# Deployment
name: jellyfin

# Service
name: jellyfin-service  # O semplicemente jellyfin

# PVC
name: jellyfin-config
name: jellyfin-data

# ConfigMap
name: jellyfin-config

# Secret
name: jellyfin-secrets
```

### 4. Labels consistenti

```yaml
metadata:
  labels:
    app: jellyfin
    component: media
    environment: production
```

### 5. Annotations per metadata

```yaml
metadata:
  annotations:
    description: "Media server"
    migrated-from: "docker-compose"
    migration-date: "2026-06-06"
```

---

## Differenze Chiave da Ricordare

| Aspetto | Docker Compose | Kubernetes |
|---------|----------------|------------|
| **File** | Tutto in 1 file | Multipli file YAML |
| **Networking** | Esplicito (networks:) | Automatico via Service |
| **Scaling** | Manuale | Automatico (HPA) |
| **Updates** | Manuale stop/start | Rolling update automatico |
| **Health** | Healthcheck opzionale | Probes raccomandati |
| **Secrets** | .env file | Secret objects |
| **Storage** | Volume semplice | PV/PVC più complesso |
| **Discovery** | Container name | Service DNS |
| **Restart** | restart policy | Gestito da controller |

---

## Comandi di Migrazione Utili

### Genera Kubernetes YAML da Docker Compose

**Kompose** (tool ufficiale):
```bash
# Installa
curl -L https://github.com/kubernetes/kompose/releases/download/v1.31.2/kompose-linux-amd64 -o kompose
chmod +x kompose
sudo mv kompose /usr/local/bin/

# Converti
cd service-directory/
kompose convert -f docker-compose.yaml

# Output: deployment.yaml, service.yaml, pvc.yaml, ...
```

**⚠️ Nota**: Kompose è un punto di partenza, richiede sempre revisione manuale!

### Test in locale con Kind

```bash
# Crea cluster locale
kind create cluster --name test

# Testa manifest
kubectl apply -f deployment.yaml

# Cleanup
kind delete cluster --name test
```

---

## Risorse

- [Kompose Documentation](https://kompose.io/)
- [Kubernetes from Docker Compose](https://kubernetes.io/docs/tasks/configure-pod-container/)
- [Docker Compose vs Kubernetes](https://www.docker.com/blog/docker-compose-vs-kubernetes/)

---

Torna alla [Guida Principale](./00-migration-guide.md)
