import json
import os
import shutil
import random
import glob

members = [1, 2, 3]
base_dir = 'e:/Graduation Project/kindred_careers'
banners_dir = os.path.join(base_dir, 'assets/images/banners')
mock_banners_dir = os.path.join(base_dir, 'assets/mock_banners')

if not os.path.exists(mock_banners_dir):
    os.makedirs(mock_banners_dir)

def find_image(field, spec):
    field_dirs = [d for d in os.listdir(banners_dir) if os.path.isdir(os.path.join(banners_dir, d))]
    matched_field = None
    for fd in field_dirs:
        if field.lower() in fd.lower() or fd.lower() in field.lower():
            matched_field = fd
            break
            
    if not matched_field:
        return None
        
    field_path = os.path.join(banners_dir, matched_field)
    
    spec_dirs = [d for d in os.listdir(field_path) if os.path.isdir(os.path.join(field_path, d))]
    matched_spec = None
    clean_spec = spec.lower().replace('/', '').replace('&', '').replace('and', '').replace(' ', '')
    for sd in spec_dirs:
        clean_sd = sd.lower().replace('/', '').replace('&', '').replace('and', '').replace(' ', '')
        if clean_spec in clean_sd or clean_sd in clean_spec:
            matched_spec = sd
            break
            
    images = []
    if matched_spec:
        images = glob.glob(os.path.join(field_path, matched_spec, '*.*'))
        images = [f for f in images if os.path.isfile(f) and not f.endswith('.json')]
        
    if not images:
        # Fallback
        for d in spec_dirs:
            images.extend(glob.glob(os.path.join(field_path, d, '*.*')))
        images = [f for f in images if os.path.isfile(f) and not f.endswith('.json')]
            
    if images:
        return random.choice(images)
    return None

for m in members:
    json_path = os.path.join(base_dir, f'assets/mock_data/member{m}_jobs.json')
    if not os.path.exists(json_path): continue
    
    with open(json_path, 'r', encoding='utf-8') as f:
        jobs = json.load(f)
        
    for i, job in enumerate(jobs):
        field = job.get('careerField', '')
        spec = job.get('specialization', '')
        
        matched_image = find_image(field, spec)
                
        if matched_image:
            ext = os.path.splitext(matched_image)[1]
            new_name = f'm{m}_job{i}{ext}'
            new_path = os.path.join(mock_banners_dir, new_name)
            shutil.copy2(matched_image, new_path)
            
            job['imageUrl'] = f'assets/mock_banners/{new_name}'
            print(f'Copied banner for m{m}_job{i} ({field}/{spec})')
        else:
            print(f'NO BANNER FOUND for m{m}_job{i} ({field}/{spec})')
            job['imageUrl'] = ''
            
    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(jobs, f, indent=2, ensure_ascii=False)

print('Done!')
