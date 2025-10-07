# CLI Contracts: Clean Compilation

## Warning Analysis Commands

### `mix warnings:analyze`
**Purpose**: Analyze current warnings and categorize by fix strategy

```bash
# Command usage
mix warnings:analyze [--format json|table] [--category simple|api|architecture]

# Success response (table format - default)
Category     | Count | Files | Risk  | Timeline
-------------|-------|-------|-------|----------
Simple       | 23    | 12    | Low   | Week 1-2
API          | 18    | 8     | Med   | Week 3-4
Architecture | 16    | 5     | High  | Week 5-6
Total        | 57    | 25    | -     | 6 weeks

# Success response (JSON format)
{
  "categories": [
    {
      "name": "simple",
      "count": 23,
      "files": 12,
      "risk": "low",
      "timeline": "week_1_2",
      "warnings": [
        {
          "file": "lib/livekitex_agent/agent.ex",
          "line": 19,
          "type": "unused_module_attribute",
          "message": "module attribute @valid_states was set but never used",
          "fix_strategy": "remove_unused_attribute"
        }
      ]
    }
  ],
  "summary": {
    "total_warnings": 57,
    "affected_files": 25,
    "estimated_weeks": 6
  }
}

# Error cases
Exit Code 1: No warnings found (nothing to analyze)
Exit Code 2: Unable to compile project for analysis
Exit Code 3: Invalid category filter specified
```

### `mix warnings:fix`
**Purpose**: Apply fixes for specific warning category

```bash
# Command usage
mix warnings:fix <category> [--dry-run] [--files file1,file2]

# Success response
✅ Fixed 12 warnings in category 'simple'
📁 Modified files:
   - lib/livekitex_agent/agent.ex (1 fix)
   - lib/livekitex_agent/health_server.ex (8 fixes)
   - lib/livekitex_agent/function_tool.ex (3 fixes)

🧪 Running tests...
✅ All tests passed (152/152)

⚡ Compiling with --warnings-as-errors...
✅ Clean compilation verified

# Dry-run response (--dry-run flag)
[DRY RUN] Would fix 12 warnings in category 'simple'
[DRY RUN] Would modify:
   - lib/livekitex_agent/agent.ex: Remove unused @valid_states
   - lib/livekitex_agent/health_server.ex: Remove @doc from private functions
   - lib/livekitex_agent/function_tool.ex: Prefix unused variables with _

# Error cases
Exit Code 1: Invalid category specified
Exit Code 2: Fixes would break tests
Exit Code 3: No warnings found in category
Exit Code 4: File modification permission denied
```

### `mix warnings:status`
**Purpose**: Show progress toward zero warnings goal

```bash
# Command usage
mix warnings:status [--verbose]

# Success response
📊 Warning Resolution Status

Progress: ████████░░ 80% (46/57 resolved)

By Category:
✅ Simple (23/23) - Completed Week 2
🔄 API (18/18) - In Progress Week 4
⏳ Architecture (5/16) - Planned Week 5-6

Recent Activity:
- 2025-10-07 14:30: Fixed undefined Logger functions (5 warnings)
- 2025-10-07 12:15: Removed unused variables (8 warnings)
- 2025-10-06 16:45: Fixed clause ordering (3 warnings)

Blockers:
❌ GenStage dependency needs evaluation (2 warnings)
❌ :scheduler module replacement pending (1 warning)

# Verbose response includes per-file breakdown
--verbose flag adds:
📁 File Details:
   lib/livekitex_agent/agent.ex: ✅ 1/1 resolved
   lib/livekitex_agent/cli.ex: 🔄 8/12 resolved
   lib/livekitex_agent/media/audio_processor.ex: ⏳ 0/6 planned

# Error cases
Exit Code 1: Project compilation failed - cannot assess status
```

## Pre-commit Hook Contracts

### `mix warnings:install_hooks`
**Purpose**: Install Git pre-commit hooks for warning prevention

```bash
# Command usage
mix warnings:install_hooks [--force]

# Success response
🔧 Installing pre-commit hooks...
✅ Created .git-hooks/pre-commit
✅ Made hook executable (chmod +x)
✅ Updated git config hooks.hooksPath=.git-hooks
🧪 Testing hook with current codebase...
✅ Hook test passed - no warnings detected

📖 Team Setup Instructions:
   All developers should run: git config core.hooksPath .git-hooks

# Error cases
Exit Code 1: Not a git repository
Exit Code 2: Hooks already installed (use --force to overwrite)
Exit Code 3: Unable to write hook files (permissions)
Exit Code 4: Hook test failed - warnings still present
```

### Hook Execution Contract
**Purpose**: Define pre-commit hook behavior

```bash
# Pre-commit hook execution
# Location: .git-hooks/pre-commit

# Success case (allows commit)
✅ Clean compilation verified
[commit proceeds normally]

# Failure case (blocks commit)
❌ Commit blocked: Compilation warnings detected
Run 'mix compile' to see warnings, fix them, then commit again

Details:
- lib/new_module.ex:15: variable "unused_var" is unused
- lib/new_module.ex:23: Logger.warn/1 is deprecated

Exit Code: 1 (blocks commit)

# Emergency bypass (documentation only)
# Override: git commit --no-verify
# Use only for emergency hotfixes - warnings must be fixed in follow-up commit
```

## Test & Validation Contracts

### `mix warnings:test`
**Purpose**: Validate that warning fixes don't break functionality

```bash
# Command usage
mix warnings:test [--category category] [--coverage]

# Success response
🧪 Running warning fix validation tests...

✅ Compilation Tests
   - Zero warnings: PASS
   - Warnings-as-errors: PASS
   - Build time < 5% increase: PASS (2.3s vs 2.2s baseline)

✅ Functional Tests
   - All existing tests: PASS (152/152)
   - Integration tests: PASS (23/23)
   - Example agents: PASS (3/3)

✅ Performance Tests
   - Audio processing latency: PASS (<100ms maintained)
   - Memory usage: PASS (+2% acceptable)
   - Real-time capabilities: PASS

📊 Test Coverage: 87.2% (maintained from baseline 87.1%)

# Error cases
Exit Code 1: Compilation warnings still present
Exit Code 2: Functional tests failing
Exit Code 3: Performance regression detected
Exit Code 4: Test coverage dropped below threshold
```

## Configuration & State

### Configuration Schema
```bash
# mix.exs additions for warning management
def project do
  [
    # ... existing config
    warning_config: [
      categories: [:simple, :api_correction, :architecture],
      timeline_weeks: 6,
      parallel_fixes: false,
      test_before_fix: true,
      performance_threshold: 0.05  # 5% max increase
    ]
  ]
end
```

### Progress State Storage
```bash
# .warnings_progress.json (git-ignored, local tracking)
{
  "start_date": "2025-10-07",
  "baseline_warnings": 57,
  "current_warnings": 11,
  "categories": {
    "simple": {"planned": 23, "completed": 23, "week": 2},
    "api_correction": {"planned": 18, "completed": 18, "week": 4},
    "architecture": {"planned": 16, "completed": 5, "week": 6}
  },
  "blocked_warnings": [
    {
      "file": "lib/livekitex_agent/media/stream_manager.ex",
      "issue": "GenStage dependency decision pending",
      "blocker_date": "2025-10-15"
    }
  ]
}
```

## Integration Contracts

### CI/CD Pipeline Integration

```yaml
# .github/workflows/warnings.yml
name: Warning Prevention
on: [push, pull_request]

jobs:
  check_warnings:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.12'
          otp-version: '24'
      - run: mix deps.get
      - run: mix warnings:test
      - run: mix compile --warnings-as-errors

  # Success: Green check, allows merge
  # Failure: Red X, blocks merge until fixed
```

### Documentation Update Contract
```bash
# Auto-generated progress tracking
# Location: docs/warning-resolution-progress.md

# Warning Resolution Progress

**Last Updated**: 2025-10-07 16:30
**Status**: 80% Complete (46/57 warnings resolved)

## Timeline Progress
- Week 1-2 (Simple): ✅ Complete (23/23)
- Week 3-4 (API): 🔄 In Progress (18/18)
- Week 5-6 (Architecture): ⏳ Planned (5/16)

## Files Modified
[Auto-generated list of files with fixes applied]

## Remaining Work
[Auto-generated list of pending warnings with fix strategies]
```