# Data Model: Clean Compilation - Zero Warnings

**Phase**: 1 (Design) | **Date**: October 7, 2025 | **Feature**: 003-necesito-sacar-todos

## Overview

This feature focuses on compilation process improvement rather than data modeling. The primary "entities" are warning categories and fix strategies rather than traditional data structures.

## Warning Classification Model

### WarningCategory
**Purpose**: Categorize compilation warnings by fix complexity and risk level
**Lifecycle**: Static classification used throughout fix process

**Attributes**:
- `category_id`: Atom (`:simple`, `:api_correction`, `:architecture`)
- `description`: String - Human-readable category description
- `risk_level`: Atom (`:low`, `:medium`, `:high`)
- `estimated_effort`: Integer - Hours to complete category
- `timeline_week`: Integer - Target week for completion (1-6)

**Validation Rules**:
- category_id must be unique across system
- risk_level must correlate with timeline (low risk = early weeks)
- estimated_effort must be positive integer

### WarningInstance
**Purpose**: Individual warning occurrences in compilation output
**Lifecycle**: Created during analysis, resolved during fix implementation

**Attributes**:
- `file_path`: String - Relative path from project root
- `line_number`: Integer - Line where warning occurs
- `warning_type`: String - Elixir compiler warning type
- `message`: String - Full warning message from compiler
- `category`: Reference to WarningCategory
- `status`: Atom (`:identified`, `:in_progress`, `:resolved`, `:blocked`)
- `fix_approach`: String - Planned resolution strategy

**Validation Rules**:
- file_path must exist in lib/ directory
- line_number must be positive
- status transitions: identified → in_progress → resolved (or blocked)

**Relationships**:
- belongs_to WarningCategory
- associated with SourceFile

### SourceFile
**Purpose**: Elixir source files containing warnings
**Lifecycle**: Static - represents existing codebase structure

**Attributes**:
- `file_path`: String - Relative path from project root
- `module_name`: String - Elixir module name
- `warning_count`: Integer - Number of warnings in file
- `fix_priority`: Integer - Order for addressing (1 = highest)
- `requires_dependency_change`: Boolean - Whether fixes need new dependencies
- `test_file_path`: String - Associated test file location

**Validation Rules**:
- file_path must have .ex extension
- module_name must be valid Elixir module format
- warning_count must be non-negative
- test_file_path should exist if provided

**Relationships**:
- has_many WarningInstance
- associated with TestFile

## Fix Strategy Model

### FixStrategy
**Purpose**: Approaches for resolving specific warning types
**Lifecycle**: Template patterns applied to WarningInstance entities

**Attributes**:
- `strategy_id`: String - Unique strategy identifier
- `warning_pattern`: String - Regex matching warning messages
- `approach`: String - Step-by-step fix instructions
- `risk_assessment`: Atom (`:safe`, `:review_required`, `:breaking_change`)
- `validation_steps`: List of strings - How to verify fix correctness

**Common Strategies**:
```elixir
# Unused variable strategy
%FixStrategy{
  strategy_id: "unused_variable",
  warning_pattern: ~r/variable "(.+)" is unused/,
  approach: "Prefix variable name with underscore or remove if truly unused",
  risk_assessment: :safe,
  validation_steps: ["Verify tests pass", "Check function still works as expected"]
}

# Undefined function strategy
%FixStrategy{
  strategy_id: "undefined_function",
  warning_pattern: ~r/(.+) is undefined/,
  approach: "Verify correct module name, add import if needed, or fix function name",
  risk_assessment: :review_required,
  validation_steps: ["Confirm function exists", "Test functionality", "Check all callers"]
}
```

## Progress Tracking Model

### FixProgress
**Purpose**: Track implementation progress across timeline
**Lifecycle**: Updated throughout 4-6 week implementation period

**Attributes**:
- `week_number`: Integer (1-6)
- `category`: Reference to WarningCategory
- `planned_fixes`: Integer - Expected fixes for this week/category
- `completed_fixes`: Integer - Actually completed fixes
- `blocked_fixes`: Integer - Fixes that couldn't be completed
- `notes`: String - Progress notes and blockers
- `test_pass_rate`: Float - Percentage of tests still passing

**Validation Rules**:
- completed_fixes ≤ planned_fixes + buffer (20%)
- test_pass_rate must be 100.0 for deployment
- week_number must be 1-6

## Pre-commit Hook Model

### HookConfiguration
**Purpose**: Pre-commit hook setup and validation
**Lifecycle**: One-time setup, ongoing validation

**Attributes**:
- `hook_path`: String - Path to git hook script
- `enabled`: Boolean - Whether hook is active
- `check_command`: String - Command executed by hook
- `bypass_allowed`: Boolean - Whether emergency bypass is possible
- `last_validation`: DateTime - When hook was last tested

**Validation Rules**:
- hook_path must be executable file
- check_command must exit 0 for success, non-0 for failure
- last_validation should be within 24 hours for active development

## State Transitions

### Warning Resolution Flow
```
WarningInstance.status transitions:
:identified → :in_progress → :resolved
                ↓
           :blocked (requires alternative approach)
```

### Category Completion Flow
```
WarningCategory progress:
Week 1-2: :simple category → :completed
Week 3-4: :api_correction category → :completed
Week 5-6: :architecture category → :completed
```

## Data Validation

### Compilation Success Verification
- All WarningInstance entities must have status = :resolved
- `mix compile --warnings-as-errors` must exit with code 0
- Test suite pass rate must remain 100%

### Progress Metrics
- Weekly completion tracking against timeline
- Risk mitigation effectiveness
- Regression prevention via pre-commit hooks

## Integration Points

### With Elixir Compiler
- Warning extraction from `mix compile` output
- Validation of fixes via recompilation
- Performance impact measurement

### With Git Workflow
- Pre-commit hook integration
- Branch protection until warnings resolved
- Commit message standards for fix tracking

### With CI/CD Pipeline
- Automated warning detection
- Regression testing for new warnings
- Performance benchmarking post-fixes