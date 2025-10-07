# Tasks: Fix Phoenix Integration Configuration Issue

**Input**: Design documents from `/specs/004-fix-phoenix-integration/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure for Phoenix integration fix

- [x] T001 Create Phoenix integration test project structure in `test/support/phoenix_test_app/`
- [x] T002 [P] Add development dependencies for Phoenix testing to `mix.exs`
- [x] T003 [P] Update existing ExUnit configuration for Phoenix integration tests

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core configuration infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Enhance WorkerOptions module structure for configuration resolution in `lib/livekitex_agent/worker_options.ex`
- [x] T005 Add configuration validation infrastructure and error handling utilities
- [x] T006 Create auto-generated entry_point infrastructure in `lib/livekitex_agent/example_tools.ex`
- [x] T007 Update Application module structure for enhanced startup in `lib/livekitex_agent/application.ex`

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Phoenix Developer Library Integration (Priority: P1) 🎯 MVP

**Goal**: Enable zero-configuration Phoenix integration - developers can add dependency and start Phoenix without crashes

**Independent Test**: Add livekitex_agent to fresh Phoenix 1.8.1 project, run `mix deps.get && mix phx.server`, verify successful startup without WorkerManager errors

### Implementation for User Story 1

- [ ] T008 [US1] Implement `WorkerOptions.from_config/1` function in `lib/livekitex_agent/worker_options.ex`
- [ ] T009 [US1] Implement `WorkerOptions.with_defaults/1` function in `lib/livekitex_agent/worker_options.ex`
- [ ] T010 [US1] Add auto-generated entry_point function in `lib/livekitex_agent/example_tools.ex`
- [ ] T011 [US1] Modify `Application.start/2` to use resolved WorkerOptions in `lib/livekitex_agent/application.ex`
- [ ] T012 [P] [US1] Create Phoenix integration test in `test/phoenix_integration_test.exs`
- [ ] T013 [P] [US1] Add unit tests for `from_config/1` in `test/worker_options_test.exs`
- [ ] T014 [P] [US1] Add unit tests for `with_defaults/1` in `test/worker_options_test.exs`
- [ ] T015 [US1] Update default configuration documentation in `config/config.exs`

**Checkpoint**: At this point, Phoenix developers can add livekitex_agent dependency and start Phoenix without configuration errors

---

## Phase 4: User Story 2 - Custom Configuration Override (Priority: P2)

**Goal**: Allow Phoenix developers to customize worker settings via config.exs while maintaining compatibility

**Independent Test**: Configure custom worker options in config.exs, restart Phoenix app, verify custom settings are applied and defaults are used for missing values

### Implementation for User Story 2

- [ ] T016 [US2] Enhance `WorkerOptions.from_config/1` to handle partial user configuration in `lib/livekitex_agent/worker_options.ex`
- [ ] T017 [US2] Add configuration merging logic for user config + defaults in `lib/livekitex_agent/worker_options.ex`
- [ ] T018 [P] [US2] Create custom configuration integration test in `test/phoenix_integration_test.exs`
- [ ] T019 [P] [US2] Add unit tests for partial configuration scenarios in `test/worker_options_test.exs`
- [ ] T020 [US2] Add example configuration patterns in `config/dev.exs`
- [ ] T021 [P] [US2] Create Phoenix integration example in `examples/phoenix_integration.exs`

**Checkpoint**: At this point, both zero-config AND custom config scenarios work independently

---

## Phase 5: User Story 3 - Error Reporting and Diagnostics (Priority: P3)

**Goal**: Provide clear error messages and diagnostics when configuration issues occur

**Independent Test**: Provide invalid configuration values, verify clear error messages with actionable suggestions are displayed

### Implementation for User Story 3

- [ ] T022 [US3] Implement `WorkerOptions.validate!/1` with comprehensive validation in `lib/livekitex_agent/worker_options.ex`
- [ ] T023 [US3] Add detailed error messages with suggestions for common configuration mistakes
- [ ] T024 [US3] Enhance Application startup error handling with clear diagnostics in `lib/livekitex_agent/application.ex`
- [ ] T025 [P] [US3] Create validation error tests in `test/worker_options_test.exs`
- [ ] T026 [P] [US3] Add application startup error handling tests in `test/application_test.exs`
- [ ] T027 [US3] Add error message examples to quickstart documentation

**Checkpoint**: All user stories should now be independently functional with proper error handling

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and ensure production readiness

- [ ] T028 [P] Update module documentation with Phoenix integration examples in `lib/livekitex_agent/worker_options.ex`
- [ ] T029 [P] Add comprehensive Application module documentation in `lib/livekitex_agent/application.ex`
- [ ] T030 [P] Code cleanup and refactoring across modified modules
- [ ] T031 [P] Update README.md with Phoenix integration quickstart
- [ ] T032 Run quickstart.md validation with actual Phoenix test project
- [ ] T033 [P] Add compatibility testing for Phoenix 1.8.1+ versions

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Builds on US1 but independently testable
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Enhances US1/US2 but independently testable

### Within Each User Story

- Core configuration functions before Application integration
- Unit tests can run in parallel with implementation (different files)
- Integration tests after core implementation
- Documentation after implementation is complete

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel
- All Foundational tasks with different files can be worked on simultaneously
- Once Foundational phase completes, all user stories can start in parallel (if team capacity allows)
- All tests marked [P] can run in parallel (different test files)
- Documentation tasks marked [P] can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch core implementation and tests together:
Task: "Create Phoenix integration test in test/phoenix_integration_test.exs"
Task: "Add unit tests for from_config/1 in test/worker_options_test.exs"
Task: "Add unit tests for with_defaults/1 in test/worker_options_test.exs"

# After core functions are implemented:
Task: "Update default configuration documentation in config/config.exs"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test Phoenix integration independently with zero configuration
5. Deploy/release if ready - this fixes the core issue

### Incremental Delivery

1. Complete Setup + Foundational → Configuration infrastructure ready
2. Add User Story 1 → Test independently → Release (MVP fixes Phoenix crash!)
3. Add User Story 2 → Test independently → Release (adds customization)
4. Add User Story 3 → Test independently → Release (adds better diagnostics)
5. Each story adds value without breaking previous functionality

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1 (critical path)
   - Developer B: User Story 2 (can start parallel to US1)
   - Developer C: User Story 3 (can start parallel to US1/US2)
3. Stories integrate naturally since they modify same modules in compatible ways

---

## Notes

- [P] tasks = different files, no dependencies, can run simultaneously
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Focus on User Story 1 first - it solves the core Phoenix integration crash
- Verify each story works independently before moving to next priority
- All changes maintain backward compatibility with existing WorkerOptions usage