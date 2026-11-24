#!/usr/bin/env python3
"""Render the public policy pages from the same offline content used in-app."""
import html
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
data = json.loads((root / 'assets/legal/policies.json').read_text())
e = html.escape
for kind in ('privacy', 'terms'):
    policy = data[kind]
    sections = ''.join('<h2>'+e(section['title'])+'</h2><p>'+e(section['body'])+'</p>' for section in policy['sections'])
    document = f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{e(policy["title"])} | SalonFe</title><link rel="stylesheet" href="/styles.css"></head><body><header><nav class="nav"><a class="brand" href="/">SalonFe</a></nav></header><main><h1>{e(policy["title"])}</h1><p>Last updated: {e(data["updated"])}</p>{sections}</main><footer><span>Contact +91 89996 08278</span><a href="/privacy">Privacy Policy</a><a href="/terms">Terms &amp; Conditions</a><a href="/support">Support</a></footer></body></html>\n'
    (root / 'hosting' / (kind + '.html')).write_text(document)
    if kind == 'privacy':
        (root / 'privacy_policy.html').write_text(document)

# Keep the repository policy copy aligned with the in-app and hosted policy.
policy = data['privacy']
(root / 'PRIVACY_POLICY.md').write_text(
    '# Privacy Policy — SalonFe\n\nLast updated: ' + data['updated'] + '\n\n' +
    '\n\n'.join('## ' + section['title'] + '\n\n' + section['body'] for section in policy['sections']) + '\n'
)
