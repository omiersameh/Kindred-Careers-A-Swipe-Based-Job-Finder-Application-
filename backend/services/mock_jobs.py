from typing import List, Optional

MOCK_JOBS = [
    {
        "id": "mock_job_1",
        "title": "Senior Flutter Developer",
        "company": "KindredTech Solutions",
        "location": "Remote (US/Europe)",
        "minSalary": 95.0,
        "maxSalary": 140.0,
        "workMode": "Remote",
        "industry": "Technology",
        "careerField": "Technology",
        "specialization": "Mobile App Development",
        "logoEmoji": "💻",
        "postedDate": "2026-06-01",
        "matchScore": 95.0,
        "imageUrl": "",
        "vibeTag": "🚀 Fast-paced Startup",
        "description": "We are seeking a Lead/Senior Flutter Developer to join our fully remote engineering team. You will drive the architecture and development of our primary mobile applications, implementing slick animations, solid state management with Provider, and robust offline-first synchronization. Experience with Firebase, App Store/Play Store deployments, and clean architectural patterns is highly desired.",
        "requiredSkills": ["Flutter", "Dart", "Firebase", "State Management", "Git"],
        "summaryBullets": [
            "Lead architecture and feature development of premium mobile apps using Flutter/Dart",
            "Build liquid glass animations and clean, responsive layouts using Provider",
            "Optimize backend integrations and client-side database synchronization",
            "Collaborate with UX designers to deliver a premium user experience"
        ]
    },
    {
        "id": "mock_job_2",
        "title": "Python API Backend Engineer",
        "company": "PyCloud Systems",
        "location": "Hybrid (San Francisco, CA)",
        "minSalary": 110.0,
        "maxSalary": 160.0,
        "workMode": "Hybrid",
        "industry": "Technology",
        "careerField": "Technology",
        "specialization": "Backend Development",
        "logoEmoji": "⚙️",
        "postedDate": "2026-06-02",
        "matchScore": 88.0,
        "imageUrl": "",
        "vibeTag": "🏢 Tech Scale-up",
        "description": "Looking for a seasoned backend engineer with expert knowledge of Python, FastAPI, and asynchronous workflows. You will design, build, and optimize high-throughput REST APIs, integrate with vector databases (ChromaDB), and help deploy containerized microservices in Docker environments. Experience with SQL/NoSQL databases and clean coding practices (ruff/mypy) is a must.",
        "requiredSkills": ["Python", "FastAPI", "Docker", "REST APIs", "SQLAlchemy"],
        "summaryBullets": [
            "Build and scale async REST APIs using FastAPI and Uvicorn",
            "Integrate vector databases and search engines for RAG applications",
            "Maintain Docker container pipelines and manage cloud-native deployments",
            "Improve performance through profiling and async database drivers"
        ]
    },
    {
        "id": "mock_job_3",
        "title": "AI/ML Engineering Specialist",
        "company": "NeuroSystems Labs",
        "location": "Remote",
        "minSalary": 130.0,
        "maxSalary": 200.0,
        "workMode": "Remote",
        "industry": "Science & Research",
        "careerField": "Science & Research",
        "specialization": "AI & ML Engineer",
        "logoEmoji": "🤖",
        "postedDate": "2026-06-03",
        "matchScore": 92.0,
        "imageUrl": "",
        "vibeTag": "🔬 R&D Frontier",
        "description": "Join our AI research team to develop and deploy cutting-edge language models and retrieval structures. You will design custom RAG pipelines, optimize LLM context window compression, implement re-ranking and hybrid search models, and fine-tune open-source models (Llama-3, Mistral) for specific domain tasks. Solid understanding of PyTorch and transformer embeddings is required.",
        "requiredSkills": ["Python", "LLMs", "RAG Systems", "PyTorch", "Embeddings"],
        "summaryBullets": [
            "Architect and optimize high-accuracy RAG and semantic search systems",
            "Fine-tune and deploy open-weight LLMs for specialized tasks",
            "Optimize context window processing and implement re-ranking algorithms",
            "Collaborate on deep learning architectures using PyTorch and HuggingFace"
        ]
    },
    {
        "id": "mock_job_4",
        "title": "Lead UI/UX Digital Designer",
        "company": "Glassmorphic Design Studio",
        "location": "Remote (Global)",
        "minSalary": 80.0,
        "maxSalary": 120.0,
        "workMode": "Remote",
        "industry": "Design",
        "careerField": "Art & Design",
        "specialization": "UI & UX Designer",
        "logoEmoji": "🎨",
        "postedDate": "2026-06-01",
        "matchScore": 85.0,
        "imageUrl": "",
        "vibeTag": "✨ Creative Boutique",
        "description": "We are seeking a visionary digital designer who loves dark mode aesthetics, glassmorphism, and smooth micro-animations. You will create modern, high-fidelity UI mockups, define interactive design systems, and work closely with frontend developers to bring premium visual designs to life. Proficiency in Figma and a strong design portfolio are required.",
        "requiredSkills": ["Figma", "UI Design", "UX Research", "Design Systems", "Prototyping"],
        "summaryBullets": [
            "Create stunning, premium user interfaces with a focus on modern dark aesthetics",
            "Develop unified design systems and high-fidelity prototypes in Figma",
            "Conduct usability testing and iterate on complex navigation flows",
            "Ensure design alignment and asset handoff with frontend engineers"
        ]
    },
    {
        "id": "mock_job_5",
        "title": "Senior Growth Marketing Analyst",
        "company": "Marketify Inc.",
        "location": "Onsite (New York, NY)",
        "minSalary": 90.0,
        "maxSalary": 130.0,
        "workMode": "Onsite",
        "industry": "Marketing",
        "careerField": "Media & Communication",
        "specialization": "Growth Marketing",
        "logoEmoji": "📢",
        "postedDate": "2026-05-28",
        "matchScore": 80.0,
        "imageUrl": "",
        "vibeTag": "📈 High Growth",
        "description": "We are hiring a Growth Marketing Analyst to manage user acquisition and digital ad spend. You will design, execute, and analyze paid search, social media campaigns, and A/B tests to optimize conversion rates and lower customer acquisition costs. Strong experience with Google Analytics, SQL, and data-driven marketing tools is required.",
        "requiredSkills": ["SEO", "Google Analytics", "SQL", "A/B Testing", "Paid Ads"],
        "summaryBullets": [
            "Formulate and execute data-driven acquisition strategies across multiple ad networks",
            "Analyze marketing funnels and run multivariate A/B testing on landing pages",
            "Write SQL queries to extract insight from customer behavior datasets",
            "Manage and allocate a significant monthly budget based on ROI metrics"
        ]
    },
    {
        "id": "mock_job_6",
        "title": "Corporate Finance Specialist",
        "company": "Capital Partners Ltd.",
        "location": "Hybrid (London, UK)",
        "minSalary": 100.0,
        "maxSalary": 150.0,
        "workMode": "Hybrid",
        "industry": "Finance",
        "careerField": "Business & Finance",
        "specialization": "Financial Analyst",
        "logoEmoji": "💰",
        "postedDate": "2026-05-30",
        "matchScore": 78.0,
        "imageUrl": "",
        "vibeTag": "💼 Prestige Firm",
        "description": "Seeking a high-caliber Finance Specialist to join our advisory team. You will construct complex financial models, evaluate investment opportunities, perform valuations, and prepare investment memoranda for clients. Strong analytical background, spreadsheet modeling expertise, and solid understanding of corporate finance theory are required.",
        "requiredSkills": ["Financial Modeling", "Corporate Finance", "Valuation", "Excel", "Data Analysis"],
        "summaryBullets": [
            "Develop robust forecasting and evaluation models for client projects",
            "Execute financial diligence and quantitative risk analyses",
            "Present complex investment presentations to corporate leadership and clients",
            "Collaborate with legal and operational teams during transaction cycles"
        ]
    }
]

def get_mock_jobs(profile: Optional[object] = None) -> List[dict]:
    """
    Returns mock jobs, optionally sorted/filtered to match the user's career fields.
    """
    if not profile:
        return MOCK_JOBS
        
    career_fields = [f.lower().strip() for f in getattr(profile, "careerFields", [])]
    skills = [s.lower().strip() for s in getattr(profile, "skills", [])]
    
    if not career_fields and not skills:
        return MOCK_JOBS
        
    # Score each mock job based on careerField and skill matches
    scored_jobs = []
    for job in MOCK_JOBS:
        score = 0.0
        # Career field match is highest priority
        job_field = job.get("careerField", "").lower().strip()
        if job_field in career_fields:
            score += 10.0
            
        # Skill matches
        job_skills = [s.lower().strip() for s in job.get("requiredSkills", [])]
        for skill in skills:
            if any(skill in s or s in skill for s in job_skills):
                score += 1.0
                
        # Set a realistic matchScore based on the profile
        job_copy = job.copy()
        if score > 0:
            job_copy["matchScore"] = min(98.0, job["matchScore"] + (score * 2))
        else:
            job_copy["matchScore"] = max(55.0, job["matchScore"] - 15.0)
            
        scored_jobs.append((score, job_copy))
        
    # Sort by score descending, then by matchScore
    scored_jobs.sort(key=lambda x: (x[0], x[1]["matchScore"]), reverse=True)
    
    return [item[1] for item in scored_jobs]
