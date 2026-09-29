# EKS GitOps Platform

> Production-ready Kubernetes platform on AWS EKS — GitOps with ArgoCD, full observability with Prometheus/Grafana, and a reusable Helm chart for application deployments.

[![Terraform](https://img.shields.io/badge/Terraform-1.8+-7B42BC?style=flat-square&logo=terraform&logoColor=white)](https://terraform.io)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.31-326CE5?style=flat-square&logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-2.12-orange?style=flat-square)](https://argo-cd.readthedocs.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## What this is

A complete GitOps platform you can fork and run. One `terraform apply` provisions the EKS cluster with all required AWS integrations. One `kubectl apply` bootstraps ArgoCD, which then self-manages and deploys every platform component — cert-manager, Prometheus stack, External Secrets Operator, and the AWS Load Balancer Controller — using the **App-of-Apps** pattern.

Application teams get a reusable Helm chart with sane defaults: HPA, PodDisruptionBudget, IRSA-ready ServiceAccount, Ingress with TLS, and resource limits baked in.

---

## Platform Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                         AWS Account                                  │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                        EKS Cluster                          │    │
│  │                                                             │    │
│  │  ┌──────────────┐   App-of-Apps   ┌─────────────────────┐ │    │
│  │  │    ArgoCD    │ ──────────────▶ │  Platform Apps       │ │    │
│  │  │  (GitOps)    │                 │  - cert-manager       │ │    │
│  │  └──────────────┘                 │  - aws-lb-controller  │ │    │
│  │         │                         │  - prometheus-stack   │ │    │
│  │         │                         │  - external-secrets   │ │    │
│  │         ▼                         └─────────────────────┘ │    │
│  │  ┌──────────────┐                                          │    │
│  │  │  App deploys │  ◀── GitHub Actions (image tag PR)       │    │
│  │  │  (Helm chart)│                                          │    │
│  │  └──────────────┘                                          │    │
│  │                                                             │    │
│  │  Node Groups:  system (t3.medium ×2)  app (t3.large ×2-10)│    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌──────────┐  ┌────────────────┐  ┌───────────────────────────┐   │
│  │   ECR    │  │ Secrets Manager│  │  IAM (IRSA per workload)  │   │
│  └──────────┘  └────────────────┘  └───────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

| Component | Version | Purpose |
|-----------|---------|---------|
| EKS | 1.31 | Managed Kubernetes |
| ArgoCD | 2.12 | GitOps continuous delivery |
| cert-manager | 1.16 | Automatic TLS via Let's Encrypt |
| AWS Load Balancer Controller | 2.9 | Ingress → ALB provisioning |
| kube-prometheus-stack | 65.x | Prometheus + Grafana + Alertmanager |
| External Secrets Operator | 0.10 | Sync AWS Secrets Manager → K8s secrets |
| Cluster Autoscaler | 1.31 | Node group auto-scaling |

---

## Getting Started

### 1. Provision the cluster

```bash
cd terraform

# Create S3 backend + DynamoDB lock table first (one-time)
./scripts/bootstrap-backend.sh

terraform init
terraform plan -var-file=environments/production.tfvars
terraform apply -var-file=environments/production.tfvars

# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name eks-gitops-production
```

### 2. Bootstrap ArgoCD

```bash
cd bootstrap
./argocd/install.sh
```

This installs ArgoCD and applies the root `app-of-apps.yml`, which tells ArgoCD to manage itself and all platform components from this repo. Everything after this point is GitOps — push to `main`, ArgoCD syncs.

### 3. Access Grafana

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
# Default credentials in Secrets Manager: /eks-gitops/grafana/admin-password
```

---

## Deploying an Application

Use the shared `helm/app` chart. Add an ArgoCD Application in `argocd/apps/`:

```yaml
# argocd/apps/my-service.yml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-service
  namespace: argocd
spec:
  project: apps
  source:
    repoURL: https://github.com/sgonzalez-devv/eks-gitops-platform
    targetRevision: HEAD
    path: helm/app
    helm:
      valueFiles:
        - values/my-service/production.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: my-service
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

---

## GitOps Workflow

```
Developer pushes to app repo
        │
        ▼
GitHub Actions CI (test + build + push to ECR)
        │
        ▼
GitHub Actions calls this repo's workflow_dispatch:
"update-image" (bumps image tag in values file)
        │
        ▼
PR opened against main (reviewable, auditable)
        │
        ▼
Merge → ArgoCD detects diff → rolling deploy
```

No `kubectl apply` in CI. The only path to production is through Git.

---

## Helm Chart Features

The shared `helm/app` chart ships with:

| Feature | Default | Notes |
|---------|---------|-------|
| HPA | min 2, max 10 | CPU 70% target |
| PodDisruptionBudget | minAvailable: 1 | Prevents full outage during node drain |
| Resource limits | 256m CPU / 256Mi RAM | Override per app |
| IRSA ServiceAccount | Enabled | Annotate with role ARN per app |
| Ingress + TLS | cert-manager ClusterIssuer | Automatic Let's Encrypt |
| Liveness / Readiness | `/health` on container port | Configurable |
| topologySpreadConstraints | zone spread | Prevents all pods on one AZ |

---

## Observability

Prometheus scrapes all workloads via `ServiceMonitor`. Grafana dashboards (in `monitoring/dashboards/`) cover:

- **Platform overview** — node CPU/memory, pod counts, API server latency
- **Application overview** — request rate, error rate, p50/p95 latency (RED metrics)
- **ArgoCD** — sync status, out-of-sync apps

Alertmanager rules (in `monitoring/alerts/`) fire on:
- PodCrashLooping
- HighErrorRate (>1% 5xx for 5 minutes)
- NodeMemoryPressure
- PVCNearlyFull
- ArgoCD app out-of-sync for >10 minutes

---

## Security

- **IRSA** — every workload gets its own IAM role, no shared credentials
- **Network Policies** — default-deny in every namespace, explicit allow rules required
- **External Secrets** — no secrets in Git, all synced from AWS Secrets Manager
- **Pod Security Standards** — `restricted` profile enforced at namespace level
- **Node IAM** — minimal permissions, no `eks:*` on node role

---

## Repository Structure

```
eks-gitops-platform/
├── terraform/              # EKS cluster + VPC + IRSA
├── bootstrap/
│   └── argocd/             # One-time ArgoCD install + root app
├── argocd/
│   ├── platform/           # Platform component Applications
│   └── apps/               # Workload Applications
├── helm/
│   └── app/                # Shared application Helm chart
│       ├── templates/
│       │   ├── deployment.yaml
│       │   ├── hpa.yaml
│       │   ├── pdb.yaml
│       │   ├── ingress.yaml
│       │   └── servicemonitor.yaml
│       └── values/         # Per-app value overrides
├── monitoring/
│   ├── dashboards/         # Grafana dashboard JSON
│   └── alerts/             # PrometheusRule manifests
├── policies/
│   └── network/            # NetworkPolicy manifests
└── .github/
    └── workflows/
        └── update-image.yml  # GitOps image tag updater
```

---

## License

MIT
