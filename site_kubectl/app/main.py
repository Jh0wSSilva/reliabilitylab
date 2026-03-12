import os
import json
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.middleware.cors import CORSMiddleware
import logging

from app.routers import (
    docker_tutorials,
    k8s_tutorials,
    tools,
    projects,
    cheatsheets,
    playground
)

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global state for data
app_data = {
    "docker": [],
    "kubernetes": [],
    "tools": [],
    "cheatsheets": [],
    "projects": []
}

def load_json_data(filename: str):
    path = os.path.join(os.path.dirname(__file__), 'data', filename)
    if os.path.exists(path):
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    return []

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Load data on startup
    logger.info("Loading data from JSON files...")
    app.state.data = {
        "docker": load_json_data("docker_tutorials.json"),
        "kubernetes": load_json_data("k8s_tutorials.json"),
        "tools": load_json_data("tools.json"),
        "cheatsheets": load_json_data("cheatsheets.json"),
        "projects": load_json_data("projects.json")
    }
    logger.info("Data loaded successfully.")
    yield
    # Cleanup on shutdown
    logger.info("Shutting down...")

app = FastAPI(title="K8s & Docker Lab Pro", lifespan=lifespan)

# CORS config
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount static files
app.mount("/static", StaticFiles(directory="app/static"), name="static")

# Templates
templates = Jinja2Templates(directory="templates")

# Include routers
app.include_router(docker_tutorials.router, prefix="/docker", tags=["Docker"])
app.include_router(k8s_tutorials.router, prefix="/kubernetes", tags=["Kubernetes"])
app.include_router(tools.router, prefix="/tools", tags=["Tools"])
app.include_router(projects.router, prefix="/projects", tags=["Projects"])
app.include_router(cheatsheets.router, prefix="/cheatsheets", tags=["CheatSheets"])
app.include_router(playground.router, prefix="/playground", tags=["Playground"])

# Expose app_data to templates and request state (or routers can import it)
# In a real app we might inject this via Dependencies, but here we can just import it in routers.

@app.get("/api/health")
async def health_check():
    return {"status": "ok", "message": "App is running normally"}

@app.get("/api/search")
async def global_search(request: Request, q: str = ""):
    q = q.lower()
    results = []
    # Search in docker
    for item in request.app.state.data.get("docker", []):
        if q in item["title"].lower() or q in item["content"].lower():
            results.append({"title": item["title"], "slug": f"/docker/{item['slug']}", "category": "Docker", "excerpt": item.get("excerpt", "")})
    # Search in kubernetes
    for item in request.app.state.data.get("kubernetes", []):
         if q in item["title"].lower() or q in item["content"].lower():
            results.append({"title": item["title"], "slug": f"/kubernetes/{item['slug']}", "category": "Kubernetes", "excerpt": item.get("excerpt", "")})
    return results

@app.get("/")
async def root(request: Request):
    d = request.app.state.data
    cheat_count = sum(len(s.get("commands", [])) for s in d.get("cheatsheets", []))
    return templates.TemplateResponse("index.html", {
        "request": request,
        "docker_count": len(d.get("docker", [])),
        "k8s_count": len(d.get("kubernetes", [])),
        "cheat_count": cheat_count,
        "stats": {
            "tutorials": len(d.get("docker", [])) + len(d.get("kubernetes", [])),
            "tools": len(d.get("tools", [])),
            "projects": len(d.get("projects", []))
        }
    })
