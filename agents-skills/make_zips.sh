#!/usr/bin/env bash
# Creates a .zip for each folder in the current directory
set -e

for dir in */; do
    name="${dir%/}"
    rm -f "$name.zip"
    zip -rq "$name.zip" "$name"
    echo "Created $name.zip"
done
