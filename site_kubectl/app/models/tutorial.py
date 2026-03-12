from pydantic import BaseModel
from typing import List, Optional

class Tutorial(BaseModel):
    id: str
    title: str
    slug: str
    category: str
    level: int  # 1 to 5
    duration: int  # in minutes
    tags: List[str]
    content: str
    excerpt: Optional[str] = None

class Command(BaseModel):
    cmd: str
    description: str
    example: Optional[str] = None

class CheatSheet(BaseModel):
    id: str
    title: str
    category: str
    commands: List[Command]

class Tool(BaseModel):
    id: str
    name: str
    description: str
    docs_url: Optional[str] = None
    install_cmd: Optional[str] = None

class SearchResult(BaseModel):
    title: str
    slug: str
    category: str
    excerpt: str
