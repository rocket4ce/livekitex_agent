# Implementation Plan: Clean Compilation - Zero Warnings

**Branch**: `003-necesito-sacar-todos` | **Date**: October 7, 2025 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/003-necesito-sacar-todos/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Eliminate all 57+ compilation warnings from the LivekitexAgent project to enable clean development builds and CI/CD enforcement via `--warnings-as-errors`. Implementation will be incremental over 4-6 weeks, prioritizing critical warnings first, with pre-commit hooks to prevent regression. Alternative libraries will be evaluated to replace any dependencies that generate unavoidable warnings.

## Technical Context

**Language/Version**: Elixir ~> 1.12, OTP 24+
**Primary Dependencies**: livekitex ~> 0.1.34, websockex, httpoison, hackney, jason, timex
**Storage**: ETS tables for session state, file system for documentation artifacts
**Testing**: ExUnit test framework, mix test
**Target Platform**: Development and CI/CD environments (macOS, Linux)
**Project Type**: Single Elixir project - determines source structure
**Performance Goals**: <5% compilation time increase post-fixes
**Constraints**: Must preserve all existing functionality and API interfaces
**Scale/Scope**: 57+ warnings across ~20 source files in lib/ directory

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

✅ **LiveKitEx Foundation**: Warning fixes will not alter livekitex ~> 0.1.34 dependency or core abstractions
✅ **Real-Time Audio/Video First**: No changes to WebSocket connections, PCM16 audio, or response time paths
✅ **Agent-Centric Architecture**: Agent abstraction, sessions, and function tools remain unchanged
✅ **OTP Supervision & Fault Tolerance**: Supervision trees and crash handling logic preserved
✅ **CLI & Development Experience**: Enhanced by eliminating warning noise during development
✅ **Required Stack**: All dependencies (Elixir ~> 1.12, livekitex, websockex, etc.) maintained
✅ **Test-First Development**: ExUnit tests must continue passing; additional pre-commit testing added
✅ **Quality Gates**: Contributes directly to Credo compliance and overall code quality

## Project Structure

### Documentation (this feature)

```
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```
lib/
├── livekitex_agent.ex
├── livekitex_agent/
│   ├── agent.ex                    # Unused @valid_states attribute
│   ├── agent_session.ex           # Clause ordering warnings
│   ├── cli.ex                     # Multiple unused variables, undefined functions
│   ├── health_server.ex           # @doc on private functions, unused variables
│   ├── function_tool.ex           # Unused variables, undefined Logger functions
│   ├── worker_manager.ex          # Unused variables, deprecated Logger.warn
│   ├── worker_supervisor.ex       # Unused variables, unknown exception fields
│   ├── media/
│   │   ├── audio_processor.ex     # Deprecated Bitwise use, clause ordering, exception fields
│   │   ├── stream_manager.ex      # Deprecated Logger.warn, undefined GenStage
│   │   └── performance_optimizer.ex # Undefined :scheduler module
│   ├── providers/
│   │   ├── provider.ex           # Exception field access warnings
│   │   └── openai/
│   │       └── stt.ex            # Unused attributes, unreachable clauses
│   ├── telemetry/
│   │   ├── metrics.ex            # Unused variables
│   │   └── logger.ex             # Unused alias, exception field access
│   └── realtime/
│       └── webrtc_handler.ex     # Undefined Livekitex.Client
└── example_tools.ex               # Unused @tool attribute

test/
├── agent_test.exs
├── function_tool_test.exs
├── livekitex_agent_test.exs
└── test_helper.exs

.git-hooks/
└── pre-commit                     # New: Warning prevention hook
```

**Structure Decision**: Single Elixir project with OTP application structure. Warning fixes will be applied across all lib/ modules while maintaining the existing directory organization. New pre-commit hooks added to prevent regression.

## Phase 1 Completion Status

### Artifacts Generated ✅

- **research.md**: Warning categorization strategy, dependency replacement plans, pre-commit hook design
- **data-model.md**: Warning classification model, progress tracking entities, state transitions
- **contracts/cli-commands.md**: Command interfaces for `mix warnings:*` commands, hook contracts
- **quickstart.md**: 6-week implementation guide with weekly milestones and troubleshooting
- **Agent Context**: Updated GitHub Copilot instructions with project technology stack

### Post-Design Constitution Check ✅

All constitution requirements remain satisfied after detailed design:

✅ **LiveKitEx Foundation**: No changes to livekitex dependency or abstractions - purely cosmetic fixes
✅ **Real-Time Audio/Video First**: Performance constraints (<5% impact) ensure real-time capabilities preserved
✅ **Agent-Centric Architecture**: Core agent/session/tool abstractions untouched
✅ **OTP Supervision & Fault Tolerance**: Supervision trees and error handling logic maintained
✅ **CLI & Development Experience**: Enhanced through warning elimination and new `mix warnings:*` commands
✅ **Required Stack**: All technology dependencies preserved (Elixir, livekitex, websockex, etc.)
✅ **Test-First Development**: ExUnit testing enhanced with pre-commit validation
✅ **Quality Gates**: Directly contributes to Credo compliance and zero-warning compilation goal

### Implementation Ready ✅

The feature specification and implementation plan are complete and ready for task breakdown in Phase 2.
