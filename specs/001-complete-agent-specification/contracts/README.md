# API Contracts Overview

This directory contains API specifications for the LivekitexAgent system. The APIs are designed to support both programmatic access and CLI interactions.

## Contract Types

### 1. Elixir Module APIs (elixir_api.md)
Core Elixir module interfaces for programmatic usage within Elixir applications.

### 2. CLI Interface (cli_interface.md)
Command-line interface specification for development and production operations.

### 3. HTTP Health API (health_api.yml)
OpenAPI specification for health check and monitoring endpoints.

### 4. WebSocket Events (websocket_events.md)
Real-time event specifications for agent session communication.

### 5. Function Tool Schema (function_tools.json)
JSON schema definitions for function tool specifications and validation.

## Usage Patterns

- **Development**: Use Elixir APIs directly in Phoenix applications or iex sessions
- **Production**: Use CLI interface for worker deployment and management
- **Monitoring**: Use HTTP Health API for system status and metrics
- **Real-time**: Use WebSocket Events for live session interaction
- **Extension**: Use Function Tool Schema for custom tool development

## Validation

All contracts include validation rules and example payloads. Implementations must validate inputs against these specifications to ensure system reliability and security.