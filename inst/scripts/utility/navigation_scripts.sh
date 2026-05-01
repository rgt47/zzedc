#!/bin/bash
# Navigation Links Generator
# Creates one-letter symbolic links for quick directory navigation
# Usage: ./navigation_scripts.sh [--clean | -c]
#   --clean | -c : Remove all navigation links

# Function to clean up navigation links
cleanup_links() {
    echo "Removing navigation links..."
    rm -f a n f t s m e o c p
    echo "All navigation links removed."
    exit 0
}

# Check for cleanup flag
if [[ "$1" == "--clean" || "$1" == "-c" ]]; then
    cleanup_links
fi

echo "Creating navigation symbolic links..."

# Remove existing navigation links first
rm -f a n f t s m e o c p

# Create symbolic links for existing directories
if [[ -d "./data" ]]; then
    ln -sf "./data" a
    echo "Created: a → ./data"
fi

if [[ -d "./analysis" ]]; then
    ln -sf "./analysis" n
    echo "Created: n → ./analysis"
fi

if [[ -d "./analysis/figures" ]]; then
    ln -sf "./analysis/figures" f
    echo "Created: f → ./analysis/figures"
fi

if [[ -d "./analysis/tables" ]]; then
    ln -sf "./analysis/tables" t
    echo "Created: t → ./analysis/tables"
fi

if [[ -d "./scripts" ]]; then
    ln -sf "./scripts" s
    echo "Created: s → ./scripts"
fi

if [[ -d "./man" ]]; then
    ln -sf "./man" m
    echo "Created: m → ./man"
fi

if [[ -d "./tests" ]]; then
    ln -sf "./tests" e
    echo "Created: e → ./tests"
fi

if [[ -d "./docs" ]]; then
    ln -sf "./docs" o
    echo "Created: o → ./docs"
fi

if [[ -d "./archive" ]]; then
    ln -sf "./archive" c
    echo "Created: c → ./archive"
fi

if [[ -d "./analysis/report" ]]; then
    ln -sf "./analysis/report" p
    echo "Created: p → ./analysis/report"
fi

echo "Navigation symbolic links created successfully!"
echo "Usage: cd a (data), cd n (analysis), cd p (report), etc."
echo "To remove all links: ./navigation_scripts.sh --clean"
