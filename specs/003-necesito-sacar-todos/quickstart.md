# Quickstart: Clean Compilation - Zero Warnings

**Goal**: Eliminate all compilation warnings from LivekitexAgent project in 4-6 weeks while maintaining functionality.

## Prerequisites

- Elixir ~> 1.12, OTP 24+ installed
- LivekitexAgent project cloned and dependencies installed
- Git repository with development branch `003-necesito-sacar-todos`
- All existing tests passing: `mix test`

## Quick Start (Development Setup)

### 1. Check Current Warning Status
```bash
# See all current warnings
mix compile

# Count warnings for baseline
mix compile 2>&1 | grep "warning:" | wc -l
# Expected: ~57 warnings initially
```

### 2. Analyze Warning Categories
```bash
# Get categorized breakdown
mix warnings:analyze

# Expected output:
# Simple: 23 warnings (unused vars, @doc on private funcs)
# API: 18 warnings (deprecated functions, undefined calls)
# Architecture: 16 warnings (type issues, missing deps)
```

### 3. Install Prevention Hooks
```bash
# Install pre-commit hooks to prevent regression
mix warnings:install_hooks

# Verify hook works
git add -A && git commit -m "test commit"
# Should pass if no warnings, fail if warnings present
```

## Implementation Phases

### Week 1-2: Simple Fixes (Low Risk)
**Target**: Eliminate 23 simple warnings

```bash
# Analyze simple category
mix warnings:analyze --category simple

# Apply fixes (with safety checks)
mix warnings:fix simple --dry-run  # Preview changes
mix warnings:fix simple           # Apply changes

# Verify success
mix compile --warnings-as-errors  # Should pass
mix test                         # Should pass (152/152)
```

**Common fixes in this phase**:
- Remove unused variables: `state` → `_state`
- Remove unused module attributes: `@valid_states`
- Remove `@doc` from private functions
- Remove unused aliases

### Week 3-4: API Corrections (Medium Risk)
**Target**: Eliminate 18 API-related warnings

```bash
# Focus on function call corrections
mix warnings:fix api_correction --dry-run
mix warnings:fix api_correction

# Key changes expected:
# - Logger.warn → Logger.warning
# - Fix undefined function calls
# - Correct clause ordering issues
```

### Week 5-6: Architecture Changes (High Risk)
**Target**: Eliminate final 16 architecture warnings

```bash
# Handle complex dependency and type issues
mix warnings:fix architecture --dry-run

# Manual verification required for:
# - GenStage replacement with GenServer
# - :scheduler module alternatives
# - Exception handling improvements
```

## Progress Tracking

### Check Status Anytime
```bash
# Overall progress dashboard
mix warnings:status

# Example output:
# Progress: ████████░░ 80% (46/57 resolved)
# Next: 5 architecture warnings remaining
```

### Validate Changes
```bash
# Full validation suite
mix warnings:test

# Checks:
# ✅ Zero warnings compilation
# ✅ All tests still pass
# ✅ Performance within 5% of baseline
# ✅ Real-time functionality preserved
```

## Common Scenarios

### Scenario 1: Developer Adds New Code
```bash
# Developer commits new feature
git add new_feature.ex
git commit -m "Add new feature"

# Pre-commit hook runs automatically:
# ✅ Pass: Clean compilation → commit allowed
# ❌ Fail: Warnings detected → commit blocked

# If blocked:
mix compile  # See the warnings
# Fix warnings, then commit again
```

### Scenario 2: Emergency Hotfix
```bash
# Critical bug needs immediate fix
git commit --no-verify -m "HOTFIX: Critical bug"

# Follow-up within 24 hours:
git checkout -b fix-warnings-from-hotfix
# Fix any warnings introduced
git commit -m "Fix warnings from emergency hotfix"
```

### Scenario 3: Warning Categories Complete
```bash
# Check if category is fully resolved
mix warnings:status --verbose

# When category shows 100% complete:
# ✅ Simple (23/23) - Week 2 ✅
# Move to next category in timeline
```

## Troubleshooting

### Problem: Tests Fail After Fix
```bash
# Rollback the specific fix
git revert <commit-hash>

# Analyze what broke
mix test --failed
mix warnings:analyze

# Try alternative fix strategy
mix warnings:fix <category> --files specific_file.ex
```

### Problem: Performance Regression
```bash
# Check performance impact
mix warnings:test --coverage

# If >5% compile time increase:
# Review fixes for optimization opportunities
# Consider deferring complex architectural changes
```

### Problem: Blocked by External Dependencies
```bash
# Document blocker
echo "GenStage replacement needed" >> .warnings_progress.json

# Research alternatives
mix hex.search GenServer  # Look for alternatives
# Update research.md with findings
```

### Problem: Pre-commit Hook Bypassed
```bash
# Check for warnings in CI
mix compile --warnings-as-errors

# If CI fails due to warnings:
# 1. Fix warnings immediately
# 2. Review team pre-commit setup
# 3. Update documentation for proper git config
```

## Success Criteria Checklist

### Weekly Milestones
- [ ] Week 1-2: Simple category 100% complete (23/23)
- [ ] Week 3-4: API category 100% complete (18/18)
- [ ] Week 5-6: Architecture category 100% complete (16/16)

### Quality Gates
- [ ] `mix compile` produces zero warnings
- [ ] `mix compile --warnings-as-errors` succeeds
- [ ] All existing tests pass (152/152 expected)
- [ ] Pre-commit hooks installed and working
- [ ] CI/CD pipeline enforces warning-free builds
- [ ] Compilation time increase < 5%

### Documentation Updates
- [ ] Progress tracking in docs/
- [ ] Team onboarding includes hook setup
- [ ] Architecture decisions documented
- [ ] Alternative library choices explained

## Team Collaboration

### For New Team Members
```bash
# Setup development environment
git clone <repo>
cd livekitex_agent
mix deps.get

# Install warning prevention
git config core.hooksPath .git-hooks
mix warnings:install_hooks

# Verify clean development environment
mix compile --warnings-as-errors  # Should pass
mix test                         # Should pass
```

### For Code Reviews
- Focus on functionality rather than style issues
- All PRs should pass warning checks automatically
- Look for inadvertent warning reintroduction
- Verify test coverage maintained

### For CI/CD Integration
- Automated warning detection on every push
- Block merges if warnings introduced
- Performance regression testing
- Documentation auto-updates

## Next Steps

1. **Start immediately**: Begin with Week 1-2 simple fixes
2. **Track progress**: Use `mix warnings:status` daily
3. **Validate frequently**: Run `mix warnings:test` before commits
4. **Collaborate**: Share progress with team weekly
5. **Document blockers**: Update research.md with any issues

**Timeline**: 4-6 weeks to completion
**Success measure**: `mix compile --warnings-as-errors` passes cleanly