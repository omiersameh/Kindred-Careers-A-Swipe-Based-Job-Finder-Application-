from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime

class CVExperience(BaseModel):
    id: str
    jobTitle: str
    company: str
    startDate: str
    endDate: str
    achievements: List[str]

class CVContent(BaseModel):
    summary: str
    skills: List[str]
    experiences: List[CVExperience]

class CVFeedback(BaseModel):
    id: str
    feedbackText: str
    timestamp: datetime
    regenerated: bool = False

class CV(BaseModel):
    id: str
    jobId: str
    userId: str
    content: CVContent
    generatedAt: datetime
    wasModified: bool = False
    regenerationCount: int = 0
    feedbackHistory: List[CVFeedback] = []
