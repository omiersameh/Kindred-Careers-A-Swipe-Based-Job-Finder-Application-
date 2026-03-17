// ============================================================
// DATA: CareerFieldsData
// Premade, fixed catalog of career fields and their
// associated specializations. Users can ONLY choose from
// these lists — no free-text additions allowed.
// ============================================================

class CareerFieldsData {
  // ── Top-level fields (choose up to 3) ─────────────────────
  static const List<Map<String, dynamic>> fields = [
    {'id': 'technology',    'label': 'Technology',            'emoji': '💻'},
    {'id': 'engineering',   'label': 'Engineering',           'emoji': '⚙️'},
    {'id': 'medical',       'label': 'Medical & Health',      'emoji': '🏥'},
    {'id': 'business',      'label': 'Business & Finance',    'emoji': '💼'},
    {'id': 'art',           'label': 'Art & Design',          'emoji': '🎨'},
    {'id': 'media',         'label': 'Media & Communication', 'emoji': '📡'},
    {'id': 'education',     'label': 'Education',             'emoji': '📚'},
    {'id': 'legal',         'label': 'Legal & Law',           'emoji': '⚖️'},
    {'id': 'science',       'label': 'Science & Research',    'emoji': '🔬'},
    {'id': 'trades',        'label': 'Skilled Trades',        'emoji': '🔧'},
    {'id': 'hospitality',   'label': 'Hospitality & Tourism', 'emoji': '🏨'},
    {'id': 'social',        'label': 'Social & Community',    'emoji': '🤝'},
  ];

  // ── Specializations per field ──────────────────────────────
  static const Map<String, List<String>> specializations = {
    'technology': [
      'Software Developer',
      'Mobile App Developer',
      'Web Developer / Frontend',
      'Web Developer / Backend',
      'Full-Stack Developer',
      'DevOps Engineer',
      'Cloud Architect',
      'Cybersecurity Analyst',
      'AI / ML Engineer',
      'Data Scientist',
      'Data Analyst',
      'Database Administrator',
      'QA / Test Engineer',
      'IT Support / Systems Admin',
      'Blockchain Developer',
      'Game Developer',
      'Embedded Systems Engineer',
      'UI / UX Designer (Tech)',
      'Product Manager (Tech)',
      'Technical Writer',
    ],

    'engineering': [
      'Civil Engineer',
      'Structural Engineer',
      'Mechanical Engineer',
      'Electrical Engineer',
      'Electronics Engineer',
      'Chemical Engineer',
      'Petroleum/Oil & Gas Engineer',
      'Aerospace Engineer',
      'Biomedical Engineer',
      'Environmental Engineer',
      'Industrial Engineer',
      'Materials Engineer',
      'Nuclear Engineer',
      'Robotics Engineer',
      'Automation Engineer',
      'Construction Manager',
      'Surveyor',
    ],

    'medical': [
      'General Practitioner (Doctor)',
      'Surgeon',
      'Dentist',
      'Pharmacist',
      'Nurse / Nursing Practitioner',
      'Physiotherapist',
      'Psychologist / Therapist',
      'Radiologist',
      'Cardiologist',
      'Dermatologist',
      'Pediatrician',
      'Optometrist',
      'Nutritionist / Dietitian',
      'Medical Lab Technician',
      'Veterinarian',
      'Public Health Specialist',
      'Healthcare Administrator',
    ],

    'business': [
      'Accountant / Auditor',
      'Financial Analyst',
      'Investment Banker',
      'Business Analyst',
      'Management Consultant',
      'Marketing Manager',
      'Digital Marketing Specialist',
      'SEO / SEM Specialist',
      'Sales Manager',
      'Supply Chain Manager',
      'Operations Manager',
      'HR Manager / Recruiter',
      'Project Manager',
      'Entrepreneur / Startup Founder',
      'E-Commerce Manager',
      'Real Estate Agent',
      'Actuary',
      'Risk Analyst',
    ],

    'art': [
      'Graphic Designer',
      'Illustrator',
      'Photographer',
      'Videographer / Video Editor',
      'Motion Graphics Designer',
      'Animator (2D / 3D)',
      'UI / UX Designer (Creative)',
      'Fashion Designer',
      'Interior Designer',
      'Industrial / Product Designer',
      'Architect (Creative Design)',
      'Music Producer',
      'Sound Engineer',
      'Singer / Performer',
      'Art Director',
      'Tattoo Artist',
      'Jewellery Designer',
      'Sculptor / Fine Artist',
    ],

    'media': [
      'Journalist / Reporter',
      'Content Creator / YouTuber',
      'Social Media Manager',
      'Public Relations Specialist',
      'Broadcaster / TV Presenter',
      'Podcast Producer',
      'Copywriter',
      'Editor (Print / Digital)',
      'Translator / Interpreter',
      'Voice-Over Artist',
      'Event Coordinator',
      'Community Manager',
      'Film Director',
      'Screenwriter',
    ],

    'education': [
      'School Teacher (Primary)',
      'School Teacher (Secondary)',
      'University Lecturer / Professor',
      'Curriculum Developer',
      'Special Education Teacher',
      'Online Course Creator / EdTech',
      'Corporate Trainer',
      'Academic Advisor / Counselor',
      'School Principal / Administrator',
      'Early Childhood Educator',
    ],

    'legal': [
      'Lawyer / Attorney',
      'Corporate Lawyer',
      'Criminal Defense Attorney',
      'Family Law Attorney',
      'Paralegal',
      'Judge / Magistrate',
      'Legal Consultant',
      'Compliance Officer',
      'Intellectual Property Specialist',
      'Notary Public',
    ],

    'science': [
      'Research Scientist',
      'Biologist / Microbiologist',
      'Chemist',
      'Physicist',
      'Geologist / Earth Scientist',
      'Astronomer / Astrophysicist',
      'Marine Biologist',
      'Botanist / Ecologist',
      'Forensic Scientist',
      'Laboratory Technician',
      'Epidemiologist',
      'Neuroscientist',
    ],

    'trades': [
      'Electrician',
      'Plumber',
      'Welder',
      'Carpenter / Joiner',
      'Mechanic (Auto)',
      'HVAC Technician',
      'Machinist / CNC Operator',
      'Construction Worker',
      'Painter / Decorator',
      'Stonemason / Tiler',
      'Roofer',
      'Pipefitter',
    ],

    'hospitality': [
      'Hotel Manager',
      'Chef / Sous-Chef',
      'Restaurant Manager',
      'Barista / Bartender',
      'Tour Guide',
      'Travel Agent',
      'Flight Attendant',
      'Event Planner',
      'Front-of-House Staff',
      'Housekeeper / Hospitality Staff',
    ],

    'social': [
      'Social Worker',
      'Community Organizer',
      'NGO / Nonprofit Manager',
      'Youth Worker',
      'Counselor / Life Coach',
      'Human Rights Advocate',
      'Volunteer Coordinator',
      'Policy Analyst',
      'Urban Planner',
    ],
  };

  /// Returns the list of specializations for a given field ID.
  static List<String> getSpecializations(String fieldId) =>
      specializations[fieldId] ?? [];

  /// Returns the field map for a given field ID.
  static Map<String, dynamic>? getField(String fieldId) {
    try {
      return fields.firstWhere((f) => f['id'] == fieldId);
    } catch (_) {
      return null;
    }
  }
}
