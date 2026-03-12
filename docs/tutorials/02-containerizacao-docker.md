# Tutorial 02 — Containerização com Docker

## Objetivo

Empacotar a aplicação site-kubectl em uma imagem Docker otimizada usando **multi-stage build**.

## Conceitos

- **Dockerfile multi-stage**: separa o build das dependências da imagem final, reduzindo tamanho e superfície de ataque
- **Usuário não-root**: executar a aplicação com um usuário sem privilégios administrativos
- **HEALTHCHECK**: verificação nativa do Docker para monitorar a saúde do container
- **docker-compose**: orquestração local de múltiplos containers

## Pré-requisitos

| Ferramenta | Versão | Verificar |
|------------|--------|-----------|
| Docker | 20.10+ | `docker --version` |
| Docker Compose | 2.0+ | `docker compose version` |

## Passo a Passo

### 1. Analisar o Dockerfile

O Dockerfile está em `site_kubectl/Dockerfile`. Vamos entender cada parte:

```dockerfile
# Estágio 1: Build — instala dependências e cria wheels
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip wheel --no-cache-dir --wheel-dir /build/wheels -r requirements.txt

# Estágio 2: Runtime — imagem final leve
FROM python:3.12-slim
WORKDIR /app

# Criar usuário não-root
RUN groupadd --system appgroup && \
    useradd --system --gid appgroup --uid 10001 --create-home appuser

# Instalar wheels pré-compilados
COPY --from=builder /build/wheels /tmp/wheels
RUN pip install --no-cache-dir --find-links=/tmp/wheels -r /tmp/requirements.txt

# Copiar código
COPY --chown=appuser:appgroup app/ /app/app/
COPY --chown=appuser:appgroup templates/ /app/templates/

# Executar como não-root
USER appuser
EXPOSE 8000

# Health check nativo
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/health')"

CMD ["sh", "-c", "uvicorn app.main:app --host ${APP_HOST:-0.0.0.0} --port ${APP_PORT:-8000}"]
```

### 2. Construir a imagem

```bash
bash scripts/build.sh
```

Ou manualmente:
```bash
docker build -t local/reliabilitylab-site-kubectl:latest -f site_kubectl/Dockerfile site_kubectl
```

### 3. Verificar a imagem

```bash
docker images | grep reliabilitylab
```

**Resultado esperado:**
```
local/reliabilitylab-site-kubectl   latest   abc123   10 seconds ago   180MB
```

### 4. Rodar o container

```bash
docker run -d --name site-kubectl \
    -p 8080:8000 \
    -e APP_ENV=development \
    -e LOG_LEVEL=debug \
    local/reliabilitylab-site-kubectl:latest
```

### 5. Testar

```bash
curl http://localhost:8080/api/health
```

**Resultado esperado:**
```json
{"status":"ok","message":"App is running normally"}
```

### 6. Verificar o health check do Docker

```bash
docker inspect --format='{{json .State.Health}}' site-kubectl | python3 -m json.tool
```

### 7. Ver logs do container

```bash
docker logs -f site-kubectl
```

### 8. Parar e remover

```bash
docker stop site-kubectl && docker rm site-kubectl
```

## Usando docker-compose

O arquivo `site_kubectl/docker-compose.yml` configura a aplicação com hot-reload para desenvolvimento:

```bash
cd site_kubectl
docker compose up -d
```

Acesse: http://localhost:8080

Para parar:
```bash
docker compose down
```

## Boas Práticas Aplicadas

| Prática | Benefício |
|---------|----------|
| Multi-stage build | Imagem menor (~180MB vs ~800MB) |
| Usuário não-root (UID 10001) | Segurança: limita impacto de vulnerabilidade |
| HEALTHCHECK | Monitoramento nativo de saúde |
| `--no-cache-dir` | Menor tamanho de imagem |
| `COPY --chown` | Permissões corretas sem `chmod` extra |
| Variáveis de ambiente | Configuração flexível sem alterar código |

## Troubleshooting

| Problema | Solução |
|----------|---------|
| `permission denied` ao iniciar | Verifique se USER é `appuser` no Dockerfile |
| Health check failing | Aumente o `--start-period` |
| `ModuleNotFoundError` | Verifique se todas as dependências estão no `requirements.txt` |
| Porta já em uso | Use outra porta: `-p 8081:8000` |

## Próximo Tutorial

[03 — Criando um Cluster Kubernetes Local](03-criando-cluster-kubernetes-local.md)
