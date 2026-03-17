from pydantic import BaseModel
from typing import List, Optional

class Experience(BaseModel):
    id: str
    jobTitle: str
    company: str
    startDate: str
    endDate: str

class Education(BaseModel):
    id: str
    degree: str
    fieldOfStudy: str
    institution: str
    graduationYear: str

class UserProfile(BaseModel):
    id: str
    name: str
    email: str
    phone: str
    bio: str
    location: str
    skills: List[str]
    experiences: List[Experience]
    educations: List[Education]
    careerFields: List[str]
    preferredWorkMode: str
