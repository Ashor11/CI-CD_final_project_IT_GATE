# Ashour Chat Tutorial — 3-Tier Student Project

[docs/itgate-final-pro.png
](https://github.com/Ashor11/CI-CD_final_project_IT_GATE/blob/f0fe9766d5deee46a2d2ca2c93ef51730201e66c/docs/itgate-final-pro.png)

A **multi-service** app (Reaction Wall + Mood of the Day) with **sign-in**: the UI is branded **"Ashour Chat Tutorial"** and uses a single **menu bar** (Sign in | Sign up when logged out; Reaction Wall | Mood | Hello, username | Log out when logged in). Both posting reactions and voting mood **require sign-in**. Built to teach **3-tier architecture**, **Kubernetes**, **Redis** (cache), and **MySQL** (persistence). Backend is **2 microservices** (reactions, mood) that call each other via Kubernetes Services.

## Architecture

- **Namespace 1 (frontend):** Ingress (TLS) + Frontend app (ClusterIP Service, ConfigMap, Secret, NetworkPolicy).
- **Namespace 2 (backend):** 2 microservices — **Reactions** and **Mood** (each: Deployment, ClusterIP Service, ConfigMap, Secret). They call each other via Service DNS in the same namespace. HPA on reactions. NetworkPolicy allows frontend + backend-to-backend; egress to data.
- **Namespace 3 (data):** Redis and MySQL as **StatefulSets** (headless Services), ConfigMaps, Secrets, NetworkPolicy. StorageClass `standard-retain` with `reclaimPolicy: Retain` for MySQL PVCs.

All components communicate **only via Kubernetes Services** (ClusterIP or headless).

---

## Run locally (before containerization)

Try the app on your machine with no Docker images and no Kubernetes. You only need **Node.js**, **Redis**, and **MySQL** (Redis and MySQL can be run via Docker for convenience).

### 1. Start Redis and MySQL

**Option A — Docker (easiest):**

```bash
# Redis
docker run -d --name buzzboard-redis -p 6379:6379 redis:7-alpine redis-server --requirepass buzzboard-redis-secret

# MySQL (creates database and user)
docker run -d --name buzzboard-mysql -p 3306:3306 \
  -e MYSQL_ROOT_PASSWORD=buzzboard-mysql-root \
  -e MYSQL_USER=buzzboard \
  -e MYSQL_PASSWORD=buzzboard-mysql-secret \
  -e MYSQL_DATABASE=buzzboard \
  mysql:8.0
```

**Option B:** Use locally installed Redis and MySQL. Create a database `buzzboard` and user `buzzboard` with password `buzzboard-mysql-secret`.

### 2. Start the two backend services

In **two separate terminals**:

```bash
# Terminal 1 — Reactions (port 8081) — runs auth (signup/signin) and reactions
cd backend/reactions
npm install
PORT=8081 REDIS_HOST=localhost REDIS_PASSWORD=buzzboard-redis-secret MYSQL_HOST=localhost MYSQL_USER=buzzboard MYSQL_PASSWORD=buzzboard-mysql-secret MYSQL_DATABASE=buzzboard JWT_SECRET=buzzboard-jwt-secret-change-in-production npm start
```

```bash
# Terminal 2 — Mood (port 8082)
cd backend/mood
npm install
PORT=8082 REDIS_HOST=localhost REDIS_PASSWORD=buzzboard-redis-secret MYSQL_HOST=localhost MYSQL_USER=buzzboard MYSQL_PASSWORD=buzzboard-mysql-secret MYSQL_DATABASE=buzzboard JWT_SECRET=buzzboard-jwt-secret-change-in-production npm start
```

### 3. Serve the frontend and point it at the backends

Use the **local** config so the browser calls `http://localhost:8081` and `http://localhost:8082`:

```bash
# Copy local config (so the frontend uses localhost:8081 and :8082)
cp frontend/public/config.local.js frontend/public/config.js

# Serve the frontend (from project root)
npx serve frontend/public -l 3000
```

Open **http://localhost:3000** in your browser. You’ll see **Sign in** and **Sign up** first; after signing up and signing in you can use:

- **Reaction Wall** — post messages or emoji (stored with your user); data is in MySQL and cached in Redis (you’ll see “Source: Redis” vs “Source: MySQL” and latency).
- **Mood of the Day** — tap a mood (stored with your user); tally is in MySQL and cached in Redis.

Once this works, you can move on to **containerization** (Docker) and then **Kubernetes**. (For Docker/K8s you don’t rely on `config.js` in the repo — the frontend image uses `config.docker.js` or a ConfigMap, so overwriting `config.js` for local run is fine.)

---

## Prerequisites

- Docker (and optionally Docker Compose for local dev)
- Kubernetes cluster (e.g. minikube, k3d, kind) with:
  - Ingress controller (e.g. ingress-nginx)
  - A default StorageClass or provisioner you can duplicate with `reclaimPolicy: Retain`

## Quick start (Docker Compose)

Runs all five services (Redis, MySQL, reactions, mood, frontend) with one command. No Kubernetes required.

**From the project root** (folder that contains `docker-compose.yml`):

```bash
docker-compose up -d --build
```

**If you don’t see the new UI (Sign in / Sign up, “Ashour Chat Tutorial”):** Docker may be using an old frontend image. Rebuild without cache and restart:

```bash
docker-compose build --no-cache frontend reactions mood
docker-compose up -d
```

Then hard-refresh the browser (Ctrl+Shift+R or Cmd+Shift+R) or open http://localhost:3001 in a private window.

**URLs:**

| Service        | URL                        |
|----------------|----------------------------|
| **Frontend**   | http://localhost:3001      |
| **Reactions API** | http://localhost:8081  |
| **Mood API**   | http://localhost:8082      |

The frontend uses port **3001**. Open **http://localhost:3001**, **Sign up** to create an account, then **Sign in**. After that you can use **Reaction Wall** and **Mood of the Day**; each post and vote is stored with your user. The frontend is built with `config.docker.js` so the browser calls the APIs at localhost:8081 and 8082.

**Useful commands:**

```bash
docker-compose ps              # List running containers
docker-compose logs -f         # Follow all logs
docker-compose logs reactions mood   # Backend logs only
docker-compose down            # Stop and remove containers
```

**Clean and re-run (Docker):** Remove all containers, volumes, and project images; then run again from scratch:

```bash
# From project root
docker-compose down -v                                    # Stop containers and remove volumes
docker rmi frontend:latest reactions:latest mood:latest 2>/dev/null || true   # Remove project images (optional)
docker-compose up -d --build                              # Build and start again
```

Then open **http://localhost:3001**. Use `docker-compose ps` to confirm all five services are Up.

**If the frontend page is blank or doesn’t load data:**

1. **Use http://localhost:3001** (not 3000). If something else is using port 3000, check with `lsof -i :3000`.
2. Rebuild: `docker-compose up -d --build`
3. Check all containers are up: `docker-compose ps` (all five should be “Up”).
4. In the browser: DevTools (F12) → **Console** and **Network**; look for failed requests or CORS errors.
5. Test the APIs: open http://localhost:8081/reactions and http://localhost:8082/mood in the browser — both should return JSON. If not, run `docker-compose logs reactions mood`.
6. **"Table 'buzzboard.users' doesn't exist"** on Sign in/Sign up: the reactions service starts before MySQL is ready. Rebuild and restart so it can create the tables: `docker-compose build --no-cache reactions mood && docker-compose up -d`. The backend now waits for MySQL at startup and creates `users` and `reactions` (and mood creates `mood_votes`).

## Deploy to Kubernetes

**Before applying manifests:** Install the NGINX Ingress Controller and add **buzzboard.local** to your hosts file (required by [k8s/namespace-1-frontend/ingress.yaml](k8s/namespace-1-frontend/ingress.yaml)). See **[k8s/README.md](k8s/README.md)** for full Ingress install steps.

**Add buzzboard.local to hosts**

- **macOS/Linux:** `sudo nano /etc/hosts` → add `INGRESS_IP   buzzboard.local`
- **Windows:** Edit `C:\Windows\System32\drivers\etc\hosts` as Administrator, same line.

### 1. Build images (required for local clusters)

The deployments use `frontend:latest`, `reactions:latest`, `mood:latest`. The cluster must have these images or you get **ImagePullBackOff** and 503.

**Minikube** (build inside minikube’s Docker):
```bash
eval $(minikube docker-env)
docker build -t frontend:latest ./frontend
docker build -t reactions:latest ./backend/reactions
docker build -t mood:latest ./backend/mood
```

**OrbStack / Docker Desktop K8s** (cluster often uses host Docker):
```bash
docker build -t frontend:latest ./frontend
docker build -t reactions:latest ./backend/reactions
docker build -t mood:latest ./backend/mood
``

**kind:** after building, load into the cluster: `kind load docker-image frontend:latest` (and same for reactions, mood).

**Remote cluster:** push images to a registry and set `image:` in the Deployment YAMLs to the full image URL.

### 2. StorageClass

Ensure the **data** namespace has a StorageClass with `reclaimPolicy: Retain`. Edit `k8s/namespace-3-data/storageclass.yaml` and set `provisioner` to your cluster’s default (e.g. `rancher.io/local-path`, `k8s.io/minikube-hostpath`). Get it with:

```bash
kubectl get sc -o jsonpath='{.items[0].provisioner}'
```

### 3. Apply manifests in order

```bash
# Namespaces
kubectl apply -f k8s/namespace-1-frontend/namespace.yaml
kubectl apply -f k8s/namespace-2-backend/namespace.yaml
kubectl apply -f k8s/namespace-3-data/namespace.yaml

# Data layer (StorageClass, then Redis + MySQL)
kubectl apply -f k8s/namespace-3-data/storageclass.yaml
kubectl apply -f k8s/namespace-3-data/redis-configmap.yaml
kubectl apply -f k8s/namespace-3-data/redis-secret.yaml
kubectl apply -f k8s/namespace-3-data/redis-statefulset.yaml
kubectl apply -f k8s/namespace-3-data/redis-networkpolicy.yaml
kubectl apply -f k8s/namespace-3-data/mysql-configmap.yaml
kubectl apply -f k8s/namespace-3-data/mysql-secret.yaml
kubectl apply -f k8s/namespace-3-data/mysql-statefulset.yaml
kubectl apply -f k8s/namespace-3-data/mysql-networkpolicy.yaml

# Backend (2 microservices)
kubectl apply -f k8s/namespace-2-backend/reactions-configmap.yaml
kubectl apply -f k8s/namespace-2-backend/reactions-secret.yaml
kubectl apply -f k8s/namespace-2-backend/reactions-deployment.yaml
kubectl apply -f k8s/namespace-2-backend/mood-configmap.yaml
kubectl apply -f k8s/namespace-2-backend/mood-secret.yaml
kubectl apply -f k8s/namespace-2-backend/mood-deployment.yaml
kubectl apply -f k8s/namespace-2-backend/backend-networkpolicy.yaml
kubectl apply -f k8s/namespace-2-backend/backend-hpa.yaml

# Frontend + Ingress (frontend-deployment.yaml includes the config-js ConfigMap)
kubectl apply -f k8s/namespace-1-frontend/frontend-configmap.yaml
kubectl apply -f k8s/namespace-1-frontend/frontend-secret.yaml
kubectl apply -f k8s/namespace-1-frontend/frontend-deployment.yaml
kubectl apply -f k8s/namespace-1-frontend/frontend-service.yaml
kubectl apply -f k8s/namespace-1-frontend/frontend-networkpolicy.yaml
```

The frontend Deployment references a ConfigMap `frontend-config-js` for the mounted `config.js`; that is defined inside `frontend-deployment.yaml`. No separate `frontend-config-js.yaml` is required unless you split it.

### 4. TLS secret and Ingress

See **k8s/ssl/README.md** for creating the TLS cert. Create the secret in both namespaces (backend Ingress needs it for TLS), then apply both Ingresses:

```bash
kubectl create secret tls ingress-tls --cert=tls.crt --key=tls.key -n frontend
kubectl create secret tls ingress-tls --cert=tls.crt --key=tls.key -n backend
kubectl apply -f k8s/namespace-1-frontend/ingress.yaml
kubectl apply -f k8s/namespace-2-backend/ingress.yaml
```

Ensure **buzzboard.local** is in your hosts file (see **k8s/README.md**). Open **https://buzzboard.local** and accept the self-signed cert. You get the same app as Docker Compose (**Ashour Chat Tutorial**): **Sign up** → **Sign in** → use Reaction Wall and Mood of the Day (by Kubernetes). To verify MySQL data persists across restarts, see **Testing PVC retain (MySQL)** below.

**Clean and re-deploy (Kubernetes):** Remove all deployments and resources in the three namespaces; then apply again and recreate TLS + Ingress:

```bash
# From project root — delete namespaces (removes all resources inside them)
kubectl delete namespace frontend backend data --ignore-not-found --timeout=120s

# Re-create namespaces and apply everything in order (see "Apply manifests in order" above)
kubectl apply -f k8s/namespace-1-frontend/namespace.yaml
kubectl apply -f k8s/namespace-2-backend/namespace.yaml
kubectl apply -f k8s/namespace-3-data/namespace.yaml
kubectl apply -f k8s/namespace-3-data/storageclass.yaml
kubectl apply -f k8s/namespace-3-data/redis-configmap.yaml
kubectl apply -f k8s/namespace-3-data/redis-secret.yaml
kubectl apply -f k8s/namespace-3-data/redis-statefulset.yaml
kubectl apply -f k8s/namespace-3-data/redis-networkpolicy.yaml
kubectl apply -f k8s/namespace-3-data/mysql-configmap.yaml
kubectl apply -f k8s/namespace-3-data/mysql-secret.yaml
kubectl apply -f k8s/namespace-3-data/mysql-statefulset.yaml
kubectl apply -f k8s/namespace-3-data/mysql-networkpolicy.yaml
kubectl apply -f k8s/namespace-2-backend/reactions-configmap.yaml
kubectl apply -f k8s/namespace-2-backend/reactions-secret.yaml
kubectl apply -f k8s/namespace-2-backend/reactions-deployment.yaml
kubectl apply -f k8s/namespace-2-backend/mood-configmap.yaml
kubectl apply -f k8s/namespace-2-backend/mood-secret.yaml
kubectl apply -f k8s/namespace-2-backend/mood-deployment.yaml
kubectl apply -f k8s/namespace-2-backend/backend-networkpolicy.yaml
kubectl apply -f k8s/namespace-2-backend/backend-hpa.yaml
kubectl apply -f k8s/namespace-1-frontend/frontend-configmap.yaml
kubectl apply -f k8s/namespace-1-frontend/frontend-secret.yaml
kubectl apply -f k8s/namespace-1-frontend/frontend-deployment.yaml
kubectl apply -f k8s/namespace-1-frontend/frontend-service.yaml
kubectl apply -f k8s/namespace-1-frontend/frontend-networkpolicy.yaml

# Re-create TLS secret and Ingress (use your tls.crt and tls.key)
kubectl create secret tls ingress-tls --cert=tls.crt --key=tls.key -n frontend
kubectl create secret tls ingress-tls --cert=tls.crt --key=tls.key -n backend
kubectl apply -f k8s/namespace-1-frontend/ingress.yaml
kubectl apply -f k8s/namespace-2-backend/ingress.yaml
```

**Before re-applying:** Build images again if using a local cluster (see "Build images" above). Then open **https://buzzboard.local**.

## Testing HPA (reactions)

The **reactions** deployment has an HPA (min 1, max 5 replicas, target 70% CPU). To see it scale:
**1. Ensure metrics-server is running** (required for CPU-based HPA):

```bash
kubectl top nodes
kubectl top pod -n backend -l app=reactions
```
If node metrics work but pod metrics show "Metrics not available", wait 1–2 min or restart the metrics-server pod. The HPA only needs metrics for **reactions** pods.

If that fails, install metrics-server:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

If the metrics-server pod is **CrashLoopBackOff** with log: `error creating self-signed certificates: mkdir apiserver.local.config: read-only file system`, the container needs a writable cert directory. The safest fix is to **edit** the deployment so args and volumes are set in one place (patch can conflict if args already exist):

```bash
kubectl edit deployment metrics-server -n kube-system
```

In the editor, find the `metrics-server` container and set:

- **args** (replace any existing or add new):
  ```yaml
  args:
    - --cert-dir=/tmp/certs
    - --kubelet-insecure-tls
    - --kubelet-preferred-address-types=InternalIP
  ```
- **volumeMounts** (add if not present):
  ```yaml
  volumeMounts:
    - name: tmp
      mountPath: /tmp
  ```
- Under **spec.template.spec**, add **volumes** (if not present):
  ```yaml
  volumes:
    - name: tmp
      emptyDir: {}
  ```

Save and exit. Ensure **replicas: 1**. List pods (label can vary; grep by name): `kubectl get pods -n kube-system | grep metrics`. Wait for the single pod to be **Running**; then try `kubectl top nodes` and `kubectl top pod -n backend -l app=reactions`. If the new pod still crashes, check logs: `kubectl logs -n kube-system deployment/metrics-server --tail=50`.

**OrbStack / K3s: "Metrics not available" for pods:** On some OrbStack or K3s clusters, the kubelet’s summary API returns **node** metrics but an **empty list of pod metrics**. Then `kubectl top nodes` works but `kubectl top pods` always shows "Metrics not available" (and HPA cannot scale on CPU). This comes from the runtime (kubelet/CRI) not exposing per-container stats, not from metrics-server. Workarounds: (1) Use **node** metrics only: `kubectl top nodes`. (2) Use another cluster (e.g. Minikube, GKE, EKS) if you need pod metrics and CPU-based HPA. (3) On OrbStack, ensure you’re on a recent version; some versions add better metrics support.

**2. In one terminal, watch the HPA and pods:**

```bash
kubectl get hpa -n backend -w
```

In another terminal:

```bash
kubectl get pods -n backend -w
```

**3. Generate load on the reactions service.** From your machine (replace with your Ingress host or use port-forward):

```bash
# Port-forward so we can hit reactions from the host
kubectl port-forward -n backend svc/reactions-svc 8080:8080 &
# Then run many requests in a loop (stop with Ctrl+C when replicas have increased)
while true; do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/reactions; done
```

Or use a load tool (e.g. `hey`: `hey -z 60s -c 20 http://localhost:8080/reactions`). Alternatively, use the app at https://buzzboard.local (Sign in, then hit Reaction Wall repeatedly — post messages, refresh).

**4. Observe:** After a minute or two, `kubectl get hpa -n backend` should show increased CPU and the HPA raising desired replicas; `kubectl get pods -n backend` should show more `reactions-*` pods. When you stop the load, the HPA will scale back down toward 1.

## Monitoring (Prometheus + Grafana)

Prometheus and Grafana can be installed in the cluster to monitor running pods (including ashour-chat). The stack scrapes pod and container metrics (CPU, memory, network) via the kubelet.

### Install the stack

From the project root:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f monitoring/prometheus-stack-values.yaml
```

This installs Prometheus, Grafana, and node-exporter in the `monitoring` namespace. Alertmanager is disabled in the provided values to reduce resource usage.

For Ingress (optional), the values file configures:
- **Prometheus:** `https://prometheus.buzzboard.local`
- **Grafana:** `https://grafana.buzzboard.local`

Create the TLS secret in `monitoring` so the Ingress can serve HTTPS:

```bash
kubectl create secret tls ingress-tls --cert=tls.crt --key=tls.key -n monitoring
```

Add the monitoring hostnames to your hosts file (same IP as `buzzboard.local`). For example, if `buzzboard.local` is `192.168.139.2`:

- **macOS/Linux:** `sudo nano /etc/hosts` and add (or append to the existing buzzboard.local line):
  ```
  192.168.139.2  prometheus.buzzboard.local grafana.buzzboard.local
  ```
- Or add a separate line: `INGRESS_IP   prometheus.buzzboard.local` and `INGRESS_IP   grafana.buzzboard.local`.

### Access Prometheus and confirm pod scraping

**Port-forward (no Ingress):**

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```

Open **http://localhost:9090/targets**. You should see targets for **kubernetes-nodes**, **kubernetes-pods** / **kubernetes-cadvisor**, etc. Pods in `ashour-chat` (and other namespaces) are discovered and scraped by default.

**Example queries** in the Prometheus query UI (http://localhost:9090/graph) for ashour-chat pods:

- `container_cpu_usage_seconds_total{namespace="ashour-chat"}`
- `container_memory_working_set_bytes{namespace="ashour-chat"}`

If you use Ingress, open **https://prometheus.buzzboard.local** instead.

### Access Grafana

**Port-forward:**

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

Open **http://localhost:3000**. Default user is `admin`; get the password:

```bash
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo
```

Grafana comes with preloaded dashboards. Use **Dashboards → Browse** and open e.g. **Kubernetes / Compute Resources / Pods** to see pod CPU/memory by namespace (including `ashour-chat`).

If you use Ingress, open **https://grafana.buzzboard.local**. If you get **503 Service Unavailable**, Grafana may be redirecting to the wrong URL; the values file sets `root_url` to fix this. Re-apply the stack: `helm upgrade prometheus prometheus-community/kube-prometheus-stack -n monitoring -f monitoring/prometheus-stack-values.yaml`, wait for the Grafana pod to restart, then try again. As a workaround, use port-forward above.

### No data in Grafana namespace/pod dashboards (CPU/Memory utilisation)

The **Kubernetes / Compute Resources / Namespace (Pods)** dashboard shows **CPU Quota** (requests/limits from the API) but **No data** for CPU/Memory **utilisation** because those come from **cAdvisor** (kubelet), not from a separate "pod exporter". The stack is already set up to scrape the kubelet:

- **ServiceMonitor** `prometheus-kube-prometheus-kubelet` in `monitoring` scrapes `/metrics/cadvisor` from the kubelet (in `kube-system`).
- **Endpoints** `prometheus-kube-prometheus-kubelet` in `kube-system` point at the node’s kubelet (e.g. `https-metrics` port 10250).

**Check in Prometheus:**

1. Port-forward: `kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090`
2. Open **http://localhost:9090/targets** and find the job for the kubelet (e.g. **kubelet** or **kubernetes-nodes-cadvisor**). If it is **DOWN**, Prometheus is not getting container metrics (common on **K3s/OrbStack** where the kubelet may not expose cAdvisor the same way; see the README note on "Metrics not available" for metrics-server).
3. If the target is **UP**, open **http://localhost:9090/graph** and run:  
   `container_memory_working_set_bytes{namespace="backend", container!=""}`  
   If that returns data, the dashboard may be using different labels or job names; use **Explore** in Grafana with that query.

**Summary:** There is no separate "pod exporter"; pod usage comes from the kubelet. If the kubelet/cAdvisor target is DOWN, fix that scrape (or accept the platform limitation); if it is UP, use the query above in Grafana or adjust the dashboard.

## Secrets with Vault

You can use **HashiCorp Vault** as the source of truth for app secrets (Redis, MySQL, JWT). The **External Secrets Operator (ESO)** syncs them into the same Kubernetes Secrets the app already uses, so no pod or app code changes are required.

**Prerequisites:** A running Kubernetes cluster, `kubectl`, `helm`, and (for bootstrap) the Vault CLI.

### Install order

1. **Install Vault** (Helm) in the `vault` namespace.
2. **Unseal** Vault (if not using dev mode) and run **bootstrap** (KV v2, Kubernetes auth, policy, role, seed secrets).
3. **Install External Secrets Operator** in the `external-secrets` namespace.
4. **Install or upgrade** the ashour-chat chart with `vault.enabled=true`.

### 1. Install Vault

From the project root:

```bash
kubectl create namespace vault
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm install vault hashicorp/vault -n vault -f vault/helm-values.yaml
```

Wait for the Vault pod to be ready: `kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=120s`.

**Standalone (default)**: Vault starts sealed. Initialize and unseal (see [Vault docs](https://developer.hashicorp.com/vault/docs/concepts/seal#unseal)):

```bash
kubectl exec -n vault vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > vault-keys.json
# Save the unseal key and root token from vault-keys.json, then:
kubectl exec -n vault vault-0 -- vault operator unseal <UNSEAL_KEY>
export VAULT_TOKEN=<ROOT_TOKEN>
```

**Dev mode (optional, for try-out)**: In `vault/helm-values.yaml`, set `server.dev.enabled: true` and disable `server.standalone`. Dev mode is unsealed by default and has KV v2 at `secret/`; data is in-memory and lost on restart. Get the root token from the Vault pod logs.

### 2. Bootstrap Vault (KV, Kubernetes auth, policy, role, seed)

Ensure Vault is reachable and you have a root (or sufficient) token. From your machine with the Vault CLI:

```bash
kubectl port-forward -n vault svc/vault 8200:8200
```

In another terminal:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=<your-root-token>

# Optional: if running from outside the cluster, you may need to pass Kubernetes CA and reviewer JWT for auth:
# export VAULT_KUBE_CA_CERT="$(kubectl get secret -n vault vault-server-tls -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d)"  # or cluster CA
# export VAULT_KUBE_REVIEWER_JWT="$(kubectl create token -n vault default --duration=86400)"

chmod +x vault/bootstrap.sh
./vault/bootstrap.sh
```

The script enables KV v2 at `secret`, configures Kubernetes auth, creates policy `ashour-chat-read` and role `ashour-chat-eso` (bound to service account `default` in namespace `ashour-chat`), and seeds `secret/ashour-chat` with keys: `redisPassword`, `mysqlRootPassword`, `mysqlUser`, `mysqlPassword`, `jwtSecret`. Override values with env vars `VAULT_secret_redisPassword`, etc., or edit the script.

### 3. Install External Secrets Operator

```bash
kubectl create namespace external-secrets
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets -n external-secrets -f external-secrets/values.yaml
```

### 4. Install ashour-chat with Vault-backed secrets

Install or upgrade the chart with Vault enabled (and optional overrides):

```bash
helm upgrade --install ashour-chat helm/ashour-chat -n ashour-chat --create-namespace \
  --set vault.enabled=true \
  --set vault.address=http://vault.vault.svc:8200 \
  --set vault.auth.role=ashour-chat-eso \
  --set vault.auth.serviceAccount=default
```

The chart creates a **SecretStore** in the release namespace and four **ExternalSecrets** that sync from Vault into `reactions-secret`, `mood-secret`, `redis-secret`, and `mysql-secret` (same names and keys the pods use).

### Verify

- List ExternalSecrets: `kubectl get externalsecrets -n ashour-chat`
- Check sync status: `kubectl describe externalsecret reactions-secret -n ashour-chat`
- Confirm Secrets exist: `kubectl get secrets -n ashour-chat reactions-secret mood-secret redis-secret mysql-secret`
- Ensure pods start and can reach Redis/MySQL (same as without Vault).

### Vault path and keys

Secrets are read from path **`secret/ashour-chat`** (KV v2). Required keys:

| Key                | Used by              |
|--------------------|----------------------|
| `redisPassword`    | reactions, mood, redis |
| `mysqlRootPassword`| mysql                |
| `mysqlUser`        | reactions, mood, mysql |
| `mysqlPassword`    | reactions, mood, mysql |
| `jwtSecret`        | reactions, mood      |

Example (one-time seed):  
`vault kv put secret/ashour-chat redisPassword=xxx mysqlRootPassword=xxx mysqlUser=buzzboard mysqlPassword=xxx jwtSecret=xxx`

**Production:** Use proper Vault storage (e.g. Raft) and unseal process; see [HashiCorp Vault documentation](https://developer.hashicorp.com/vault/docs).

## Testing PVC retain (MySQL)

To verify data persists across StatefulSet restart:

1. Use the app and add some reactions/mood votes.
2. Delete the MySQL StatefulSet: `kubectl delete statefulset mysql -n data`
3. Re-apply the MySQL StatefulSet manifest. The existing PVC (from `volumeClaimTemplates`) should still exist (Retain) and the new pod should bind to it; data should be intact.

## Project layout

```
frontend/           # Static app (HTML/JS/CSS), nginx, Dockerfile
backend/reactions/  # Reactions microservice (Node/Express), Dockerfile
backend/mood/       # Mood microservice (Node/Express), Dockerfile
k8s/
  namespace-1-frontend/
  namespace-2-backend/
  namespace-3-data/
  ssl/README.md
monitoring/
  prometheus-stack-values.yaml   # Helm values for Prometheus + Grafana stack
vault/
  helm-values.yaml               # Vault Helm values (standalone / dev)
  bootstrap.sh                   # KV v2, Kubernetes auth, policy, role, seed secrets
external-secrets/
  values.yaml                    # External Secrets Operator Helm values
docker-compose.yml
README.md
```

## License

Use for teaching and learning. Adjust branding and secrets for production.
