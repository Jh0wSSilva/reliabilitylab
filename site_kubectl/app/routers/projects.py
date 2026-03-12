from fastapi import APIRouter, Request
from fastapi.templating import Jinja2Templates

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/")
async def list_projects(request: Request):
    projects = request.app.state.data.get("projects", [])
    return templates.TemplateResponse("projects/index.html", {"request": request, "projects": projects})

@router.get("/api/list")
async def get_projects_api_list(request: Request):
    return request.app.state.data.get("projects", [])
