import json
import os
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, HRFlowable
from reportlab.lib.colors import HexColor

def generate_pdf(member_id, job_index, profile, job, output_dir):
    filename = f"m{member_id[-1]}_job{job_index}.pdf"
    filepath = os.path.join(output_dir, filename)
    
    doc = SimpleDocTemplate(
        filepath,
        pagesize=letter,
        rightMargin=50,
        leftMargin=50,
        topMargin=50,
        bottomMargin=50
    )
    
    styles = getSampleStyleSheet()
    
    # Custom styles
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Heading1'],
        fontSize=24,
        spaceAfter=6,
        textColor=HexColor('#111111')
    )
    
    contact_style = ParagraphStyle(
        'ContactInfo',
        parent=styles['Normal'],
        fontSize=10,
        textColor=HexColor('#555555'),
        spaceAfter=12
    )
    
    heading_style = ParagraphStyle(
        'CustomHeading2',
        parent=styles['Heading2'],
        fontSize=14,
        textColor=HexColor('#222222'),
        spaceBefore=14,
        spaceAfter=6
    )
    
    body_style = ParagraphStyle(
        'CustomBody',
        parent=styles['Normal'],
        fontSize=11,
        leading=14,
        spaceAfter=8
    )
    
    bullet_style = ParagraphStyle(
        'CustomBullet',
        parent=styles['Normal'],
        fontSize=11,
        leading=14,
        leftIndent=15,
        firstLineIndent=-10,
        spaceAfter=4
    )
    
    elements = []
    
    # Header: Name
    full_name = f"{profile.get('firstName', '')} {profile.get('lastName', '')}"
    elements.append(Paragraph(full_name, title_style))
    
    # Header: Contact
    contact_info = f"{profile.get('location', '')} | {profile.get('email', '')} | {profile.get('phone', '')}"
    elements.append(Paragraph(contact_info, contact_style))
    elements.append(HRFlowable(width="100%", thickness=1, color=HexColor('#CCCCCC'), spaceAfter=15))
    
    # Objective / Summary tailored to Job
    elements.append(Paragraph("PROFESSIONAL SUMMARY", heading_style))
    summary_text = (
        f"Results-driven professional seeking the <b>{job.get('title', '')}</b> role at "
        f"<b>{job.get('company', '')}</b>. Leveraging a strong background in "
        f"{', '.join(profile.get('careerFieldIds', [])).replace('_', ' ').title()} and proven expertise in "
        f"{', '.join(profile.get('skills', [])[:4])}. Eager to contribute to innovative projects "
        f"within the {job.get('industry', '')} sector."
    )
    elements.append(Paragraph(summary_text, body_style))
    
    # Skills
    elements.append(Paragraph("CORE COMPETENCIES", heading_style))
    skills_text = ", ".join(profile.get('skills', []))
    elements.append(Paragraph(skills_text, body_style))
    
    # Experience
    elements.append(Paragraph("PROFESSIONAL EXPERIENCE", heading_style))
    for exp in profile.get('experiences', []):
        job_title = f"<b>{exp.get('jobTitle', '')}</b>"
        company_date = f"{exp.get('company', '')} | {exp.get('startDate', '')} – {exp.get('endDate', '')}"
        
        elements.append(Paragraph(job_title, body_style))
        elements.append(Paragraph(company_date, contact_style))
        
        # Add a bullet point customized for the target job
        elements.append(Paragraph(f"• {exp.get('description', '')}", bullet_style))
        req_skills = job.get('requiredSkills', [])
        if req_skills:
            tailored_bullet = f"• Demonstrated proficiency in key technologies including {', '.join(req_skills[:3])} to deliver high-impact results."
            elements.append(Paragraph(tailored_bullet, bullet_style))
            
        elements.append(Spacer(1, 8))
        
    # Education
    elements.append(Paragraph("EDUCATION & CREDENTIALS", heading_style))
    edu_text = f"<b>{profile.get('degree', '')} in {profile.get('fieldOfStudy', '')}</b>"
    elements.append(Paragraph(edu_text, body_style))
    edu_school = f"{profile.get('institution', '')} | Class of {profile.get('graduationYear', '')}"
    elements.append(Paragraph(edu_school, contact_style))
    
    for cred in profile.get('credentials', []):
        elements.append(Paragraph(f"• {cred.get('title')} - {cred.get('issuer')} ({cred.get('year')})", bullet_style))
        
    # Build PDF
    doc.build(elements)
    print(f"Generated {filename} for {full_name} targeting {job.get('title')}")

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    mock_data_dir = os.path.join(base_dir, 'mock_data')
    output_dir = os.path.join(base_dir, 'mock_cvs')
    
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        
    # Generate for all 3 members
    for i in range(1, 4):
        member_id = f"demo_member_{i}"
        profile_path = os.path.join(mock_data_dir, f"member{i}_profile.json")
        jobs_path = os.path.join(mock_data_dir, f"member{i}_jobs.json")
        
        if not os.path.exists(profile_path) or not os.path.exists(jobs_path):
            print(f"Missing data for member {i}, skipping.")
            continue
            
        with open(profile_path, 'r', encoding='utf-8') as f:
            profile = json.load(f)
            
        with open(jobs_path, 'r', encoding='utf-8') as f:
            jobs = json.load(f)
            
        for idx, job in enumerate(jobs):
            generate_pdf(member_id, idx, profile, job, output_dir)
            
    print(f"\nSuccessfully generated {3 * 20} mock PDFs in {output_dir}")

if __name__ == "__main__":
    main()
