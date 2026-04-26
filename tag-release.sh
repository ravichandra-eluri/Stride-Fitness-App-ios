#!/bin/bash
# Run this after every TestFlight or App Store archive + upload.
# It reads the build number from Xcode and creates + pushes the git tag.

BUILD=$(grep -m1 "CURRENT_PROJECT_VERSION" Stride/Stride.xcodeproj/project.pbxproj | tr -d ' ;' | cut -d= -f2)
VERSION=$(grep -m1 "MARKETING_VERSION" Stride/Stride.xcodeproj/project.pbxproj | tr -d ' ;' | cut -d= -f2)
TAG="v${VERSION}-build${BUILD}"

echo "Tagging release: $TAG"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists. Bump the build number first."
  exit 1
fi

git tag "$TAG"
git push origin "$TAG"

echo "Done — $TAG pushed to GitHub."
