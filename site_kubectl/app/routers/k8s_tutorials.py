from fastapi import APIRouter, Request, HTTPException
from fastapi.templating import Jinja2Templates

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/")
async def list_k8s_tutorials(request: Request):
    tutorials = request.app.state.data.get("kubernetes", [])
    return templates.TemplateResponse("kubernetes/index.html", {"request": request, "tutorials": tutorials})

@router.get("/api/list")
async def get_k8s_api_list(request: Request):
    return request.app.state.data.get("kubernetes", [])

@router.get("/{slug}")
async def get_k8s_tutorial(slug: str, request: Request):
    tutorials = request.app.state.data.get("kubernetes", [])
    tutorial = next((t for t in tutorials if t["slug"] == slug), None)
    if not tutorial:
        raise HTTPException(status_code=404, detail="Tutorial not found")
    
    idx = tutorials.index(tutorial)
    prev_tut = tutorials[idx - 1] if idx > 0 else None
    next_tut = tutorials[idx + 1] if idx < len(tutorials) - 1 else None
    
    return templates.TemplateResponse("kubernetes/tutorial.html", {
        "request": request,
        "tutorial": tutorial,
        "prev_tut": prev_tut,
        "next_tut": next_tut
    })
