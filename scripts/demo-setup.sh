#!/usr/bin/env bash
# scripts/demo-setup.sh
#
# Brings up the full k8s-go-demo environment for a live demo.
# Safe to re-run -- skips any step that is already complete.
#
# Usage: ./scripts/demo-setup.sh

set -euo pipefail

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
die()     { echo -e "${RED}error:${RESET} $*" >&2; exit 1; }

helm_installed() { helm list -n "$1" --short 2>/dev/null | grep -q "^$2$"; }

# ------------------------------------------------------------------------------
# 1. Preflight checks
# ------------------------------------------------------------------------------

info "Checking required tools..."
for cmd in minikube kubectl helm docker; do
  command -v "$cmd" &>/dev/null || die "'$cmd' not found -- install it and re-run"
  success "$cmd"
done

# ------------------------------------------------------------------------------
# 2. Minikube
# ------------------------------------------------------------------------------

info "Checking minikube..."
if minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
  success "minikube already running"
else
  info "Starting minikube..."
  minikube start --driver=docker --cpus=4 --memory=8192
  success "minikube started"
fi

# ------------------------------------------------------------------------------
# 3. Helm repos
# ------------------------------------------------------------------------------

info "Adding Helm repos (skipping any already present)..."

add_repo() {
  local name=$1 url=$2
  if helm repo list 2>/dev/null | grep -q "^${name}[[:space:]]"; then
    success "repo '${name}' already added"
  else
    helm repo add "$name" "$url"
    success "added repo '${name}'"
  fi
}

add_repo prometheus-community https://prometheus-community.github.io/helm-charts
add_repo grafana              https://grafana.github.io/helm-charts
add_repo open-telemetry       https://open-telemetry.github.io/opentelemetry-helm-charts

info "Updating Helm repos..."
helm repo update >/dev/null
success "repos up to date"

# ------------------------------------------------------------------------------
# 4. Monitoring stack
# ------------------------------------------------------------------------------

info "Checking kube-prometheus-stack..."
if helm_installed monitoring kube-prometheus-stack; then
  success "kube-prometheus-stack already deployed"
else
  info "Installing kube-prometheus-stack..."
  helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring --create-namespace \
    -f monitoring/kube-prometheus-stack-values.yaml
  success "kube-prometheus-stack installed"
fi

info "Checking Tempo..."
if helm_installed monitoring tempo; then
  success "tempo already deployed"
else
  info "Installing Tempo..."
  helm install tempo grafana/tempo \
    --namespace monitoring --create-namespace \
    -f monitoring/tempo-values.yaml
  success "tempo installed"
fi

info "Checking OTel Collector..."
if helm_installed monitoring otel-collector; then
  success "otel-collector already deployed"
else
  info "Installing OTel Collector..."
  helm install otel-collector open-telemetry/opentelemetry-collector \
    --namespace monitoring --create-namespace \
    -f monitoring/otel-collector-values.yaml
  success "otel-collector installed"
fi

# ------------------------------------------------------------------------------
# 5. Docker image
# ------------------------------------------------------------------------------

info "Building Docker image..."
docker build -q -t k8s-go-demo:local .
success "image built"

info "Loading image into minikube..."
# Scale to 0 first to release any reference to the old image under this tag.
# minikube image load is a no-op if a running container holds the tag.
if kubectl get deployment go-demo -n demo &>/dev/null; then
  kubectl scale deployment go-demo -n demo --replicas=0 &>/dev/null
  kubectl rollout status deployment/go-demo -n demo --timeout=30s &>/dev/null || true
fi
minikube image rm k8s-go-demo:local &>/dev/null || true
minikube image load k8s-go-demo:local
success "image loaded"

# ------------------------------------------------------------------------------
# 6. go-demo
# ------------------------------------------------------------------------------

info "Checking go-demo..."
if helm_installed demo go-demo; then
  info "go-demo already deployed -- upgrading to pick up new image..."
  helm upgrade go-demo charts/go-demo --namespace demo
  success "go-demo upgraded"
else
  info "Installing go-demo..."
  helm install go-demo charts/go-demo --namespace demo --create-namespace
  success "go-demo installed"
fi

# ------------------------------------------------------------------------------
# 7. Wait for pods
# ------------------------------------------------------------------------------

info "Waiting for all pods to be ready..."

kubectl rollout status deployment/go-demo \
  -n demo --timeout=120s
success "go-demo ready"

kubectl rollout status deployment/kube-prometheus-stack-grafana \
  -n monitoring --timeout=180s
success "grafana ready"

kubectl rollout status statefulset/prometheus-kube-prometheus-stack-prometheus \
  -n monitoring --timeout=180s
success "prometheus ready"

kubectl rollout status statefulset/tempo \
  -n monitoring --timeout=120s
success "tempo ready"

kubectl rollout status deployment/otel-collector \
  -n monitoring --timeout=60s
success "otel-collector ready"

# Scale go-demo back up if we scaled it down
kubectl scale deployment go-demo -n demo --replicas=1 &>/dev/null || true

# ------------------------------------------------------------------------------
# 8. Port-forwards
# ------------------------------------------------------------------------------

info "Stopping any existing port-forwards..."
pkill -f "kubectl port-forward.*go-demo"         2>/dev/null || true
pkill -f "kubectl port-forward.*grafana"          2>/dev/null || true
pkill -f "kubectl port-forward.*prometheus[^-]"   2>/dev/null || true
pkill -f "kubectl port-forward.*tempo"            2>/dev/null || true
sleep 1

info "Starting port-forwards..."
kubectl port-forward svc/go-demo 8080:8080 -n demo \
  &>/dev/null &
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring \
  &>/dev/null &
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring \
  &>/dev/null &
kubectl port-forward svc/tempo 3200:3200 -n monitoring \
  &>/dev/null &
success "port-forwards running in background"

# ------------------------------------------------------------------------------
# 9. Summary
# ------------------------------------------------------------------------------

echo ""
echo -e "${BOLD}Demo environment ready.${RESET}"
echo ""
echo "  Service       URL                       Credentials"
echo "  -----------   ------------------------  -----------"
echo "  go-demo       http://localhost:8080      -"
echo "  Prometheus    http://localhost:9090      -"
echo "  Grafana       http://localhost:3000      admin / admin"
echo "  Tempo         http://localhost:3200      -"
echo ""
echo "  Quick smoke test:"
echo "    curl http://localhost:8080/health"
echo ""
echo "  Stop port-forwards when done:"
echo "    pkill -f 'kubectl port-forward'"
echo ""
