# LivekitexAgent Constitution

## Core Principles

### I. LiveKitEx Foundation (NON-NEGOTIABLE)
All functionality MUST be built on top of the custom `livekitex` library (v0.1.34+). This is the core dependency that enables LiveKit protocol communication in Elixir. No direct protocol implementations are allowed - everything must flow through livekitex abstractions to ensure consistency and maintainability.

### II. Python LiveKit Agent Parity
Feature implementations MUST maintain functional parity with Python LiveKit Agents while respecting Elixir idioms. Each feature should have a clear Python counterpart documented in implementation. When Python patterns conflict with Elixir best practices, choose the Elixir way but document the deviation.

### III. Real-Time Audio/Video First
The system is designed for low-latency, real-time communication. All components MUST support:
- WebSocket-based realtime connections
- PCM16 audio streaming capabilities
- Concurrent audio/video handling
- Graceful degradation when media streams fail
- Sub-100ms response times for critical paths

### IV. Agent-Centric Architecture
Every feature revolves around the Agent abstraction:
- Agents have instructions, tools, and media components (LLM/STT/TTS/VAD)
- Agent Sessions manage conversation state and turn-taking
- Job/Run Contexts provide execution environment for agent operations
- Function Tools extend agent capabilities dynamically

### V. OTP Supervision & Fault Tolerance
Leverage Elixir's OTP principles:
- All long-running processes must be supervised
- Worker processes should handle crashes gracefully
- Session state must survive individual component failures
- Health checks and circuit breakers for external dependencies
- Let-it-crash philosophy for non-critical components

### VI. CLI & Development Experience
Provide excellent developer experience:
- CLI commands for dev/prod deployment
- Hot-reload support during development
- Comprehensive logging with structured formats
- Built-in health checks and diagnostics
- Example implementations for common use cases

## Technology Constraints

### Required Stack
- **Core**: Elixir ~> 1.12, OTP supervision trees
- **LiveKit**: livekitex ~> 0.1.34 (custom library)
- **WebSockets**: websockex for realtime connections
- **HTTP**: httpoison + hackney for API calls
- **JSON**: jason for data serialization
- **Audio**: System `afplay` on macOS (built-in audio playback)

### Media Processing Requirements
- Support PCM16 audio format as primary
- WebSocket streaming for real-time audio
- Graceful handling of video streams when present
- Buffer management for audio/video synchronization
- Platform-specific audio playback (macOS afplay, extensible)

### External Integration Standards
- OpenAI API compatibility for LLM/STT/TTS services
- Function calling schema generation (OpenAI format)
- WebRTC support through LiveKit infrastructure
- RESTful APIs for agent management and control

## Development Workflow

### Test-First Development
- Unit tests for all public functions
- Integration tests for LiveKit protocol interactions
- Real-time communication tests with mock WebSocket servers
- Audio processing pipeline tests
- CLI command tests with example scenarios

### Documentation Requirements
- All public modules must have comprehensive @moduledoc
- Function documentation with examples
- README with quick start guide
- Example agents in /examples directory
- Architecture documentation for complex subsystems

### Quality Gates
- Credo static analysis (zero warnings)
- Dialyzer type checking (all public functions typed)
- Test coverage > 80% for core modules
- Performance benchmarks for real-time paths
- Manual testing with actual LiveKit servers

## Governance

This constitution supersedes all other development practices. The architecture must remain true to both Elixir/OTP principles and LiveKit Agent patterns. When conflicts arise, prioritize real-time performance and fault tolerance.

Changes to core principles require:
1. Documentation of impact on existing implementations
2. Migration plan for breaking changes
3. Approval from project maintainer
4. Update of all affected examples and documentation

**Version**: 1.0.0 | **Ratified**: 2025-10-07 | **Last Amended**: 2025-10-07