# Tasks: Fix Phoenix Integration Configuration Error

**Feature**: 005-fix-phoenix-integration
**Branch**: `005-fix-phoenix-integration`
**Date**: October 7, 2025
**Generated from**: [spec.md](./spec.md), [plan.md](./plan.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

## Task Overview

**Total Tasks**: 15
**User Stories**: 3 (P1: Critical startup, P2: Error messages, P3: Graceful fallback)
**Implementation Strategy**: Test-driven development with independent story completion
**MVP Scope**: User Story 1 (Critical startup functionality)

## Phase 1: Setup & Prerequisites

### T001: [Setup] Validate current test environment ✓
**File**: `test/test_helper.exs`
**Description**: Ensure ExUnit is properly configured for the new test files
**Acceptance**: Test helper runs without errors, supports proper test isolation
**Dependencies**: None
**Status**: COMPLETED - Test environment validated, shows current configuration issues

### T002: [Setup] Create test data factories [P] ✓
**File**: `test/support/test_factories.ex`
**Description**: Create helper functions for generating valid/invalid WorkerOptions and configuration data
**Acceptance**: Factories can generate all edge cases identified in contracts
**Dependencies**: None
**Status**: COMPLETED - Test factories created with comprehensive edge case coverage

## Phase 2: Foundational Changes (Blocking Prerequisites)

### T003: [Foundation] Add WorkerOptions input validation to WorkerManager
**File**: `lib/livekitex_agent/worker_manager.ex`
**Description**: Add `validate_worker_options_input/1` function and call it in `init/1`
**Acceptance**: Clear ArgumentError with helpful message when receiving invalid input types
**Dependencies**: T001

### T004: [Foundation] Enhance WorkerOptions.from_config error handling
**File**: `lib/livekitex_agent/worker_options.ex`
**Description**: Add input type validation and clear error messages in `from_config/1`
**Acceptance**: Function handles all edge cases from contracts without crashing
**Dependencies**: T001

## Phase 3: User Story 1 - Agent Application Starts Successfully (Priority P1)

**Story Goal**: Phoenix applications with livekitex_agent start without KeyError exceptions
**Independent Test**: Add to Phoenix app deps, run `mix phx.server`, verify startup succeeds

### T005: [US1] Test - Application configuration resolution scenarios
**File**: `test/application_test.exs`
**Description**: Create comprehensive test cases for `resolve_worker_options/0` covering all edge cases
**Acceptance**: Tests cover empty config, nil config, invalid types, and success cases
**Dependencies**: T002

### T006: [US1] Test - WorkerManager initialization validation [P]
**File**: `test/worker_manager_test.exs`
**Description**: Test WorkerManager initialization with various input types and validation errors
**Acceptance**: Tests verify proper error messages and successful initialization with valid inputs
**Dependencies**: T002

### T007: [US1] Fix Application.resolve_worker_options implementation
**File**: `lib/livekitex_agent/application.ex`
**Description**: Replace current resolve_worker_options/0 with robust implementation including try/rescue and emergency fallback
**Acceptance**: Function never crashes, always returns valid WorkerOptions struct
**Dependencies**: T003, T004, T005

### T008: [US1] Add emergency fallback configuration creation [P]
**File**: `lib/livekitex_agent/application.ex`
**Description**: Implement `create_emergency_fallback/0` function with minimal valid configuration
**Acceptance**: Creates WorkerOptions that pass validation and allow basic functionality
**Dependencies**: T004

### T009: [US1] Test - Phoenix integration startup scenarios
**File**: `test/phoenix_integration_test.exs`
**Description**: Integration tests simulating Phoenix application startup with various configuration states
**Acceptance**: Application starts successfully in all scenarios, uses fallback when needed
**Dependencies**: T007, T008

**✓ Checkpoint US1**: Application starts reliably without KeyError exceptions

## Phase 4: User Story 2 - Configuration Validation and Error Messages (Priority P2)

**Story Goal**: Developers receive clear, actionable error messages for configuration issues
**Independent Test**: Provide invalid config, verify error messages help identify and fix problems

### T010: [US2] Test - Enhanced error message scenarios
**File**: `test/worker_options_test.exs`
**Description**: Test error message quality and actionability for all invalid configuration scenarios
**Acceptance**: Error messages include problem description, impact, and specific fix instructions
**Dependencies**: T002

### T011: [US2] Enhance error message formatting in WorkerOptions validation
**File**: `lib/livekitex_agent/worker_options.ex`
**Description**: Improve error messages in `validate!/1` to match contract specifications
**Acceptance**: Messages follow standard format: what, why, how-to-fix, suggested values
**Dependencies**: T004, T010

### T012: [US2] Add structured logging for configuration issues [P]
**File**: `lib/livekitex_agent/application.ex`
**Description**: Add comprehensive logging with structured data for configuration failures
**Acceptance**: Logs include error type, received value, suggested fix, and fallback status
**Dependencies**: T007

**✓ Checkpoint US2**: Configuration errors provide clear guidance for resolution

## Phase 5: User Story 3 - Graceful Fallback Mechanism (Priority P3)

**Story Goal**: System continues to function with emergency defaults when configuration fails
**Independent Test**: Force configuration failure, verify application starts with degraded functionality

### T013: [US3] Test - Fallback mechanism activation scenarios
**File**: `test/application_fallback_test.exs`
**Description**: Test emergency fallback activation under various failure conditions
**Acceptance**: Fallback activates quickly (< 1s) and provides working configuration
**Dependencies**: T002, T008

### T014: [US3] Add performance monitoring for configuration resolution [P]
**File**: `lib/livekitex_agent/application.ex`
**Description**: Add telemetry events and timing measurements for configuration performance tracking
**Acceptance**: Resolution time logged, meets < 1s performance requirement
**Dependencies**: T012

## Phase 6: Polish & Cross-Cutting Concerns

### T015: [Polish] Final integration verification and cleanup
**File**: Multiple files
**Description**: Run full test suite, verify Credo/Dialyzer compliance, update documentation
**Acceptance**: All tests pass, no quality gate failures, documentation reflects changes
**Dependencies**: T009, T011, T013

## Dependencies & Execution Order

### Critical Path (MVP - User Story 1)
```
T001 → T002 → T003,T004 → T005,T006 → T007,T008 → T009
```

### Full Feature Dependencies
```
Phase 1: T001 → T002
Phase 2: T003,T004 (depends on T001)
Phase 3: T005,T006 (depends on T002) → T007,T008 (depends on T003,T004) → T009
Phase 4: T010 (depends on T002) → T011 (depends on T004,T010) + T012 (depends on T007)
Phase 5: T013 (depends on T002,T008) + T014 (depends on T012)
Phase 6: T015 (depends on all previous)
```

### Parallel Execution Opportunities

**Phase 2 (Foundation)**:
```bash
# Can run in parallel after T001 completes
mix test test/worker_manager_test.exs &    # T003 validation
mix test test/worker_options_test.exs &    # T004 validation
wait
```

**Phase 3 (User Story 1)**:
```bash
# After T002 factory setup
mix test test/application_test.exs &       # T005
mix test test/worker_manager_test.exs &    # T006
wait

# After T003,T004 foundation complete
# T007 and T008 can be implemented in parallel (different functions)
```

**Phase 4 (User Story 2)**:
```bash
# After T004,T007 complete
# T011 and T012 are independent enhancements
mix test test/worker_options_test.exs &    # T011 validation
mix test test/application_test.exs &       # T012 validation
wait
```

## Story Completion Criteria

### User Story 1 (P1) - Complete when:
- [ ] Application.resolve_worker_options/0 never crashes (T007)
- [ ] Emergency fallback creates valid configuration (T008)
- [ ] Phoenix applications start without KeyError (T009)
- [ ] All P1 tests pass consistently

### User Story 2 (P2) - Complete when:
- [ ] Error messages include actionable guidance (T011)
- [ ] Configuration failures are logged with context (T012)
- [ ] Developers can resolve issues in < 5 minutes
- [ ] All P2 tests pass consistently

### User Story 3 (P3) - Complete when:
- [ ] Fallback mechanism activates within 1 second (T013)
- [ ] Configuration resolution performance monitored (T014)
- [ ] System provides basic functionality during degraded mode
- [ ] All P3 tests pass consistently

## Implementation Strategy

### MVP Approach (Minimum Viable Product)
**Scope**: Complete User Story 1 only (T001-T009)
**Timeline**: Fastest path to eliminate KeyError exceptions
**Deliverable**: Reliable Phoenix integration without crashes

### Incremental Delivery
1. **Sprint 1**: Foundation + User Story 1 (T001-T009) - Critical functionality
2. **Sprint 2**: User Story 2 (T010-T012) - Developer experience
3. **Sprint 3**: User Story 3 (T013-T014) - Resilience features
4. **Sprint 4**: Polish (T015) - Production readiness

### Quality Gates
- **After each task**: Unit tests pass for modified code
- **After each story**: Integration tests pass, story acceptance criteria met
- **Before completion**: Full test suite, Credo, Dialyzer, manual verification

## File Impact Summary

**Modified Files**:
- `lib/livekitex_agent/application.ex` (T007, T008, T012, T014)
- `lib/livekitex_agent/worker_manager.ex` (T003)
- `lib/livekitex_agent/worker_options.ex` (T004, T011)

**New Test Files**:
- `test/support/test_factories.ex` (T002)
- `test/application_test.exs` (T005)
- `test/worker_manager_test.exs` (T006)
- `test/phoenix_integration_test.exs` (T009)
- `test/worker_options_test.exs` (T010)
- `test/application_fallback_test.exs` (T013)

**Risk Mitigation**: All changes maintain backward compatibility, no breaking API changes