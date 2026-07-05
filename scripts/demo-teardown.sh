#!/usr/bin/env bash
# scripts/demo-teardown.sh
#
# Tears down the full k8s-go-demo demo environment.
# Uninstalls Helm releases in reverse dependency order,
# stops port-forwards, and optionally stops or deletes minikube.
#
# Usage: ./scripts/demo-teardown.sh [--delete-cluster]
#
#   --delete-cluster   Run 'minikube delete' instead of 'minikube stop'

set -euo pipefail

DELETE_CLUSTER=false
for arg in "$@"; do
  [[ "$arg" == "--delete-cluster" ]] && DELETE_CLUSTER=true
done

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}==>${RESET} $*"; }
success() { echo -e "${GREEN}  ok${RESET}  $*"; }

helm_installed() { helm list -n "$1" --short 2>/dev/null | grep -q "^$2$"; }

# ------------------------------------------------------------------------------
# 1. Port-forwards
# ------------------------------------------------------------------------------

info "Stopping port-forwards..."
pkill -f "kubectl port-forward.*go-demo"        2>/dev/null || true
pkill -f "kubectl port-forward.*grafana"         2>/dev/null || true
pkill -f "kubectl port-forward.*prometheus[^-]"  2>/dev/null || true
pkill -f "kubectl port-forward.*tempo"           2>/dev/null || true
success "port-forwards stopped"

# ------------------------------------------------------------------------------
# 2. Helm uninstalls (reverse dependency order)
# ------------------------------------------------------------------------------

info "Uninstalling Helm releases..."

uninstall() {
  local release=$1 namespace=$2
  if helm_installed "$namespace" "$release"; then
    helm uninstall "$release" -n "$namespace"
    success "uninstalled $release"
  else
    success "$release not installed -- skipping"
  fi
}

uninstall go-demo               demo
uninstall otel-collector        monitoring
uninstall tempo                 monitoring
uninstall kube-prometheus-stack monitoring

# ------------------------------------------------------------------------------
# 3. Namespaces (optional cleanup)
# ------------------------------------------------------------------------------

info "Removing namespaces..."
for ns in demo monitoring; do
  if kubectl get namespace "$ns" &>/dev/null; then
    kubectl delete namespace "$ns"
    success "deleted namespace $ns"
  else
    success "namespace $ns already gone"
  fi
done

# ------------------------------------------------------------------------------
# 4. Minikube
# ------------------------------------------------------------------------------

if [[ "$DELETE_CLUSTER" == "true" ]]; then
  info "Deleting minikube cluster..."
  minikube delete
  success "cluster deleted"
else
  info "Stopping minikube (run with --delete-cluster to wipe entirely)..."
  minikube stop
  success "minikube stopped"
fi

# ------------------------------------------------------------------------------
# 5. Summary
# ------------------------------------------------------------------------------

echo ""
echo -e "${BOLD}Teardown complete.${RESET}"
echo ""
if [[ "$DELETE_CLUSTER" == "false" ]]; then
  echo "  Restart the demo anytime with:"
  echo "    ./scripts/demo-setup.sh"
  echo ""
fi
