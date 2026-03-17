from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
from enum import Enum

class Job(BaseModel):
    id: str
    title: str
    company: str
    location: str
    minSalary: float = 0
    maxSalary: float = 0
    workMode: str = "Hybrid"  # Remote, Hybrid, Onsite
    description: str = ""
    requiredSkills: List[str] = []
    industry: str = ""
    matchScore: float = 0.0
    jobType: str = "Full-Time"
    postedDate: str = ""
    logoEmoji: str = "🏢"
    # Phase 3: RAG fields
    imageUrl: str = ""        # Company/listing image URL
    summaryBullets: List[str] = []  # 3-4 Gemini-generated bullet summary
    vibeTag: str = ""         # e.g. 'Fast-paced Startup'

class SwipeDirection(str, Enum):
    left = "left"
    right = "right"

class SwipeAction(BaseModel):
    id: str
    jobId: str
    jobTitle: str
    company: str
    direction: SwipeDirection
    timestamp: datetime
