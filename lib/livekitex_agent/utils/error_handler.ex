defmodule LivekitexAgent.Utils.ErrorHandler do
  @moduledoc """
  Base error handling and circuit breaker patterns for robust agent operations.

  This module provides:
  - Circuit breaker pattern for external service calls
  - Retry logic with exponential backoff
  - Error categorization and recovery strategies
  - Rate limiting and throttling
  - Error monitoring and alerting integration
  - Graceful degradation mechanisms

  ## Circuit Breaker States

  - `:closed` - Normal operation, requests pass through
  - `:open` - Circuit is open, requests fail fast
  - `:half_open` - Testing if service has recovered

  ## Error Categories

  - `:transient` - Temporary errors that may succeed on retry
  - `:permanent` - Permanent errors that won't succeed on retry
  - `:rate_limited` - Rate limiting errors, need to back off
  - `:timeout` - Timeout errors, may succeed with retry
  - `:unknown` - Unclassified errors
  """

  use GenServer
  require Logger

  @default_failure_threshold 5
  @default_recovery_timeout_ms 30_000
  @default_request_timeout_ms 10_000
  @default_max_retries 3

  defstruct [
    :name,
    :state,
    :failure_count,
    :failure_threshold,
    :recovery_timeout_ms,
    :last_failure_time,
    :request_timeout_ms,
    :half_open_max_calls,
    :half_open_success_count,
    :metrics
  ]

  @type circuit_state :: :closed | :open | :half_open
  @type error_category :: :transient | :permanent | :rate_limited | :timeout | :unknown

  @type circuit_breaker_options :: %{
    failure_threshold: pos_integer(),
    recovery_timeout_ms: pos_integer(),
    request_timeout_ms: pos_integer(),
    half_open_max_calls: pos_integer()
  }

  @type retry_options :: %{
    max_retries: non_neg_integer(),
    base_delay_ms: pos_integer(),
    max_delay_ms: pos_integer(),
    backoff_multiplier: float()
  }

  ## Client API

  @doc """
  Starts a circuit breaker GenServer.
  """
  def start_link(name, opts \\ %{}) do
    GenServer.start_link(__MODULE__, {name, opts}, name: via_tuple(name))
  end

  @doc """
  Executes a function through the circuit breaker.
  """
  def call(name, fun, timeout \\ 5000) when is_function(fun, 0) do
    GenServer.call(via_tuple(name), {:call, fun}, timeout)
  end

  @doc """
  Gets the current state of the circuit breaker.
  """
  def get_state(name) do
    GenServer.call(via_tuple(name), :get_state)
  end

  @doc """
  Gets circuit breaker metrics.
  """
  def get_metrics(name) do
    GenServer.call(via_tuple(name), :get_metrics)
  end

  @doc """
  Manually opens the circuit breaker.
  """
  def open_circuit(name) do
    GenServer.call(via_tuple(name), :open_circuit)
  end

  @doc """
  Manually closes the circuit breaker.
  """
  def close_circuit(name) do
    GenServer.call(via_tuple(name), :close_circuit)
  end

  @doc """
  Executes a function with retry logic and exponential backoff.
  """
  def with_retry(fun, opts \\ %{}) when is_function(fun, 0) do
    max_retries = Map.get(opts, :max_retries, @default_max_retries)
    base_delay_ms = Map.get(opts, :base_delay_ms, 100)
    max_delay_ms = Map.get(opts, :max_delay_ms, 30_000)
    backoff_multiplier = Map.get(opts, :backoff_multiplier, 2.0)

    do_retry(fun, 0, max_retries, base_delay_ms, max_delay_ms, backoff_multiplier)
  end

  @doc """
  Categorizes an error for appropriate handling strategy.
  """
  def categorize_error(error) do
    case error do
      {:error, :timeout} -> :timeout
      {:error, :econnrefused} -> :transient
      {:error, :nxdomain} -> :permanent
      {:error, :rate_limited} -> :rate_limited
      {:error, %HTTPoison.Error{reason: :timeout}} -> :timeout
      {:error, %HTTPoison.Error{reason: :econnrefused}} -> :transient
      {:error, %HTTPoison.Error{reason: :nxdomain}} -> :permanent
      {:exit, :timeout} -> :timeout
      {:exit, {:timeout, _}} -> :timeout
      _ -> :unknown
    end
  end

  @doc """
  Determines if an error should be retried based on its category.
  """
  def should_retry?(error_category, attempt, max_retries) do
    case error_category do
      :transient -> attempt < max_retries
      :timeout -> attempt < max_retries
      :rate_limited -> attempt < max_retries
      :permanent -> false
      :unknown -> attempt < max(1, div(max_retries, 2))  # Fewer retries for unknown errors
    end
  end

  @doc """
  Calculates the delay for the next retry attempt.
  """
  def calculate_retry_delay(attempt, base_delay_ms, max_delay_ms, backoff_multiplier) do
    delay = base_delay_ms * :math.pow(backoff_multiplier, attempt)
    min(trunc(delay), max_delay_ms)
  end

  @doc """
  Wraps a function call with timeout handling.
  """
  def with_timeout(fun, timeout_ms) when is_function(fun, 0) do
    task = Task.async(fun)

    case Task.yield(task, timeout_ms) do
      {:ok, result} -> result
      nil ->
        Task.shutdown(task)
        {:error, :timeout}
    end
  end

  @doc """
  Creates a rate limiter for function calls.
  """
  def rate_limit(name, max_calls, window_ms) do
    case :ets.lookup(:rate_limiters, name) do
      [] ->
        :ets.insert(:rate_limiters, {name, [], window_ms, max_calls})
        :ok
      [{^name, calls, ^window_ms, ^max_calls}] ->
        now = System.monotonic_time(:millisecond)
        recent_calls = Enum.filter(calls, fn call_time -> now - call_time < window_ms end)

        if length(recent_calls) >= max_calls do
          {:error, :rate_limited}
        else
          new_calls = [now | recent_calls]
          :ets.insert(:rate_limiters, {name, new_calls, window_ms, max_calls})
          :ok
        end
    end
  end

  ## GenServer Callbacks

  @impl true
  def init({name, opts}) do
    # Initialize ETS table for rate limiting if it doesn't exist
    case :ets.whereis(:rate_limiters) do
      :undefined -> :ets.new(:rate_limiters, [:set, :public, :named_table])
      _ -> :ok
    end

    state = %__MODULE__{
      name: name,
      state: :closed,
      failure_count: 0,
      failure_threshold: Map.get(opts, :failure_threshold, @default_failure_threshold),
      recovery_timeout_ms: Map.get(opts, :recovery_timeout_ms, @default_recovery_timeout_ms),
      last_failure_time: nil,
      request_timeout_ms: Map.get(opts, :request_timeout_ms, @default_request_timeout_ms),
      half_open_max_calls: Map.get(opts, :half_open_max_calls, 1),
      half_open_success_count: 0,
      metrics: init_metrics()
    }

    Logger.info("Circuit breaker started: #{name}")
    {:ok, state}
  end

  @impl true
  def handle_call({:call, fun}, _from, state) do
    case state.state do
      :closed ->
        handle_closed_call(fun, state)

      :open ->
        handle_open_call(state)

      :half_open ->
        handle_half_open_call(fun, state)
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.state, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  @impl true
  def handle_call(:open_circuit, _from, state) do
    new_state = %{state |
      state: :open,
      last_failure_time: System.monotonic_time(:millisecond)
    }
    Logger.warning("Circuit breaker manually opened: #{state.name}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:close_circuit, _from, state) do
    new_state = %{state |
      state: :closed,
      failure_count: 0,
      half_open_success_count: 0
    }
    Logger.info("Circuit breaker manually closed: #{state.name}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:check_recovery, state) do
    if state.state == :open and should_attempt_recovery?(state) do
      new_state = %{state | state: :half_open, half_open_success_count: 0}
      Logger.info("Circuit breaker attempting recovery: #{state.name}")
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Circuit breaker terminating: #{state.name}, reason: #{inspect(reason)}")
    :ok
  end

  ## Private Functions

  defp via_tuple(name) do
    {:via, Registry, {LivekitexAgent.CircuitBreakerRegistry, name}}
  end

  defp handle_closed_call(fun, state) do
    start_time = System.monotonic_time(:millisecond)

    result = try do
      with_timeout(fun, state.request_timeout_ms)
    rescue
      e -> {:error, e}
    catch
      :exit, reason -> {:exit, reason}
    end

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:error, _} = error ->
        new_state = handle_failure(error, state)
        new_metrics = update_metrics(state.metrics, :failure, duration)
        {:reply, result, %{new_state | metrics: new_metrics}}

      {:exit, _} = exit_reason ->
        new_state = handle_failure(exit_reason, state)
        new_metrics = update_metrics(state.metrics, :failure, duration)
        {:reply, {:error, :circuit_breaker_failure}, %{new_state | metrics: new_metrics}}

      success_result ->
        new_state = handle_success(state)
        new_metrics = update_metrics(state.metrics, :success, duration)
        {:reply, success_result, %{new_state | metrics: new_metrics}}
    end
  end

  defp handle_open_call(state) do
    if should_attempt_recovery?(state) do
      new_state = %{state | state: :half_open, half_open_success_count: 0}
      {:reply, {:error, :circuit_breaker_open}, new_state}
    else
      new_metrics = update_metrics(state.metrics, :rejected, 0)
      {:reply, {:error, :circuit_breaker_open}, %{state | metrics: new_metrics}}
    end
  end

  defp handle_half_open_call(fun, state) do
    start_time = System.monotonic_time(:millisecond)

    result = try do
      with_timeout(fun, state.request_timeout_ms)
    rescue
      e -> {:error, e}
    catch
      :exit, reason -> {:exit, reason}
    end

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:error, _} = _error ->
        # Failure in half-open state, go back to open
        new_state = %{state |
          state: :open,
          failure_count: state.failure_count + 1,
          last_failure_time: System.monotonic_time(:millisecond)
        }
        schedule_recovery_check(new_state)
        new_metrics = update_metrics(state.metrics, :failure, duration)
        {:reply, result, %{new_state | metrics: new_metrics}}

      {:exit, _} ->
        # Exit in half-open state, go back to open
        new_state = %{state |
          state: :open,
          failure_count: state.failure_count + 1,
          last_failure_time: System.monotonic_time(:millisecond)
        }
        schedule_recovery_check(new_state)
        new_metrics = update_metrics(state.metrics, :failure, duration)
        {:reply, {:error, :circuit_breaker_failure}, %{new_state | metrics: new_metrics}}

      success_result ->
        # Success in half-open state
        new_success_count = state.half_open_success_count + 1

        new_state = if new_success_count >= state.half_open_max_calls do
          # Enough successes, close the circuit
          Logger.info("Circuit breaker recovered: #{state.name}")
          %{state |
            state: :closed,
            failure_count: 0,
            half_open_success_count: 0
          }
        else
          %{state | half_open_success_count: new_success_count}
        end

        new_metrics = update_metrics(state.metrics, :success, duration)
        {:reply, success_result, %{new_state | metrics: new_metrics}}
    end
  end

  defp handle_failure(error, state) do
    _error_category = categorize_error(error)
    new_failure_count = state.failure_count + 1

    Logger.warning("Circuit breaker failure #{new_failure_count}: #{state.name}, error: #{inspect(error)}")

    if new_failure_count >= state.failure_threshold do
      # Open the circuit
      new_state = %{state |
        state: :open,
        failure_count: new_failure_count,
        last_failure_time: System.monotonic_time(:millisecond)
      }
      schedule_recovery_check(new_state)
      Logger.error("Circuit breaker opened: #{state.name}")
      new_state
    else
      %{state | failure_count: new_failure_count}
    end
  end

  defp handle_success(state) do
    if state.failure_count > 0 do
      Logger.info("Circuit breaker failure count reset: #{state.name}")
    end

    %{state | failure_count: 0}
  end

  defp should_attempt_recovery?(state) do
    case state.last_failure_time do
      nil -> true
      last_failure ->
        now = System.monotonic_time(:millisecond)
        now - last_failure >= state.recovery_timeout_ms
    end
  end

  defp schedule_recovery_check(state) do
    Process.send_after(self(), :check_recovery, state.recovery_timeout_ms)
  end

  defp init_metrics do
    %{
      total_calls: 0,
      successful_calls: 0,
      failed_calls: 0,
      rejected_calls: 0,
      average_response_time: 0.0,
      state_changes: 0,
      last_state_change: DateTime.utc_now()
    }
  end

  defp update_metrics(metrics, call_type, duration) do
    new_total = metrics.total_calls + 1

    updated = case call_type do
      :success ->
        new_successful = metrics.successful_calls + 1
        new_avg = calculate_average_response_time(
          metrics.average_response_time,
          duration,
          new_total
        )
        %{metrics | successful_calls: new_successful, average_response_time: new_avg}

      :failure ->
        %{metrics | failed_calls: metrics.failed_calls + 1}

      :rejected ->
        %{metrics | rejected_calls: metrics.rejected_calls + 1}
    end

    %{updated | total_calls: new_total}
  end

  defp calculate_average_response_time(current_avg, new_duration, total_calls) do
    (current_avg * (total_calls - 1) + new_duration) / total_calls
  end

  # Retry implementation
  defp do_retry(fun, attempt, max_retries, base_delay_ms, max_delay_ms, backoff_multiplier) do
    case fun.() do
      {:error, _} = error when attempt < max_retries ->
        error_category = categorize_error(error)

        if should_retry?(error_category, attempt, max_retries) do
          delay = calculate_retry_delay(attempt, base_delay_ms, max_delay_ms, backoff_multiplier)

          # Add jitter to prevent thundering herd
          jittered_delay = delay + :rand.uniform(div(delay, 10) + 1)

          Logger.debug("Retrying after #{jittered_delay}ms, attempt #{attempt + 1}/#{max_retries}")
          Process.sleep(jittered_delay)

          do_retry(fun, attempt + 1, max_retries, base_delay_ms, max_delay_ms, backoff_multiplier)
        else
          Logger.warning("Not retrying #{error_category} error: #{inspect(error)}")
          error
        end

      result ->
        if attempt > 0 do
          Logger.info("Operation succeeded after #{attempt} retries")
        end
        result
    end
  end
end
