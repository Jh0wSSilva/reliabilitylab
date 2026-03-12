from fastapi import APIRouter, Request
from fastapi.templating import Jinja2Templates

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/")
async def list_tools(request: Request):
    tools = request.app.state.data.get("tools", [])
    return templates.TemplateResponse("tools/index.html", {"request": request, "tools": tools})

@router.get("/api/list")
async def get_tools_api_list(request: Request):
    return request.app.state.data.get("tools", [])
