#!/bin/bash
# Generates App/Secrets.plist (gitignored, bundled into the app) from .env.local.
# Run after adding/rotating ANTHROPIC_API_KEY in .env.local, then rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .env.local ]]; then
  rm -f App/Secrets.plist
  echo "no .env.local — Secrets.plist removed; app runs on mock intelligence"
  exit 0
fi

ENTRIES=""
COUNT=0
for NAME in ANTHROPIC_API_KEY AZURE_OPENAI_ENDPOINT AZURE_OPENAI_KEY AZURE_OPENAI_DEPLOYMENT ELEVENLABS_API_KEY; do
  VAL=$(grep -E "^${NAME}=" .env.local | head -1 | cut -d= -f2- || true)
  if [[ -n "$VAL" ]]; then
    ENTRIES="${ENTRIES}	<key>${NAME}</key>
	<string>${VAL}</string>
"
    COUNT=$((COUNT + 1))
  fi
done

if [[ $COUNT -eq 0 ]]; then
  rm -f App/Secrets.plist
  echo "no known keys in .env.local — Secrets.plist removed"
  exit 0
fi

cat > App/Secrets.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
${ENTRIES}</dict>
</plist>
EOF
echo "App/Secrets.plist written with ${COUNT} value(s)"
# The plist is bundled via the generated project; regenerate so it's included.
# NOTE: regeneration resets Xcode GUI signing — re-tick "Automatically manage
# signing" before the next device build.
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null && echo "project regenerated (Secrets.plist bundled)"
fi
