#!/usr/bin/env bash
# Usage: ./NewProject.sh ProjectName   (UpperCamelCase)
set -euo pipefail
projectName="${1:?usage: $0 ProjectName}"
[[ "$projectName" =~ ^[A-Z][A-Za-z0-9]*$ ]] || { echo "Name must be UpperCamelCase (letters/digits)"; exit 1; }
rootDir="$(cd "$(dirname "$0")" && pwd)"
destDir="$rootDir/examples/$projectName"
[[ -e "$destDir" ]] && { echo "$destDir already exists"; exit 1; }
cp -r "$rootDir/Template" "$destDir"
for ext in v cst; do mv "$destDir/Template.$ext" "$destDir/$projectName.$ext"; done
sed -i "s/Template/$projectName/g" "$destDir/$projectName.v" "$destDir/Makefile"
echo "Created $destDir"
