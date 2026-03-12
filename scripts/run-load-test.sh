#!/usr/bin/env bash
# =============================================================================
# ReliabilityLab — Executar Testes de Carga com k6
# Roda cenários de teste contra a aplicação no cluster
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BASE_URL="${BASE_URL:-http://site-kubectl.local}"

# Verificar se k6 está instalado
if ! command -v k6 &>/dev/null; then
    echo "[ERRO] k6 não está instalado."
    echo ""
    echo "Instale com:"
    echo "  # Linux (Debian/Ubuntu)"
    echo "  sudo gpg -k"
    echo "  sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69"
    echo "  echo 'deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main' | sudo tee /etc/apt/sources.list.d/k6.list"
    echo "  sudo apt-get update && sudo apt-get install k6"
    echo ""
    echo "  # macOS"
    echo "  brew install k6"
    exit 1
fi

# Determinar qual teste rodar
TEST_TYPE="${1:-smoke}"

case "$TEST_TYPE" in
    smoke)
        echo "[INFO] Executando smoke test..."
        k6 run -e BASE_URL="$BASE_URL" "$PROJECT_DIR/load-testing/smoke-test.js"
        ;;
    load)
        echo "[INFO] Executando load test..."
        k6 run -e BASE_URL="$BASE_URL" "$PROJECT_DIR/load-testing/load-test.js"
        ;;
    stress)
        echo "[INFO] Executando stress test..."
        k6 run -e BASE_URL="$BASE_URL" "$PROJECT_DIR/load-testing/stress-test.js"
        ;;
    spike)
        echo "[INFO] Executando spike test..."
        k6 run -e BASE_URL="$BASE_URL" "$PROJECT_DIR/load-testing/spike-test.js"
        ;;
    *)
        echo "Uso: $0 [smoke|load|stress|spike]"
        echo ""
        echo "Tipos de teste:"
        echo "  smoke   - Teste rápido de verificação (padrão)"
        echo "  load    - Teste de carga normal"
        echo "  stress  - Teste de carga máxima"
        echo "  spike   - Teste de pico repentino"
        exit 1
        ;;
esac
