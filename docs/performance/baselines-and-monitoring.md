# LivekitexAgent Performance Baselines and Monitoring

## Overview

This document establishes performance baselines and monitoring approaches for the LivekitexAgent system. It defines target performance characteristics, measurement methodologies, and comprehensive monitoring strategies for production deployment.

## Performance Baselines

### 1. Latency Baselines

#### Audio Processing Latency
**Target**: < 50ms per audio chunk
**Critical Threshold**: < 100ms
**Measurement**: Time from audio input to processed output

**Baseline Metrics**:
- **PCM16 Processing**: 5-15ms typical
- **VAD Processing**: 2-8ms per chunk
- **Buffer Management**: 1-3ms overhead
- **Format Conversion**: <1ms

#### End-to-End Response Latency
**Target**: < 100ms total system response
**Critical Threshold**: < 200ms
**Measurement**: User audio input to agent audio output

**Component Breakdown**:
```
Audio Input → STT Processing → LLM Processing → TTS → Audio Output
    ↓              ↓              ↓            ↓         ↓
   5ms          50-150ms       200-800ms    50-200ms    5ms
```

**Baseline Distribution**:
- **P50 (Median)**: 350ms
- **P90**: 800ms
- **P95**: 1200ms
- **P99**: 2000ms

#### Component-Specific Latency Targets

##### LiveKit WebRTC Latency
**Target**: Sub-100ms audio transmission
**Measurement**: Network round-trip including processing
- **Local Network**: 10-30ms
- **Regional CDN**: 50-80ms
- **Global**: 100-150ms

##### OpenAI API Latency
**STT (Whisper)**: 50-300ms depending on audio length
**LLM (GPT-4)**: 200-1500ms depending on complexity
**TTS**: 50-500ms depending on text length and voice
**Realtime API**: 50-200ms streaming response

### 2. Throughput Baselines

#### Concurrent Session Capacity
**Target**: 100+ concurrent sessions per worker
**Critical**: Maintain <200ms latency at target capacity
**Scaling Point**: 75 sessions (auto-scale trigger)

**Resource Requirements per Session**:
- **Memory**: 2-5MB average, 10MB peak
- **CPU**: 1-3% per session (depends on activity)
- **Network**: 50-200kb/s per active session

#### Request Processing Rates
**Agent Creation**: 100+ agents/second
**Tool Registration**: 1000+ tools/second
**Session Initialization**: 50+ sessions/second
**Message Processing**: 10+ messages/second per session

### 3. Resource Utilization Baselines

#### Memory Usage
**System Baseline**: 50-100MB core system
**Per Session**: 2-5MB typical, 10MB peak
**Buffer Management**: 1-2MB per audio buffer
**Tool Registry**: <1MB for 100 tools
**Critical Threshold**: 80% system memory

#### CPU Utilization
**System Baseline**: 5-10% idle system
**Per Session**: 1-3% per active conversation
**Audio Processing**: 2-5% per real-time stream
**Critical Threshold**: 70% sustained utilization

#### Network Bandwidth
**Audio Streaming**: 64-128kbps per session (PCM16 16kHz)
**API Calls**: 1-10kb per request (varies by provider)
**WebRTC Overhead**: 20-40kbps per connection
**Peak Capacity**: 10Mbps for 100 concurrent sessions

### 4. Quality Baselines

#### Audio Quality Metrics
**Target Quality Score**: > 4.0/5.0
**Measurement**: Automated quality assessment + user feedback

**Quality Indicators**:
- **Clarity Score**: > 4.0 (no distortion, clear speech)
- **Naturalness**: > 3.5 (human-like intonation)
- **Intelligibility**: > 95% (word recognition accuracy)
- **Background Noise**: < 2% (noise ratio)

#### System Availability
**Target**: 99.9% uptime (8.76 hours downtime/year)
**Measurement**: Health check endpoint availability
**Recovery**: < 30 seconds for component failures

## Monitoring Architecture

### 1. Real-time Monitoring System

#### Core Monitoring Components
```elixir
# Real-time performance monitoring
{:ok, monitor} = LivekitexAgent.Telemetry.RealtimeMonitor.start_link(
  session_pid: session_pid,
  components: [:audio_processor, :webrtc_handler, :llm_client],
  alert_thresholds: %{
    latency_ms: 150,           # Alert if latency > 150ms
    quality_score: 3.0,        # Alert if quality < 3.0
    memory_mb: 500,            # Alert if memory > 500MB
    cpu_percent: 70,           # Alert if CPU > 70%
    error_rate: 0.05          # Alert if errors > 5%
  }
)
```

#### Monitoring Frequency
- **Real-time Metrics**: 250ms intervals (4Hz)
- **System Metrics**: 1-second intervals
- **Aggregated Reports**: 1-minute intervals
- **Health Checks**: 5-second intervals

### 2. Metrics Collection System

#### Core Metrics Module
**Module**: `LivekitexAgent.Telemetry.Metrics`
**Storage**: ETS tables for high-performance local storage
**Retention**: 24 hours for detailed metrics, 30 days aggregated

#### Metric Categories

##### Session Performance Metrics
```elixir
# Session lifecycle metrics
:telemetry.execute([:livekitex_agent, :session, :started], %{
  session_id: session_id,
  timestamp: System.system_time(:millisecond)
})

:telemetry.execute([:livekitex_agent, :session, :turn_completed], %{
  session_id: session_id,
  duration_ms: turn_duration,
  messages_count: message_count
})
```

**Tracked Metrics**:
- Session duration and lifecycle events
- Turn completion rates and timing
- User engagement patterns
- Error rates and failure analysis

##### Audio Processing Metrics
```elixir
# Audio quality and latency tracking
:telemetry.execute([:livekitex_agent, :audio, :processed], %{
  latency_ms: processing_time,
  quality_score: audio_quality,
  chunk_size_bytes: data_size
})
```

**Tracked Metrics**:
- STT/TTS processing latency and accuracy
- Audio quality scores and degradation
- Buffer performance and audio glitches
- Format conversion efficiency

##### Connection Quality Metrics
```elixir
# Network and connection monitoring
:telemetry.execute([:livekitex_agent, :connection, :quality], %{
  latency_ms: rtt_latency,
  packet_loss_percent: loss_rate,
  bandwidth_kbps: current_bandwidth
})
```

**Tracked Metrics**:
- WebRTC connection quality and stability
- Network latency and packet loss
- Reconnection rates and recovery time
- Connection establishment time

### 3. Health Check System

#### HTTP Health Endpoints
**Module**: `LivekitexAgent.HealthServer`
**Default Port**: 8080

**Available Endpoints**:
```bash
# Basic health check - service responsive
GET /health
Response: {"healthy": true, "timestamp": "2024-01-01T00:00:00Z"}

# Kubernetes readiness probe
GET /health/ready
Response: {"ready": true, "services": ["livekit", "openai"], "timestamp": "..."}

# Kubernetes liveness probe
GET /health/live
Response: {"alive": true, "uptime_seconds": 3600, "timestamp": "..."}

# Prometheus-compatible metrics
GET /metrics
Response:
http_requests_total 1547
uptime_seconds 3600
memory_bytes 104857600
...

# Detailed system status
GET /status
Response: {
  "health": {...},
  "metrics": {...},
  "uptime_seconds": 3600,
  "request_count": 1547
}
```

#### Health Check Categories
```elixir
# System health checks
defp check_system_health do
  %{
    status: :healthy,
    memory_usage: get_memory_percentage(),
    cpu_usage: get_cpu_percentage(),
    disk_usage: get_disk_percentage(),
    load_average: get_load_average()
  }
end

# External service checks
defp check_external_services do
  %{
    livekit: check_livekit_connectivity(),
    openai: check_openai_api(),
    database: check_database_connection()
  }
end
```

### 4. Performance Dashboard System

#### Dashboard Data Structure
```elixir
# Real-time dashboard metrics
dashboard_data = %{
  overview: %{
    active_sessions: session_count,
    success_rate: calculate_success_rate(),
    avg_response_time: get_avg_response_time(),
    error_rate: calculate_error_rate()
  },
  system: %{
    cpu_usage: get_current_cpu_usage(),
    memory_usage: get_current_memory_usage(),
    active_connections: get_connection_count(),
    queue_size: get_queue_metrics()
  },
  performance_trends: get_performance_trends(),
  top_errors: get_top_error_types(),
  worker_status: get_worker_health_status()
}
```

#### Performance Visualization
**Supported Formats**: JSON, Prometheus, HTML dashboard
**Update Frequency**: Real-time (WebSocket) or polling (HTTP)
**Historical Data**: 24-hour detailed, 30-day aggregated

### 5. Alerting and Notification System

#### Alert Threshold Configuration
```elixir
# Configure performance alerts
LivekitexAgent.Telemetry.Metrics.set_alert_rule("high_latency", %{
  metric: "audio.processing.latency_ms",
  condition: :greater_than,
  threshold: 150,                    # Alert if > 150ms
  duration_seconds: 300,             # Sustained for 5 minutes
  severity: :warning,
  notification_channels: [:email, :webhook]
})

LivekitexAgent.Telemetry.Metrics.set_alert_rule("critical_errors", %{
  metric: "session.error_rate",
  condition: :greater_than,
  threshold: 0.10,                   # Alert if > 10% error rate
  duration_seconds: 60,              # Sustained for 1 minute
  severity: :critical,
  notification_channels: [:pagerduty, :slack]
})
```

#### Alert Categories and Thresholds

##### Performance Alerts
- **High Latency**: > 150ms sustained for 5 minutes
- **Low Quality**: Audio quality < 3.0 for 2 minutes
- **Memory Usage**: > 80% system memory for 5 minutes
- **CPU Usage**: > 70% utilization for 10 minutes

##### Error Rate Alerts
- **Session Failures**: > 5% error rate for 2 minutes
- **API Failures**: > 10% external API errors for 1 minute
- **Connection Issues**: > 15% WebRTC failures for 5 minutes

##### Resource Alerts
- **Disk Space**: < 10% free space remaining
- **Network Saturation**: > 90% bandwidth utilization
- **Queue Backlog**: > 100 pending requests for 1 minute

## Monitoring Implementation

### 1. Telemetry Integration
```elixir
# Attach telemetry event handlers
:telemetry.attach_many(
  "livekitex-agent-monitoring",
  [
    [:livekitex_agent, :session, :started],
    [:livekitex_agent, :session, :completed],
    [:livekitex_agent, :audio, :processed],
    [:livekitex_agent, :tool, :executed],
    [:livekitex_agent, :connection, :established]
  ],
  &LivekitexAgent.Telemetry.Metrics.handle_event/4,
  %{}
)
```

### 2. Custom Metrics Collection
```elixir
# Register custom metric collectors
LivekitexAgent.Telemetry.Metrics.register_collector("database.connections", fn ->
  connection_count = MyApp.Database.connection_count()
  [{"database.connections.active", connection_count}]
end)

LivekitexAgent.Telemetry.Metrics.register_collector("business.conversion_rate", fn ->
  rate = calculate_user_conversion_rate()
  [{"business.conversion_rate", rate}]
end)
```

### 3. Performance Optimization Integration
```elixir
# Automatic performance optimization
{:ok, optimizer} = LivekitexAgent.Media.PerformanceOptimizer.start_link(
  audio_processor: audio_pid,
  target_latency_ms: 80,
  optimization_profile: :realtime
)

# Monitor and auto-optimize
LivekitexAgent.Media.PerformanceOptimizer.optimize_for_realtime(optimizer)
```

## Deployment Monitoring

### 1. Production Configuration
```elixir
# config/prod.exs
config :livekitex_agent,
  # Enable comprehensive monitoring in production
  telemetry: [
    enabled: true,
    metrics_interval_ms: 1000,
    export_interval_ms: 60_000,
    retention_hours: 24
  ],

  # Health check configuration
  health_server: [
    enabled: true,
    port: 8080,
    host: "0.0.0.0"
  ],

  # Performance monitoring
  monitoring: [
    real_time_enabled: true,
    alert_thresholds: %{
      latency_ms: 150,
      error_rate: 0.05,
      memory_percent: 80,
      cpu_percent: 70
    }
  ]
```

### 2. Container Health Checks
```yaml
# Docker health check
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

### 3. Kubernetes Integration
```yaml
# Kubernetes deployment with health checks
apiVersion: apps/v1
kind: Deployment
metadata:
  name: livekitex-agent
spec:
  template:
    spec:
      containers:
      - name: agent
        livenessProbe:
          httpGet:
            path: /health/live
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
```

## Performance Benchmarking

### 1. Benchmarking Methodology
```bash
# Automated performance benchmarking
./scripts/benchmark-performance.sh

# Generates comprehensive performance report including:
# - Component initialization latency
# - Concurrent session capacity testing
# - Memory usage profiling
# - Audio processing throughput
# - External API response times
```

### 2. Continuous Performance Testing
```elixir
# Automated performance regression testing
defmodule LivekitexAgent.PerformanceTest do
  def benchmark_agent_creation do
    measure_time(fn ->
      agent = LivekitexAgent.Agent.new(
        instructions: "Test agent",
        tools: [:test_tool]
      )
    end)
  end

  def benchmark_session_capacity do
    # Test concurrent session limits
    concurrent_sessions = 1..100
    |> Enum.map(fn i ->
      Task.async(fn -> create_test_session(i) end)
    end)
    |> Enum.map(&Task.await/1)

    measure_performance_degradation(concurrent_sessions)
  end
end
```

This performance baseline and monitoring approach ensures LivekitexAgent maintains optimal performance characteristics in production while providing comprehensive visibility into system behavior and automatic optimization capabilities.