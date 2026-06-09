# Template per Nuovo Servizio Kubernetes

Questo template ti aiuta a creare manifest per un nuovo servizio in modo consistente.

## Uso del Template

```bash
# Copia il template per un nuovo servizio
cp -r k3s/templates/service-template k3s/apps/my-new-service

cd k3s/apps/my-new-service

# Modifica i file sostituendo i placeholder:
# - SERVICE_NAME
# - NAMESPACE
# - IMAGE_NAME
# - PORT_NUMBER
# ecc.
```

---

## File Inclusi

```
service-template/
├── README.md              # Questo file
├── namespace.yaml         # (Opzionale) se serve namespace dedicato
├── deployment.yaml        # Deployment principale
├── service.yaml           # Service (ClusterIP)
├── ingress.yaml           # (Opzionale) per servizi HTTP
├── pvc.yaml               # (Opzionale) storage persistente
├── configmap.yaml         # (Opzionale) file di configurazione
├── secret.yaml.example    # (Template) NON committare secret reali!
└── kustomization.yaml     # Kustomize per applicare tutto insieme
```

---

## Workflow

### 1. Copia Template
```bash
cp -r k3s/templates/service-template k3s/apps/myservice
cd k3s/apps/myservice
```

### 2. Personalizza File

Cerca e sostituisci:
- `SERVICE_NAME` → nome del tuo servizio (es. `jellyfin`)
- `NAMESPACE` → namespace k8s (es. `homelab`)
- `IMAGE_NAME` → immagine Docker (es. `nginx:alpine`)
- `CONTAINER_PORT` → porta del container (es. `80`)
- `SERVICE_PORT` → porta del service (es. `80`)
- `HOSTNAME` → hostname per ingress (es. `myservice.elaine.pw`)

### 3. Rimuovi File Non Necessari

```bash
# Se non serve ingress
rm ingress.yaml

# Se non serve storage
rm pvc.yaml

# Se non serve configmap
rm configmap.yaml

# Aggiorna kustomization.yaml di conseguenza
```

### 4. Applica

**Opzione A: Via Flux (GitOps)**
```bash
git add k3s/apps/myservice/
git commit -m "Add myservice"
git push
# Flux applica automaticamente in ~1 minuto
```

**Opzione B: Manuale (per test)**
```bash
kubectl apply -k k3s/apps/myservice/
```

---

## Checklist Pre-Deploy

- [ ] Tutte le occorrenze di `SERVICE_NAME` sostituite
- [ ] Namespace corretto in tutti i file
- [ ] Image name e tag verificati
- [ ] Porte corrette (containerPort, servicePort)
- [ ] Storage (PVC) configurato se necessario
- [ ] ConfigMap creato se serve config file
- [ ] Secret creato (via kubectl, NON committato)
- [ ] Ingress configurato se HTTP
- [ ] Resources (CPU/RAM) impostati
- [ ] Labels consistenti in tutti i file
- [ ] kustomization.yaml include tutti i file necessari

---

## Tips

### Per servizi stateless
- Usa `Deployment`
- `replicas: 2` o più per high availability
- PVC opzionale

### Per database o servizi stateful
- Usa `StatefulSet` invece di `Deployment`
- PVC richiesto
- Service headless (`clusterIP: None`)

### Per job periodici
- Usa `CronJob` invece di `Deployment`
- Vedi `k3s/templates/cronjob-template/`

### Per servizi esterni
- Crea solo `Service` con `ExternalName`
- Nessun Deployment

---

Torna alla [Guida Principale](../docs/00-migration-guide.md)
