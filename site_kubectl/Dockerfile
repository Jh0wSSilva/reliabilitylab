# =============================================================================
# Dockerfile — site_kubectl (FastAPI + Jinja2)
# Imagem otimizada multi-stage para ambiente de produção/laboratório
# =============================================================================

# --- Estágio 1: Build das dependências ---
FROM python:3.12-slim AS builder

WORKDIR /build

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

COPY requirements.txt .

RUN pip install --upgrade pip && \
    pip wheel --no-cache-dir --wheel-dir /build/wheels -r requirements.txt

# --- Estágio 2: Imagem final de execução ---
FROM python:3.12-slim

LABEL maintainer="reliabilitylab"
LABEL description="Aplicação FastAPI do laboratório DevOps ReliabilityLab"

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_HOST=0.0.0.0 \
    APP_PORT=8000 \
    APP_ENV=production \
    LOG_LEVEL=info

# Criar usuário não-root para segurança
RUN groupadd --system appgroup && \
    useradd --system --gid appgroup --uid 10001 --create-home appuser

# Instalar dependências pré-compiladas do estágio builder
COPY --from=builder /build/wheels /tmp/wheels
COPY --from=builder /build/requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir --no-index --find-links=/tmp/wheels -r /tmp/requirements.txt && \
    rm -rf /tmp/wheels /tmp/requirements.txt

# Copiar código da aplicação com permissões corretas
COPY --chown=appuser:appgroup app/ /app/app/
COPY --chown=appuser:appgroup templates/ /app/templates/

# Executar como usuário não-root
USER appuser

EXPOSE 8000

# Verificação de saúde nativa do Docker
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health', timeout=3)" || exit 1

# Iniciar servidor Uvicorn
CMD ["sh", "-c", "uvicorn app.main:app --host ${APP_HOST:-0.0.0.0} --port ${APP_PORT:-8000}"]
