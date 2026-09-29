#!/usr/bin/env bash
set -euo pipefail

ARGOCD_VERSION="v2.12.3"
ARGOCD_NAMESPACE="argocd"
REPO_URL="https://github.com/sgonzalez-devv/eks-gitops-platform"

echo "→ Creating argocd namespace"
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "→ Installing ArgoCD ${ARGOCD_VERSION}"
kubectl apply -n "$ARGOCD_NAMESPACE" \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "→ Waiting for ArgoCD server to be ready"
kubectl rollout status deploy/argocd-server -n "$ARGOCD_NAMESPACE" --timeout=120s

echo "→ Applying App-of-Apps root application"
kubectl apply -f "$(dirname "$0")/../../argocd/app-of-apps.yml"

echo "→ Retrieving initial admin password"
echo ""
echo "ArgoCD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""
echo "→ Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Then open https://localhost:8080"
