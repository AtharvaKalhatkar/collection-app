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

# Navigate into compiled web directory
cd build/web

# Initialize a clean git tree for the deployment branch
rm -rf .git
git init
git branch -M gh-pages
git config user.name "Atharva Kalhatkar"
git config user.email "atharva@collectionapp.local"

# Add and commit all web assets
git add -A
git commit -m "Deploy Flutter Web to GitHub Pages $(date +'%Y-%m-%d %H:%M:%S')"

# Push to gh-pages branch
git remote add origin https://github.com/AtharvaKalhatkar/collection-app.git
git push -f origin gh-pages

echo ""
echo "=========================================="
echo "✅ DEPLOYMENT FINISHED!"
echo "🌐 Your app is live at:"
echo "👉 https://atharvakalhatkar.github.io/collection-app/"
echo "=========================================="
