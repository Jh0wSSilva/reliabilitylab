#!/usr/bin/env bash
# =============================================================================
# ReliabilityLab — Deploy da Stack de Observabilidade
# Instala Prometheus, Grafana, Loki, Promtail e OpenTelemetry Collector
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================"
echo "  Instalando Stack de Observabilidade"
echo "============================================"
echo ""

# --- Adicionar repositórios Helm ---
echo "[INFO] Adicionando repositórios Helm..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
helm repo update

# --- Prometheus + Grafana (kube-prometheus-stack) ---
echo ""
echo "[INFO] Instalando kube-prometheus-stack (Prometheus + Grafana)..."
helm upgrade --install kube-prometheus-stack \
    prometheus-community/kube-prometheus-stack \
    -n monitoring --create-namespace \
    -f "$PROJECT_DIR/observability/prometheus/values.yaml" \
    --wait --timeout 5m
echo "[OK]   kube-prometheus-stack instalado."

# --- Loki ---
echo ""
echo "[INFO] Instalando Loki..."
helm upgrade --install loki grafana/loki \
    -n monitoring \
    -f "$PROJECT_DIR/observability/loki/values.yaml" \
    --wait --timeout 5m
echo "[OK]   Loki instalado."

# --- Promtail ---
echo ""
echo "[INFO] Instalando Promtail..."
helm upgrade --install promtail grafana/promtail \
    -n monitoring \
    -f "$PROJECT_DIR/observability/loki/promtail-values.yaml" \
    --wait --timeout 3m
echo "[OK]   Promtail instalado."

# --- OpenTelemetry Collector ---
echo ""
echo "[INFO] Instalando OpenTelemetry Collector..."
helm upgrade --install otel-collector \
    open-telemetry/opentelemetry-collector \
    -n monitoring \
    -f "$PROJECT_DIR/observability/otel/values.yaml" \
    --wait --timeout 3m
echo "[OK]   OpenTelemetry Collector instalado."

# --- ServiceMonitor ---
echo ""
echo "[INFO] Aplicando ServiceMonitor..."
kubectl apply -f "$PROJECT_DIR/observability/prometheus/servicemonitor.yaml"
echo "[OK]   ServiceMonitor aplicado."

# --- Dashboard ConfigMap ---
echo ""
echo "[INFO] Aplicando dashboard do Grafana..."
kubectl apply -f "$PROJECT_DIR/observability/grafana/dashboard-configmap.yaml"
echo "[OK]   Dashboard ConfigMap aplicado."

# --- PrometheusRule (Alertas SLO + Application + Infrastructure) ---
echo ""
echo "[INFO] Aplicando regras de alerta do Prometheus..."
kubectl apply -f "$PROJECT_DIR/observability/prometheus/alerts.yaml"
echo "[OK]   PrometheusRule aplicado (12 alertas)."

# --- SLO Dashboard ---
echo ""
echo "[INFO] Aplicando dashboard SLO do Grafana..."
kubectl apply -f "$PROJECT_DIR/observability/grafana/slo-dashboard-configmap.yaml"
echo "[OK]   SLO Dashboard ConfigMap aplicado."

# --- Alertmanager Config ---
echo ""
echo "[INFO] Aplicando configuração do Alertmanager..."
kubectl apply -f "$PROJECT_DIR/observability/alertmanager/config.yaml"
echo "[OK]   Alertmanager ConfigMap aplicado."

# --- Webhook Logger ---
echo ""
echo "[INFO] Aplicando webhook logger para alertas..."
kubectl apply -f "$PROJECT_DIR/observability/alertmanager/webhook-logger.yaml"
echo "[OK]   Webhook Logger aplicado."

echo ""
echo "============================================"
echo "  Stack de Observabilidade instalada!"
echo ""
echo "  Acessar Grafana:"
echo "    kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo "    http://localhost:3000  (admin / admin123)"
echo ""
echo "  Acessar Prometheus:"
echo "    kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
echo "    http://localhost:9090"
echo ""
echo "  Acessar Alertmanager:"
echo "    kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093"
echo "    http://localhost:9093"
echo "============================================"
