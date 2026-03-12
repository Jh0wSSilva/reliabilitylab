from fastapi import APIRouter, Request, HTTPException
from fastapi.templating import Jinja2Templates

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/")
async def list_docker_tutorials(request: Request):
    tutorials = request.app.state.data.get("docker", [])
    return templates.TemplateResponse("docker/index.html", {"request": request, "tutorials": tutorials})

@router.get("/api/list")
async def get_docker_api_list(request: Request):
    return request.app.state.data.get("docker", [])

@router.get("/{slug}")
async def get_docker_tutorial(slug: str, request: Request):
    tutorials = request.app.state.data.get("docker", [])
    tutorial = next((t for t in tutorials if t["slug"] == slug), None)
    if not tutorial:
        raise HTTPException(status_code=404, detail="Tutorial not found")
    
    # prev/next logic
    idx = tutorials.index(tutorial)
    prev_tut = tutorials[idx - 1] if idx > 0 else None
    next_tut = tutorials[idx + 1] if idx < len(tutorials) - 1 else None
    
    return templates.TemplateResponse("docker/tutorial.html", {
        "request": request,
        "tutorial": tutorial,
        "prev_tut": prev_tut,
        "next_tut": next_tut
    })
