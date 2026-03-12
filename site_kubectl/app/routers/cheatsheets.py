from fastapi import APIRouter, Request
from fastapi.templating import Jinja2Templates

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/")
async def list_cheatsheets(request: Request):
    sheets = request.app.state.data.get("cheatsheets", [])
    return templates.TemplateResponse("cheatsheets/index.html", {"request": request, "sheets": sheets})

@router.get("/api/list")
async def get_cheatsheets_api_list(request: Request):
    return request.app.state.data.get("cheatsheets", [])
