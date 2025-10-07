#!/bin/bash

# Diagram Generation Script for LivekitexAgent Documentation
# Converts all Mermaid source files to SVG format

set -e

DOCS_DIR="$(cd "$(dirname "$0")/../docs" && pwd)"
DIAGRAMS_SRC_DIR="$DOCS_DIR/diagrams/src"
DIAGRAMS_OUT_DIR="$DOCS_DIR/diagrams"

echo "🎨 Generating diagrams for LivekitexAgent documentation..."
echo "Source directory: $DIAGRAMS_SRC_DIR"
echo "Output directory: $DIAGRAMS_OUT_DIR"

# Check if Mermaid CLI is installed
if ! command -v mmdc &> /dev/null; then
    echo "❌ Mermaid CLI (mmdc) not found."
    echo "📦 Install with: npm install -g @mermaid-js/mermaid-cli"
    echo "⚠️  Continuing without diagram generation..."
    exit 0
fi

# Create output directory if it doesn't exist
mkdir -p "$DIAGRAMS_OUT_DIR"

# Counter for processed files
processed=0
total=0

# Count total .mmd files
if [[ -d "$DIAGRAMS_SRC_DIR" ]]; then
    total=$(find "$DIAGRAMS_SRC_DIR" -name "*.mmd" -type f | wc -l)
fi

echo "📊 Found $total Mermaid files to process"

# Process all .mmd files in src directory
if [[ -d "$DIAGRAMS_SRC_DIR" ]]; then
    while IFS= read -r -d '' mmd_file; do
        filename=$(basename "$mmd_file" .mmd)
        output_file="$DIAGRAMS_OUT_DIR/${filename}.svg"

        echo "🔄 Processing: $filename.mmd → $filename.svg"

        # Generate SVG with Mermaid CLI
        if mmdc -i "$mmd_file" -o "$output_file" -t neutral -b white 2>/dev/null; then
            echo "✅ Generated: $output_file"
            ((processed++))
        else
            echo "❌ Failed to generate: $filename.svg"
        fi

    done < <(find "$DIAGRAMS_SRC_DIR" -name "*.mmd" -type f -print0)
fi

echo ""
echo "🎉 Diagram generation complete!"
echo "📈 Processed: $processed/$total files"

if [[ $processed -gt 0 ]]; then
    echo "📁 Generated diagrams in: $DIAGRAMS_OUT_DIR"
    echo "📝 You can now reference these SVG files in your documentation"
else
    echo "ℹ️  No diagrams were generated. Create .mmd files in $DIAGRAMS_SRC_DIR first."
fi