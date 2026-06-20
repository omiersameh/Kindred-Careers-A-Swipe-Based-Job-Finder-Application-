from pydantic import BaseModel
from typing import List, Optional, Dict

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

class Credential(BaseModel):
    id: str
    title: str
    issuer: str
    year: str

class UserProfile(BaseModel):
    id: str
    name: str
    email: str
    phone: str
    bio: str
    location: str
    skills: List[str]
    specializations: Dict[str, List[str]] = {}
    credentials: List[Credential] = []
    experiences: List[Experience]
    educations: List[Education]
    careerFields: List[str]
    preferredWorkMode: str
