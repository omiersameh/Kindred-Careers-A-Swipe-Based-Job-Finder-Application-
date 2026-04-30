"""
cv_pdf_generator.py — ATS-optimized PDF CV generator using ReportLab.

Produces a clean, single-column PDF that passes ATS (Applicant Tracking System)
parsing reliably:
  - Standard fonts (Helvetica) — no embedded fonts that confuse parsers
  - No tables, columns, text boxes, or images
  - Logical reading order: Contact → Summary → Skills → Experience → Education
  - All text is selectable (no image-based rendering)
"""

import io
from typing import List, Optional

from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, HRFlowable, ListFlowable, ListItem
)

# ── Colour palette (ATS-safe — minimal use of colour) ─────────────────────
_BLACK      = colors.HexColor("#000000")
_DARK_GREY  = colors.HexColor("#333333")
_MID_GREY   = colors.HexColor("#555555")
_LIGHT_GREY = colors.HexColor("#888888")
_RULE_GREY  = colors.HexColor("#CCCCCC")


def _build_styles():
    """Returns a dict of named ParagraphStyles for the CV document."""
    base = getSampleStyleSheet()

    styles = {}

    # Candidate name — large, bold
    styles["name"] = ParagraphStyle(
        "name",
        fontName="Helvetica-Bold",
        fontSize=20,
        leading=24,
        textColor=_BLACK,
        spaceAfter=2,
    )

    # Contact line — small grey
    styles["contact"] = ParagraphStyle(
        "contact",
        fontName="Helvetica",
        fontSize=10,
        leading=14,
        textColor=_MID_GREY,
        spaceAfter=4,
    )

    # Section header (EXPERIENCE, SKILLS …)
    styles["section_header"] = ParagraphStyle(
        "section_header",
        fontName="Helvetica-Bold",
        fontSize=11,
        leading=14,
        textColor=_BLACK,
        spaceBefore=14,
        spaceAfter=4,
        textTransform="uppercase",
    )

    # Body text
    styles["body"] = ParagraphStyle(
        "body",
        fontName="Helvetica",
        fontSize=10,
        leading=15,
        textColor=_DARK_GREY,
        spaceAfter=4,
    )

    # Job title line inside an experience block
    styles["job_title"] = ParagraphStyle(
        "job_title",
        fontName="Helvetica-Bold",
        fontSize=10,
        leading=14,
        textColor=_BLACK,
        spaceAfter=1,
    )

    # Company + dates sub-line
    styles["job_meta"] = ParagraphStyle(
        "job_meta",
        fontName="Helvetica-Oblique",
        fontSize=10,
        leading=13,
        textColor=_MID_GREY,
        spaceAfter=4,
    )

    # Bullet item
    styles["bullet"] = ParagraphStyle(
        "bullet",
        fontName="Helvetica",
        fontSize=10,
        leading=14,
        textColor=_DARK_GREY,
        leftIndent=14,
        spaceAfter=2,
        bulletIndent=4,
    )

    # Skill chip — same as body but used inline in a comma-joined string
    styles["skills_text"] = ParagraphStyle(
        "skills_text",
        fontName="Helvetica",
        fontSize=10,
        leading=15,
        textColor=_DARK_GREY,
        spaceAfter=6,
    )

    return styles


def _hr(styles) -> HRFlowable:
    """Thin grey horizontal rule below section headers."""
    return HRFlowable(
        width="100%",
        thickness=0.5,
        color=_RULE_GREY,
        spaceAfter=6,
    )


def generate_cv_pdf(
    summary: str,
    skills: List[str],
    experiences: List[dict],           # {jobTitle, company, startDate, endDate, achievements:[str]}
    education_entries: List[str],      # free-form strings
    candidate_name: str = "Candidate",
    candidate_email: str = "",
    candidate_phone: str = "",
    candidate_location: str = "",
    target_role: str = "",
    target_company: str = "",
) -> bytes:
    """
    Generates an ATS-optimized PDF CV and returns it as raw bytes.

    Args:
        summary:           Professional summary paragraph.
        skills:            Ordered list of skills (most relevant first).
        experiences:       List of experience dicts from the AI CV content.
        education_entries: List of education strings.
        candidate_name:    Full name of the candidate.
        candidate_email:   Email address.
        candidate_phone:   Phone number.
        candidate_location: City / Country.
        target_role:       Job title being applied to (used in filename hint).
        target_company:    Company being applied to.

    Returns:
        PDF as bytes — ready to stream or save to disk.
    """
    buffer = io.BytesIO()

    doc = SimpleDocTemplate(
        buffer,
        pagesize=letter,
        leftMargin=0.85 * inch,
        rightMargin=0.85 * inch,
        topMargin=0.85 * inch,
        bottomMargin=0.85 * inch,
        title=f"CV — {candidate_name}",
        author=candidate_name,
        subject=f"Application for {target_role} at {target_company}",
    )

    styles = _build_styles()
    story = []

    # ── HEADER ────────────────────────────────────────────────────────────
    story.append(Paragraph(candidate_name or "Candidate", styles["name"]))

    contact_parts = []
    if candidate_email:
        contact_parts.append(candidate_email)
    if candidate_phone:
        contact_parts.append(candidate_phone)
    if candidate_location:
        contact_parts.append(candidate_location)

    if contact_parts:
        story.append(Paragraph(" · ".join(contact_parts), styles["contact"]))

    story.append(Spacer(1, 6))
    story.append(_hr(styles))

    # ── PROFESSIONAL SUMMARY ──────────────────────────────────────────────
    if summary:
        story.append(Paragraph("Professional Summary", styles["section_header"]))
        story.append(_hr(styles))
        story.append(Paragraph(summary, styles["body"]))

    # ── SKILLS ───────────────────────────────────────────────────────────
    if skills:
        story.append(Paragraph("Skills", styles["section_header"]))
        story.append(_hr(styles))
        story.append(Paragraph(", ".join(skills), styles["skills_text"]))

    # ── EXPERIENCE ───────────────────────────────────────────────────────
    if experiences:
        story.append(Paragraph("Professional Experience", styles["section_header"]))
        story.append(_hr(styles))

        for exp in experiences:
            job_title = exp.get("jobTitle") or exp.get("job_title", "")
            company   = exp.get("company", "")
            start     = exp.get("startDate") or exp.get("start_date", "")
            end       = exp.get("endDate") or exp.get("end_date", "")
            bullets   = exp.get("achievements") or exp.get("tailoredBullets") or []

            date_str = f"{start} – {end}" if start or end else ""

            story.append(Paragraph(job_title, styles["job_title"]))
            meta = company
            if date_str:
                meta = f"{company}  |  {date_str}" if company else date_str
            if meta:
                story.append(Paragraph(meta, styles["job_meta"]))

            for bullet in bullets:
                story.append(Paragraph(f"• {bullet}", styles["bullet"]))

            story.append(Spacer(1, 4))

    # ── EDUCATION ────────────────────────────────────────────────────────
    if education_entries:
        story.append(Paragraph("Education", styles["section_header"]))
        story.append(_hr(styles))
        for entry in education_entries:
            if entry.strip():
                story.append(Paragraph(f"• {entry}", styles["bullet"]))

    # ── BUILD ─────────────────────────────────────────────────────────────
    doc.build(story)
    return buffer.getvalue()
