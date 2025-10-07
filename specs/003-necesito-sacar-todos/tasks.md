# Tasks: Clean Compilation - Zero Warnings

**Input**: Design documents from `/specs/003-necesito-sacar-todos/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions


## Phase 3: User Story 1 - Clean Development Builds (Priority: P1) 🎯 MVP

**Goal**: Eliminate simple warnings to provide immediate clean compilation feedback for developers

**Independent Test**: Run `mix compile` in project root and verify zero warnings for Category A fixes

### Implementation for User Story 1

#### Category A: Simple Variable/Attribute Fixes (Week 1-2)

- [ ] T009 [P] [US1] Fix unused variable warnings in `lib/livekitex_agent/health_server.ex` (lines 347, 353, 644)
- [ ] T010 [P] [US1] Fix unused module attribute `@valid_states` in `lib/livekitex_agent/agent.ex` (line 19)
- [ ] T011 [P] [US1] Remove @doc annotations from private functions in `lib/livekitex_agent/health_server.ex` (lines 383, 391, 426, 450, 474, 496, 518, 554, 569, 589, 614, 641, 657, 672, 687)
- [ ] T012 [P] [US1] Fix unused variables in `lib/livekitex_agent/cli.ex` (lines 876, 1170, 1623)
- [ ] T013 [P] [US1] Fix unused variables in `lib/livekitex_agent/telemetry/metrics.ex` (lines 941, 946, 973)
- [ ] T014 [P] [US1] Fix unused variables in `lib/livekitex_agent/worker_supervisor.ex` (lines 152, 400, 446)
- [ ] T015 [P] [US1] Fix unused variables in `lib/livekitex_agent/function_tool.ex` (lines 172, 279)
- [ ] T016 [P] [US1] Fix unused variables in `lib/livekitex_agent/worker_manager.ex` (lines 220, 230, 308, 585)
- [ ] T017 [P] [US1] Fix unused alias `TelemetryLogger` in `lib/livekitex_agent/telemetry/logger.ex` (line 39)
- [ ] T018 [P] [US1] Fix unused module attributes in `lib/livekitex_agent/providers/openai/stt.ex` (line 22)
- [ ] T019 [P] [US1] Fix unused module attribute in `lib/livekitex_agent/telemetry/logger.ex` (line 42)
- [ ] T020 [P] [US1] Fix unused module attribute `@tool` in `lib/livekitex_agent/example_tools.ex` (line 291)

#### Validation for User Story 1

- [ ] T021 [US1] Run compilation test suite to verify Category A fixes: `mix compile --warnings-as-errors`
- [ ] T022 [US1] Validate all existing tests still pass: `mix test`
- [ ] T023 [US1] Verify compilation time impact < 5% increase via benchmarking
- [ ] T024 [US1] Update progress tracking in `.warnings_progress.json`

**Checkpoint**: ~25 simple warnings eliminated, clean development builds for basic cases

---

## Phase 4: User Story 2 - Continuous Integration Compatibility (Priority: P2)

**Goal**: Enable CI/CD pipelines to enforce warning-free builds via `--warnings-as-errors`

**Independent Test**: Configure CI with `--warnings-as-errors` and verify builds pass

### Implementation for User Story 2

#### Category B: Function/API Corrections (Week 2-4)

- [ ] T025 [P] [US2] Replace deprecated `Logger.warn` with `Logger.warning` in `lib/livekitex_agent/media/stream_manager.ex` (line 264)
- [ ] T026 [P] [US2] Replace deprecated `Logger.warn` with `Logger.warning` in `lib/livekitex_agent/worker_manager.ex` (lines 291, 564)
- [ ] T027 [P] [US2] Fix undefined Logger functions in `lib/livekitex_agent/function_tool.ex` (lines 128, 498, 507)
- [ ] T028 [P] [US2] Fix undefined function calls in `lib/livekitex_agent/cli.ex` (lines 1148, 1244, 1262, 1280, 1420, 1501, 1527, 1785)
- [ ] T029 [P] [US2] Fix clause ordering warnings in `lib/livekitex_agent/media/audio_processor.ex` (lines 349, 389)
- [ ] T030 [P] [US2] Fix clause ordering warnings in `lib/livekitex_agent/agent_session.ex` (lines 830, 929, 1724)
- [ ] T031 [P] [US2] Fix start_link/2 default value warnings in `lib/livekitex_agent/agent.ex` (line 119)
- [ ] T032 [P] [US2] Fix inefficient length() usage warnings in `lib/livekitex_agent/cli.ex` (lines 619, 693)
- [ ] T033 [P] [US2] Fix unreachable clause warnings in `lib/livekitex_agent/cli.ex` (lines 1137, 1378)
- [ ] T034 [P] [US2] Fix unreachable clause warning in `lib/livekitex_agent/providers/openai/stt.ex` (line 281)
- [ ] T035 [P] [US2] Fix default values warning in `lib/livekitex_agent/function_tool.ex` (line 416)

#### Pre-commit Hook Implementation for User Story 2

- [ ] T036 [US2] Implement pre-commit hook script in `.git-hooks/pre-commit`
- [ ] T037 [US2] Create hook installation task `lib/mix/tasks/warnings/install_hooks.ex`
- [ ] T038 [US2] Add hook testing and validation in installation process
- [ ] T039 [US2] Update README.md with team setup instructions for git hooks

#### Validation for User Story 2

- [ ] T040 [US2] Test pre-commit hooks prevent new warnings from being committed
- [ ] T041 [US2] Validate CI/CD pipeline integration with `--warnings-as-errors`
- [ ] T042 [US2] Run full test suite to ensure API corrections don't break functionality
- [ ] T043 [US2] Update progress tracking and verify Category B completion

**Checkpoint**: API corrections complete, CI/CD enforcement active, regression prevention in place

---

## Phase 5: User Story 3 - Enhanced Code Maintainability (Priority: P3)

**Goal**: Eliminate complex architectural warnings for long-term code maintainability

**Independent Test**: Code follows consistent Elixir patterns without any remaining warnings

### Implementation for User Story 3

#### Category C: Type System & Architecture (Week 3-6)

- [ ] T044 [P] [US3] Fix exception field access warnings using `Exception.message/1` in `lib/livekitex_agent/health_server.ex` (line 1155)
- [ ] T045 [P] [US3] Fix exception field access warnings in `lib/livekitex_agent/worker_supervisor.ex` (line 331)
- [ ] T046 [P] [US3] Fix exception field access warnings in `lib/livekitex_agent/media/audio_processor.ex` (lines 311, 402, 414)
- [ ] T047 [P] [US3] Fix exception field access warnings in `lib/livekitex_agent/tool_registry.ex` (line 423)
- [ ] T048 [P] [US3] Fix exception field access warnings in `lib/livekitex_agent/providers/provider.ex` (lines 162, 181)
- [ ] T049 [P] [US3] Fix exception field access warning in `lib/livekitex_agent/telemetry/logger.ex` (line 204)
- [ ] T050 [US3] Replace deprecated `use Bitwise` with `import Bitwise` in `lib/livekitex_agent/media/audio_processor.ex` (line 43)
- [ ] T051 [US3] Fix type violation warnings in `lib/livekitex_agent/example.ex` (line 27)

#### Dependency Replacement for User Story 3

- [ ] T052 [US3] Evaluate and replace GenStage with GenServer pattern in `lib/livekitex_agent/media/stream_manager.ex` (lines 111, 119)
- [ ] T053 [US3] Replace undefined `:scheduler` module calls with `:erlang.statistics/1` in `lib/livekitex_agent/media/performance_optimizer.ex` (lines 422, 424)
- [ ] T054 [US3] Investigate and fix undefined `Livekitex.Client` in `lib/livekitex_agent/realtime/webrtc_handler.ex` (line 466)
- [ ] T055 [US3] Research and document alternative approaches for undefined `System.uptime/0` in `lib/livekitex_agent/cli.ex` (line 1785)

#### Validation for User Story 3

- [ ] T056 [US3] Run comprehensive type checking with `mix dialyzer` after architectural changes
- [ ] T057 [US3] Validate real-time audio/video functionality preserved after dependency changes
- [ ] T058 [US3] Verify performance impact remains < 5% after architectural modifications
- [ ] T059 [US3] Run complete test suite including integration tests
- [ ] T060 [US3] Final validation: `mix compile --warnings-as-errors` passes with zero warnings

**Checkpoint**: All architectural warnings eliminated, codebase follows consistent Elixir patterns

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and long-term maintenance

- [ ] T061 [P] Create comprehensive documentation in `docs/warning-resolution-progress.md`
- [ ] T062 [P] Update project README.md with warning prevention setup instructions
- [ ] T063 [P] Create developer onboarding checklist including hook installation
- [ ] T064 Add CI/CD workflow configuration for warning enforcement in `.github/workflows/warnings.yml`
- [ ] T065 Create monitoring and reporting for warning prevention effectiveness
- [ ] T066 [P] Run final quickstart.md validation end-to-end
- [ ] T067 [P] Update project quality gates documentation
- [ ] T068 Performance optimization review across all warning fix categories

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
  - User stories can proceed in parallel if team capacity allows
  - Or sequentially in priority order (P1 → P2 → P3) for incremental delivery
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Phase 2 - No dependencies on other stories (MVP delivery)
- **User Story 2 (P2)**: Can start after Phase 2 - Builds on US1 but independently testable
- **User Story 3 (P3)**: Can start after Phase 2 - May reference patterns from US1/US2 but independently testable

### Within Each User Story

- Simple fixes (Category A) can run in parallel - different files, no dependencies
- API corrections (Category B) can run in parallel - different functions and modules
- Architectural changes (Category C) may have dependencies due to type system interactions
- Validation tasks must run after implementation tasks within each story
- Progress tracking happens at end of each user story phase

### Parallel Opportunities

#### Phase 1 & 2 (Setup & Foundation)
- T002, T003 can run in parallel
- T005, T006 can run in parallel after T004 completes

#### User Story 1 (Simple Fixes)
- Tasks T009-T020 can all run in parallel (different files)
- Validation tasks T021-T024 run sequentially after implementation

#### User Story 2 (API Corrections)
- Tasks T025-T035 can run in parallel (different functions)
- Hook tasks T036-T039 can run in parallel with API fixes
- Validation tasks T040-T043 run sequentially after implementation

#### User Story 3 (Architecture)
- Exception handling tasks T044-T049 can run in parallel
- Dependency replacement tasks T052-T055 may need coordination
- Validation tasks T056-T060 run sequentially after architectural changes

---

## Parallel Example: User Story 1 (Simple Fixes)

```bash
# Launch all simple warning fixes in parallel:
Task T009: "Fix unused variables in health_server.ex"
Task T010: "Fix unused @valid_states in agent.ex"
Task T011: "Remove @doc from private functions in health_server.ex"
Task T012: "Fix unused variables in cli.ex"
Task T013: "Fix unused variables in metrics.ex"
Task T014: "Fix unused variables in worker_supervisor.ex"
Task T015: "Fix unused variables in function_tool.ex"
Task T016: "Fix unused variables in worker_manager.ex"
Task T017: "Fix unused alias in logger.ex"
Task T018: "Fix unused attributes in stt.ex"
Task T019: "Fix unused attribute in logger.ex"
Task T020: "Fix unused @tool in example_tools.ex"

# Then run validation sequentially:
Task T021: "Compile with --warnings-as-errors"
Task T022: "Run full test suite"
Task T023: "Benchmark compilation performance"
Task T024: "Update progress tracking"
```

---

## MVP Strategy

**Minimum Viable Product**: User Story 1 (Clean Development Builds)

- Delivers immediate value by eliminating ~25 simple warnings
- Provides clean compilation feedback for daily development
- Low risk implementation with high developer satisfaction impact
- Independent delivery without dependencies on CI/CD or architectural changes

**Incremental Value**: Each user story builds on previous ones while remaining independently valuable:
1. **US1**: Clean local development experience
2. **US2**: CI/CD quality enforcement + regression prevention
3. **US3**: Long-term maintainability and architectural consistency

**Timeline**: 4-6 weeks total, with deliverable value every 1-2 weeks per user story completion