#!/bin/bash

# Documentation Validation Script for LivekitexAgent
# Validates completeness and quality of flow documentation

set -e

DOCS_DIR="$(cd "$(dirname "$0")/../docs" && pwd)"
FLOW_DOC="$DOCS_DIR/flow.md"
SPECS_DIR="$(cd "$(dirname "$0")/../specs/002-crear-un-flow" && pwd)"

echo "🔍 Validating LivekitexAgent documentation..."
echo "Documentation directory: $DOCS_DIR"

# Initialize counters
warnings=0
errors=0

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Helper functions
warn() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}"
    ((warnings++))
}

error() {
    echo -e "${RED}❌ ERROR: $1${NC}"
    ((errors++))
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

info() {
    echo "ℹ️  $1"
}

# Check if main flow.md exists
if [[ ! -f "$FLOW_DOC" ]]; then
    error "Main flow.md file not found at $FLOW_DOC"
else
    success "Main flow.md file found"
fi

# Check functional requirements coverage (FR-001 through FR-015)
if [[ -f "$FLOW_DOC" ]]; then
    info "Checking functional requirements coverage..."

    for fr in {001..015}; do
        if grep -q "FR-${fr}" "$FLOW_DOC"; then
            success "FR-${fr} documented"
        else
            warn "FR-${fr} not found in documentation"
        fi
    done
fi

# Check required sections exist
if [[ -f "$FLOW_DOC" ]]; then
    info "Checking required sections..."

    declare -A required_sections=(
        ["System Overview"]="High-level architecture section"
        ["Agent Lifecycle"]="Agent initialization and states"
        ["Session Management"]="Real-time conversation handling"
        ["Performance Characteristics"]="Metrics and benchmarks"
        ["Integration Patterns"]="External service integration"
    )

    for section in "${!required_sections[@]}"; do
        if grep -qi "$section" "$FLOW_DOC"; then
            success "Section found: $section"
        else
            warn "Missing section: $section - ${required_sections[$section]}"
        fi
    done
fi

# Check diagram files exist
info "Checking diagram availability..."
diagram_dir="$DOCS_DIR/diagrams"
if [[ -d "$diagram_dir" ]]; then
    svg_count=$(find "$diagram_dir" -name "*.svg" -type f | wc -l)
    mmd_count=$(find "$DOCS_DIR/diagrams/src" -name "*.mmd" -type f 2>/dev/null | wc -l)

    info "Found $svg_count SVG diagrams and $mmd_count Mermaid source files"

    if [[ $svg_count -eq 0 ]]; then
        warn "No SVG diagrams found. Run scripts/generate-diagrams.sh"
    fi
else
    warn "Diagrams directory not found"
fi

# Check appendices exist
info "Checking technical appendices..."
appendices_dir="$DOCS_DIR/appendices"
if [[ -d "$appendices_dir" ]]; then
    appendix_count=$(find "$appendices_dir" -name "*.md" -type f | wc -l)
    info "Found $appendix_count appendix files"

    if [[ $appendix_count -eq 0 ]]; then
        warn "No appendix files found"
    fi
else
    warn "Appendices directory not found"
fi

# Check performance documentation
info "Checking performance documentation..."
perf_dir="$DOCS_DIR/performance"
if [[ -d "$perf_dir" ]]; then
    perf_count=$(find "$perf_dir" -name "*.md" -type f | wc -l)
    info "Found $perf_count performance documentation files"

    if [[ $perf_count -eq 0 ]]; then
        warn "No performance documentation files found"
    fi
else
    warn "Performance directory not found"
fi

# Check word count for 30-minute reading goal
if [[ -f "$FLOW_DOC" ]]; then
    word_count=$(wc -w < "$FLOW_DOC")
    # Average reading speed: 200-250 words per minute
    # 30 minutes = 6000-7500 words max
    info "Documentation word count: $word_count words"

    if [[ $word_count -gt 7500 ]]; then
        warn "Documentation may be too long for 30-minute reading goal (>7500 words)"
    elif [[ $word_count -lt 2000 ]]; then
        warn "Documentation may be too brief for comprehensive coverage (<2000 words)"
    else
        success "Word count appropriate for 30-minute reading goal"
    fi
fi

# Summary
echo ""
echo "📊 Validation Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $errors -eq 0 && $warnings -eq 0 ]]; then
    success "All validation checks passed!"
    echo "🎉 Documentation is ready for review"
    exit 0
elif [[ $errors -eq 0 ]]; then
    echo -e "${YELLOW}⚠️  $warnings warning(s) found${NC}"
    echo "📝 Documentation is mostly complete but could be improved"
    exit 1
else
    echo -e "${RED}❌ $errors error(s) and $warnings warning(s) found${NC}"
    echo "🔧 Please fix the errors before proceeding"
    exit 2
fi