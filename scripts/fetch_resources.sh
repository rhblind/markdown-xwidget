#!/bin/bash

# Library versions
HIGHLIGHTJS_VERSION="11.11.1"
MERMAID_VERSION="11"
MATHJAX_VERSION="4"

tempdir=$(mktemp -d)

echo "Fetching highlight.js CSS themes from cdnjs API..."

# Get list of CSS files from cdnjs API and download them
curl -sL "https://api.cdnjs.com/libraries/highlight.js/${HIGHLIGHTJS_VERSION}?fields=files" | \
python3 -c "
import json, sys, subprocess, os

data = json.load(sys.stdin)
css_files = [f for f in data['files'] if f.startswith('styles/') and f.endswith('.min.css')]

base_url = 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/${HIGHLIGHTJS_VERSION}/'

for f in css_files:
    # Remove 'styles/' prefix and '.min.css' suffix, then add .css
    rel_path = f.replace('styles/', '').replace('.min.css', '.css')
    local_path = 'resources/highlight_css/' + rel_path
    os.makedirs(os.path.dirname(local_path) if os.path.dirname(local_path) else 'resources/highlight_css', exist_ok=True)
    url = base_url + f
    subprocess.run(['curl', '-sL', url, '-o', local_path], check=True)

print(f'Downloaded {len(css_files)} CSS files')
"

echo "Downloading highlight.min.js from CDN"

curl -sL \
    "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/${HIGHLIGHTJS_VERSION}/highlight.min.js" \
    > resources/highlight.min.js

echo "Fetching mermaid js"

curl -sL \
     "https://cdn.jsdelivr.net/npm/mermaid@${MERMAID_VERSION}/dist/mermaid.min.js" \
     > resources/mermaid.min.js

echo "Fetching MathJax js"

curl -sL \
     "https://cdn.jsdelivr.net/npm/mathjax@${MATHJAX_VERSION}/tex-mml-chtml.js" \
     > resources/tex-mml-chtml.js

echo "Done!"
