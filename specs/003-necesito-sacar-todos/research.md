# Research: Clean Compilation - Zero Warnings

**Phase**: 0 (Research) | **Date**: October 7, 2025 | **Feature**: 003-necesito-sacar-todos

## Research Overview

Investigation of warning resolution strategies, Elixir best practices, and tooling for preventing regression.

## Warning Categories Analysis

### Decision: Categorize warnings by fix complexity and impact
**Rationale**: Enables prioritized incremental fixing strategy aligned with 4-6 week timeline
**Alternatives considered**: Fix all at once (rejected: too risky), fix randomly (rejected: no clear progress)

#### Category A: Simple Variable/Attribute Fixes (Low Risk)
- Unused variables → prefix with underscore or remove
- Unused module attributes → remove or use
- Unused aliases → remove
- Private function @doc → remove @doc annotations

**Timeline**: Week 1-2 | **Files**: ~15 files | **Risk**: Very Low

#### Category B: Function/API Corrections (Medium Risk)
- Deprecated Logger.warn → Logger.warning
- Undefined functions → correct function names or add imports
- Default clause warnings → reorder or combine clauses

**Timeline**: Week 2-4 | **Files**: ~8 files | **Risk**: Medium

#### Category C: Type System & Architecture (High Risk)
- Exception field access → use Exception.message/1 or specific exception types
- Undefined modules (GenStage, :scheduler) → evaluate alternatives or add dependencies
- Bitwise deprecation → import Bitwise instead of use

**Timeline**: Week 3-6 | **Files**: ~5 files | **Risk**: High

## Dependency Resolution Strategy

### Decision: Evaluate and replace problematic dependencies
**Rationale**: Per clarification, find alternative libraries rather than suppress warnings
**Alternatives considered**: Suppress warnings (rejected per clarification), patch upstream (rejected: too slow)

#### GenStage Issues
- Current: Undefined GenStage module in stream_manager.ex
- Alternative 1: Add gen_stage dependency
- Alternative 2: Replace with standard GenServer pattern
- **Recommended**: Alternative 2 for minimal dependencies

#### :scheduler Module Issues
- Current: Undefined :scheduler in performance_optimizer.ex
- Alternative 1: Use :erlang.statistics/1 for CPU metrics
- Alternative 2: Remove scheduler utilization feature
- **Recommended**: Alternative 1 for equivalent functionality

## Pre-commit Hook Implementation

### Decision: Git pre-commit hooks with mix compile --warnings-as-errors
**Rationale**: Per clarification, block commits with new warnings at source control level
**Alternatives considered**: CI-only checks (rejected: allows bad commits), IDE plugins (rejected: not universal)

#### Implementation Approach
```bash
#!/bin/sh
# .git-hooks/pre-commit
cd "$(git rev-parse --show-toplevel)"
if ! mix compile --warnings-as-errors >/dev/null 2>&1; then
  echo "❌ Commit blocked: Compilation warnings detected"
  echo "Run 'mix compile' to see warnings, fix them, then commit again"
  exit 1
fi
echo "✅ Clean compilation verified"
```

#### Installation Process
- Script placement in .git-hooks/ directory
- Documentation in README for contributor setup
- CI verification that hooks are properly configured

## Testing Strategy

### Decision: Validate fixes preserve functionality while eliminating warnings
**Rationale**: Must ensure no breaking changes per FR-010, FR-011, FR-012
**Alternatives considered**: Skip testing (rejected: too risky), manual testing only (rejected: not scalable)

#### Test Categories
1. **Regression Tests**: All existing tests must continue passing
2. **Compilation Tests**: New tests for zero-warning compilation
3. **Integration Tests**: Real-time audio/video functionality preserved
4. **Performance Tests**: Compilation time impact < 5%

#### Validation Commands
```bash
# Before each fix
mix test --cover
mix compile --warnings-as-errors

# After each fix
mix test --cover
mix compile --warnings-as-errors
mix dialyzer # if type changes made
```

## Risk Mitigation

### Decision: Incremental approach with rollback capability
**Rationale**: Minimize risk of breaking changes while making steady progress
**Alternatives considered**: Big bang approach (rejected: too risky), feature flags (rejected: overkill)

#### Rollback Strategy
- Each category fixed in separate commits
- Git branch protection until tests pass
- Ability to revert individual fix categories independently

#### Monitoring Points
- Test suite pass rate (must remain 100%)
- Compilation time (must stay < 5% increase)
- Real-time performance (audio/video latency unchanged)
- Memory usage (no significant increases)

## Timeline & Priorities

### Decision: High-impact, low-risk first; complex changes last
**Rationale**: Delivers early value while building confidence for riskier changes
**Alternatives considered**: Alphabetical order (rejected: no strategic benefit), random (rejected: unpredictable)

#### Week 1-2: Category A (Simple Fixes)
- All unused variable/attribute/alias warnings
- Private function @doc removals
- **Deliverable**: ~75% warning reduction, no functional risk

#### Week 3-4: Category B (API Corrections)
- Logger function updates
- Function name corrections
- Clause reordering
- **Deliverable**: ~90% warning reduction, medium risk managed

#### Week 5-6: Category C (Architecture)
- Exception handling improvements
- Dependency replacements
- Module import corrections
- **Deliverable**: 100% warning elimination, highest value

## Tools & Automation

### Decision: Leverage existing Elixir tooling with custom validation
**Rationale**: Use proven tools rather than reinvent; add specific validation for this project
**Alternatives considered**: Custom linting tools (rejected: maintenance burden), manual process (rejected: error-prone)

#### Development Tools
- `mix compile --warnings-as-errors` for validation
- `mix format` for consistent style post-fix
- `mix dialyzer` for type checking after changes
- `mix credo` for additional static analysis

#### CI Integration
- Warning checks in pull request validation
- Performance regression testing
- Test coverage maintenance verification
- Documentation updates for changed APIs