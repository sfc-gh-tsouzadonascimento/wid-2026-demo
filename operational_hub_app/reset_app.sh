#!/usr/bin/env bash
# Reset FrostBank Intelligence Hub to pre-demo state.
# Removes Q&A question cards so they can be added live in Scene 3 step 14.
# Run this before each demo, after reset_demo.sql.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Resetting app to pre-demo state (no Q&A cards)..."

# Empty the QUESTIONS array in App.jsx
python3 -c "
import re, pathlib
p = pathlib.Path('$DIR/frontend/src/App.jsx')
t = p.read_text()
t = re.sub(r'const QUESTIONS = \[.*?\]', 'const QUESTIONS = []', t, flags=re.DOTALL)
p.write_text(t)
print('  App.jsx: QUESTIONS = []')
"

# Empty the ALLOWED_QUESTIONS list in app.py
python3 -c "
import re, pathlib
p = pathlib.Path('$DIR/app.py')
t = p.read_text()
t = re.sub(r'ALLOWED_QUESTIONS = \[.*?\]', 'ALLOWED_QUESTIONS = []', t, flags=re.DOTALL)
p.write_text(t)
print('  app.py:  ALLOWED_QUESTIONS = []')
"

# Rebuild frontend
echo "Rebuilding frontend..."
npm --prefix "$DIR/frontend" run build

echo "Done. App is in pre-demo state (dashboard only, no Q&A cards)."
echo "Run ./build.sh to restart the server."
