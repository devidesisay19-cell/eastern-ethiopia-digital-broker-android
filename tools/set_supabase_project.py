#!/usr/bin/env python3
"""Switch the app to another Supabase project in one go.
Usage:  python3 tools/set_supabase_project.py https://YOURREF.supabase.co sb_publishable_xxxxx
Replaces the project URL + publishable key in every page of app/src/main/assets/web.
(Android Studio alternative: Edit > Find > Replace in Files, replace the old URL and the old key.)"""
import glob, re, sys
if len(sys.argv) != 3 or not sys.argv[1].startswith('https://') or not sys.argv[2].startswith(('sb_publishable_', 'eyJ')):
    sys.exit(__doc__)
url, key = sys.argv[1].rstrip('/'), sys.argv[2]
n = 0
for f in glob.glob('app/src/main/assets/web/*.html') + glob.glob('app/src/main/assets/web/*.js'):
    s = open(f, encoding='utf-8').read()
    t = re.sub(r'https://[a-z0-9]{15,25}\.supabase\.co', url, s)
    t = re.sub(r'sb_publishable_[A-Za-z0-9_\-]+', key, t)
    if t != s:
        open(f, 'w', encoding='utf-8').write(t); n += 1
print('updated', n, 'files ->', url)
