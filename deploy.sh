#!/usr/bin/env bash
set -e

echo "=========================================="
echo "🚀 Building Flutter Web for GitHub Pages..."
echo "=========================================="
flutter build web --release --base-href /collection-app/

echo ""
echo "=========================================="
echo "📦 Deploying build/web to gh-pages branch..."
echo "=========================================="

REPO_REMOTE=$(git config --get remote.origin.url)
DEPLOY_DIR=$(mktemp -d)

# Clone only the latest gh-pages commit
git clone --depth 1 --branch gh-pages "$REPO_REMOTE" "$DEPLOY_DIR"

# Copy newly built assets into the deployment directory
rsync -av --exclude='.git' build/web/ "$DEPLOY_DIR/"

cd "$DEPLOY_DIR"
git config user.name "Atharva Kalhatkar"
git config user.email "atharva@collectionapp.local"

# Clean up heavy symbols files if any
find . -name "*.symbols" -delete

git add -A
if ! git diff --cached --quiet; then
  git commit -m "Deploy Flutter Web to GitHub Pages $(date +'%Y-%m-%d %H:%M:%S')"
  git push origin gh-pages
  echo "✅ Changes pushed successfully."
else
  echo "ℹ️ No changes detected to commit."
fi

rm -rf "$DEPLOY_DIR"

echo ""
echo "=========================================="
echo "✅ DEPLOYMENT FINISHED!"
echo "🌐 Your app is live at:"
echo "👉 https://atharvakalhatkar.github.io/collection-app/"
echo "=========================================="
