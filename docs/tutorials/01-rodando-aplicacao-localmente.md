# Tutorial 01 — Rodando a Aplicação Localmente

## Objetivo

Rodar a aplicação **site-kubectl** (FastAPI + Jinja2) diretamente na sua máquina, sem Docker e sem Kubernetes.

## Conceitos

- **FastAPI**: framework web moderno para Python com suporte a async e documentação automática
- **Uvicorn**: servidor ASGI de alta performance que roda aplicações FastAPI
- **Virtual Environment (venv)**: ambiente Python isolado para gerenciar dependências

## Pré-requisitos

| Ferramenta | Versão | Verificar |
|------------|--------|-----------|
| Python | 3.10+ | `python3 --version` |
| pip | 21+ | `pip3 --version` |

## Passo a Passo

### 1. Navegar até o diretório da aplicação

```bash
cd site_kubectl
```

### 2. Criar o ambiente virtual

```bash
python3 -m venv venv
source venv/bin/activate
```

> No Windows: `venv\Scripts\activate`

### 3. Instalar dependências

```bash
pip install -r requirements.txt
```

### 4. Rodar a aplicação

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

O parâmetro `--reload` recarrega a aplicação automaticamente quando você modifica os arquivos.

### 5. Testar

```bash
# Em outro terminal:
curl http://localhost:8000/api/health
```

**Resultado esperado:**
```json
{"status":"ok","message":"App is running normally"}
```

### 6. Acessar no navegador

Abra: http://localhost:8000

Você verá a página principal do portal educacional.

### 7. Explorar a API

FastAPI gera documentação automática:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## Estrutura da Aplicação

```
site_kubectl/
├── app/
│   ├── main.py         ← Ponto de entrada principal
│   ├── data/           ← Dados JSON (conteúdo dos tutoriais)
│   ├── models/         ← Modelos Pydantic
│   ├── routers/        ← Rotas da API (docker, kubernetes, tools, etc.)
│   └── static/         ← Arquivos estáticos (CSS, JS)
├── templates/          ← Templates Jinja2 (HTML)
├── requirements.txt    ← Dependências Python
└── nginx.conf          ← Config do Nginx (usado no Docker)
```

## Endpoints Disponíveis

| Endpoint | Método | Descrição |
|----------|--------|-----------|
| `/` | GET | Página principal |
| `/api/health` | GET | Health check |
| `/api/search?q=termo` | GET | Busca global |
| `/docker` | GET | Tutoriais Docker |
| `/kubernetes` | GET | Tutoriais Kubernetes |
| `/tools` | GET | Ferramentas |
| `/projects` | GET | Projetos |
| `/cheatsheets` | GET | Cheatsheets |
| `/playground` | GET | Playground |

## Troubleshooting

| Problema | Solução |
|----------|---------|
| `ModuleNotFoundError` | Certifique-se de ativar o venv: `source venv/bin/activate` |
| Porta 8000 já em uso | Use outra porta: `--port 8001` |
| Templates não encontrados | Execute de dentro do diretório `site_kubectl/` |

## Próximo Tutorial

[02 — Containerização com Docker](02-containerizacao-docker.md)
