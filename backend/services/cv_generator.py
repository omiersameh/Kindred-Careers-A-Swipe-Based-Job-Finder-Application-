import os
import json
from openai import AsyncOpenAI
from dotenv import load_dotenv
from models.user_profile import UserProfile
from models.job import Job
from models.cv import CV, CVContent, CVExperience

# Load .env from the backend/ directory
load_dotenv()

# OpenRouter client — API key loaded from .env
client = AsyncOpenAI(
    base_url="https://openrouter.ai/api/v1",
    api_key=os.getenv("CV_OPENROUTER_API_KEY", ""),
)
_CV_MODEL = os.getenv("CV_MODEL", "openai/gpt-oss-120b:free")

async def generate_tailored_cv(job: Job, profile: UserProfile) -> CVContent:
    """
    Uses OpenAI to generate a tailored CV JSON based on the user's profile and the target job.
    """
    system_prompt = '''You are an expert technical recruiter and CV writer.
You will be provided with a user's raw profile data and a target job description.
Your task is to generate a tailored CV specifically optimized to pass ATS systems for this job.
Output MUST be a raw JSON object matching this schema exactly:
{
  "summary": "str - A strong 2-3 sentence professional summary tailored to the job",
  "skills": ["str", "str"] - ranked list of skills most relevant to the job,
  "experiences": [
    {
      "id": "str",
      "jobTitle": "str",
      "company": "str",
      "startDate": "str",
      "endDate": "str",
      "achievements": ["str", "str"] - rewrite achievements to highlight keywords from the job
    }
  ]
}
Do not include markdown blocks or any text outside the JSON.
'''

    user_prompt = f'''
TARGET JOB:
Title: {job.title}
Company: {job.company}
Required Skills: {', '.join(job.requiredSkills)}
Description: {job.description}

USER PROFILE:
Name: {profile.name}
Skills: {', '.join(profile.skills)}
Career Fields: {', '.join(profile.careerFields)}
Raw Experiences: {json.dumps([e.model_dump() for e in profile.experiences], default=str)}
'''

    try:
        response = await client.chat.completions.create(
            model=_CV_MODEL,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            response_format={ "type": "json_object" },
            temperature=0.7
        )
        
        raw_json = response.choices[0].message.content
        data = json.loads(raw_json)
        
        # Parse into Pydantic models to ensure schema validity
        experiences = [
            CVExperience(**exp) for exp in data.get("experiences", [])
        ]
        
        content = CVContent(
            summary=data.get("summary", ""),
            skills=data.get("skills", []),
            experiences=experiences
        )
        
        return content
        
    except Exception as e:
        print(f"OpenAI Generation Failed: {e}")
        raise e

async def regenerate_tailored_cv(existing_content: CVContent, feedback: str, job: Job, profile: UserProfile) -> CVContent:
    """
    Regenerates the CV by passing the existing content and user feedback back to the LLM.
    """
    # Very similar logic, but we provide the old CV and the feedback as context
    system_prompt = '''You are an expert technical recruiter and CV writer. Output valid JSON only.'''
    
    user_prompt = f'''
The user wants to revise their generated CV based on this feedback: "{feedback}"

TARGET JOB: {job.title} at {job.company}
CURRENT CV STRUCTURE (JSON):
{json.dumps(existing_content.model_dump(), default=str)}

Return the EXACT SAME JSON structure with the requested changes applied (e.g. updating the summary, modifying bullet points, adding a skill).
'''

    try:
        response = await client.chat.completions.create(
            model=_CV_MODEL,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            response_format={ "type": "json_object" },
            temperature=0.7
        )
        
        data = json.loads(response.choices[0].message.content)
        experiences = [CVExperience(**exp) for exp in data.get("experiences", [])]
        
        return CVContent(
            summary=data.get("summary", ""),
            skills=data.get("skills", []),
            experiences=experiences
        )
        
    except Exception as e:
        print(f"OpenAI Regeneration Failed: {e}")
        raise e
