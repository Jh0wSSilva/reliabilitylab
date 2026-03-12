from fastapi import APIRouter, Request
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel
import yaml

router = APIRouter()
templates = Jinja2Templates(directory="templates")

class ValidateRequest(BaseModel):
    yaml_content: str

@router.get("/")
async def render_playground(request: Request):
    return templates.TemplateResponse("playground/index.html", {"request": request})

@router.post("/validate")
async def validate_yaml(req: ValidateRequest):
    try:
        content = yaml.safe_load(req.yaml_content)
        if not content:
            return {"status": "error", "message": "YAML is empty or invalid format"}
        
        warnings = []
        # Check basic K8s heuristics
        if "kind" not in content:
            return {"status": "error", "message": "Missing 'kind' attribute."}
        if "metadata" not in content:
            warnings.append("Missing 'metadata' attribute.")
            
        if content["kind"] in ["Deployment", "Pod", "StatefulSet"]:
            spec = content.get("spec", {})
            template_spec = spec.get("template", {}).get("spec", {}) if content["kind"] != "Pod" else spec
            containers = template_spec.get("containers", [])
            for c in containers:
                if "resources" not in c:
                    warnings.append(f"Container '{c.get('name', 'unknown')}' is missing resource limits/requests.")
                if "livenessProbe" not in c:
                    warnings.append(f"Container '{c.get('name', 'unknown')}' is missing a livenessProbe.")
                image = c.get("image", "")
                if ":latest" in image or ":" not in image:
                    warnings.append(f"Avoid using ':latest' tag for image '{image}'.")
        
        return {
            "status": "success",
            "message": f"Successfully parsed {content.get('kind')} manifest.",
            "warnings": warnings,
            "parsed_name": content.get("metadata", {}).get("name", "unknown")
        }
    except yaml.YAMLError as exc:
        return {"status": "error", "message": f"YAML Parse Error: {str(exc)}"}
