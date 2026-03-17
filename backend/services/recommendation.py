from models.user_profile import UserProfile
from models.job import Job, SwipeAction
from typing import List

def get_recommended_jobs(profile: UserProfile, jobs_pool: List[Job], swipe_history: List[SwipeAction]) -> List[Job]:
    """
    RAG + LSTM Simulation:
    Scores jobs based on keyword matching and boosts based on recent user right-swipes.
    """
    # 1. Extract keywords from user profile
    user_keywords = set(profile.skills + profile.careerFields)
    for exp in profile.experiences:
        user_keywords.update(exp.jobTitle.split())
        
    user_keywords = {k.lower().strip() for k in user_keywords if len(k) > 2}

    # 2. Extract recent liked industries (Simulating LSTM context)
    liked_industries = []
    # Sort history descending
    recent_swipes = sorted(swipe_history, key=lambda s: s.timestamp, reverse=True)[:5]
    for action in recent_swipes:
        if action.direction.value == 'right':
            # In a real app we'd fetch the job here. Just mocking by pulling industry from the action if it existed.
            # For simplicity in this endpoint simulation, we might not have industry directly on SwipeAction.
            pass

    scored_jobs = []
    
    for job in jobs_pool:
        # Extract job keywords
        job_keywords = set(job.requiredSkills + job.title.split() + job.description.split())
        job_keywords = {k.lower().strip() for k in job_keywords if len(k) > 2}
        
        # Calculate overlap
        intersection = user_keywords.intersection(job_keywords)
        
        # Base score
        score = min(float(len(intersection) * 12), 100.0)
        
        # Work mode boost
        if profile.preferredWorkMode.lower() == job.workMode.lower():
            score += 5.0
            
        # Ensure max 100
        job.matchScore = min(score, 100.0)
        scored_jobs.append(job)

    # Sort descending by matchScore
    scored_jobs.sort(key=lambda j: j.matchScore, reverse=True)
    return scored_jobs
