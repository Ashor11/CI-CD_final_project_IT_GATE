# ashour-chat Helm Chart

Deploys the Ashour Chat app in **one namespace**: frontend, reactions, mood, Redis, and MySQL, with a single Ingress.

## Prerequisites

- Kubernetes cluster (minikube, k3d, kind, or any cluster)
- Ingress controller (e.g. NGINX Ingress)
- `kubectl` and Helm 3.x

For HTTPS: create a TLS secret in the same namespace where you install the chart (see below).

## Install (quick start)

From the chart directory:

```bash
cd helm/ashour-chat

# Install into namespace ashour-chat (all resources go there)
helm install ashour-chat . -n ashour-chat --create-namespace
```

Use your own images (full name:tag):

```bash
helm install ashour-chat . -n ashour-chat --create-namespace \
  --set frontendImage=ashour11/ashour-chat-frontend:2 \
  --set reactionsImage=ashour11/ashour-chat-reactions:2 \
  --set moodImage=ashour11/ashour-chat-mood:2
```

## Optional: TLS

If you have `tls.crt` and `tls.key`, create the secret **before** or **after** install (chart expects secret name `ingress-tls`):

```bash
kubectl create secret tls ingress-tls --cert=tls.crt --key=tls.key -n ashour-chat
```

If you don’t create it, set `ingress.tls.enabled: false` or ignore TLS until you need it.

## Upgrade

```bash
helm upgrade ashour-chat . -n ashour-chat --set frontendImage=... --set reactionsImage=... --set moodImage=...
```

## Uninstall

```bash
helm uninstall ashour-chat -n ashour-chat
# Optionally remove the namespace and PVCs:
# kubectl delete namespace ashour-chat
# kubectl delete pvc -n ashour-chat -l app=mysql   # if you want to wipe MySQL data
```

## Main values

| Key | Description | Default |
|-----|-------------|--------|
| `frontendImage` | Full frontend image (name:tag) | `frontend:latest` |
| `reactionsImage` | Full reactions image (name:tag) | `reactions:latest` |
| `moodImage` | Full mood image (name:tag) | `mood:latest` |
| `ingress.enabled` | Create Ingress | `true` |
| `ingress.host` | Hostname | `buzzboard.local` |
| `ingress.tls.enabled` | Use TLS (requires secret `ingress-tls`) | `true` |
| `networkPolicies.enabled` | Create NetworkPolicies (advanced) | `false` |
| `storageClass.enabled` | Create a custom StorageClass (for local clusters) | `false` |
| `reactions.hpa.enabled` | Enable HPA for reactions | `false` |

Full list: see `values.yaml`.

## Pipeline (k8s-helm)

The Azure pipeline runs:

```bash
helm upgrade --install ashour-chat <chart-path> -n frontend --create-namespace \
  --set frontendImage=$(DOCKERHUB_IMAGE_PREFIX)-frontend:$(effectiveTag) \
  --set reactionsImage=$(DOCKERHUB_IMAGE_PREFIX)-reactions:$(effectiveTag) \
  --set moodImage=$(DOCKERHUB_IMAGE_PREFIX)-mood:$(effectiveTag) \
  --set storageClass.enabled=false
```

Use the same namespace in pipeline and docs (e.g. `frontend` or `ashour-chat`) and create the TLS secret there if you use TLS.
