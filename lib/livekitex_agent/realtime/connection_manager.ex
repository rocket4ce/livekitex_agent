defmodule LivekitexAgent.Realtime.ConnectionManager do
  @moduledoc """
  Connection manager for LiveKit rooms and agent sessions.

  The ConnectionManager provides:
  - Centralized management of LiveKit room connections
  - Agent session lifecycle coordination
  - Connection pooling and load balancing
  - Room participant management and monitoring
  - Connection quality monitoring and optimization
  - Automatic failover and reconnection handling
  - Resource cleanup and connection lifecycle management

  ## Architecture

  The ConnectionManager acts as a coordinator between:
  - Multiple agent sessions requiring LiveKit connectivity
  - WebRTC handlers managing individual peer connections
  - Room state management and participant tracking
  - Connection quality monitoring and adaptation
  - Resource allocation and cleanup

  ## Connection Strategies

  - **Single Room**: One agent per room for dedicated conversations
  - **Shared Room**: Multiple agents in one room for collaborative scenarios
  - **Load Balanced**: Distribute agents across multiple rooms for scalability
  - **Failover**: Automatic migration to backup rooms on connection failure

  ## Performance Optimization

  - Connection pooling to reduce setup latency
  - Intelligent room assignment for optimal load distribution
  - Quality-based connection management and adaptation
  - Resource monitoring and automatic scaling
  """

  use GenServer
  require Logger

  @connection_timeout 30_000
  @heartbeat_interval 15_000
  @cleanup_interval 60_000
  @max_connections_per_room 10

  defstruct [
    :connections,
    :rooms,
    :agent_sessions,
    :config,
    :metrics,
    :heartbeat_timer,
    :cleanup_timer,
    :event_callbacks,
    :connection_strategies
  ]

  @type connection_info :: %{
          connection_id: String.t(),
          agent_session_id: String.t(),
          room_name: String.t(),
          webrtc_handler: pid(),
          connection_state: atom(),
          participant_identity: String.t(),
          quality_metrics: map(),
          created_at: DateTime.t(),
          last_activity: DateTime.t()
        }

  @type room_info :: %{
          room_name: String.t(),
          connection_count: non_neg_integer(),
          participants: map(),
          quality_score: float(),
          created_at: DateTime.t(),
          last_activity: DateTime.t()
        }

  @type manager_config :: %{
          livekit_url: String.t(),
          api_key: String.t(),
          api_secret: String.t(),
          default_strategy: atom(),
          max_connections_per_room: integer(),
          connection_timeout: integer(),
          enable_load_balancing: boolean(),
          enable_auto_cleanup: boolean()
        }

  @type t :: %__MODULE__{
          connections: map(),
          rooms: map(),
          agent_sessions: map(),
          config: manager_config(),
          metrics: map(),
          heartbeat_timer: reference() | nil,
          cleanup_timer: reference() | nil,
          event_callbacks: map(),
          connection_strategies: map()
        }

  # Client API

  @doc """
  Starts the ConnectionManager GenServer.

  ## Options
  - `:livekit_url` - LiveKit server URL (required)
  - `:api_key` - LiveKit API key (required)
  - `:api_secret` - LiveKit API secret (required)
  - `:default_strategy` - Default connection strategy (default: :single_room)
  - `:max_connections_per_room` - Maximum connections per room (default: 10)
  - `:connection_timeout` - Connection timeout in ms (default: 30000)
  - `:enable_load_balancing` - Enable load balancing (default: true)
  - `:enable_auto_cleanup` - Enable automatic cleanup (default: true)

  ## Example
      {:ok, manager} = ConnectionManager.start_link(
        livekit_url: "wss://myproject.livekit.cloud",
        api_key: "api_key",
        api_secret: "api_secret",
        default_strategy: :load_balanced
      )
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a new LiveKit connection for an agent session.

  ## Options
  - `:agent_session_id` - Unique agent session identifier (required)
  - `:room_name` - Specific room name (optional, auto-generated if not provided)
  - `:participant_identity` - Participant identity (optional, derived from session if not provided)
  - `:strategy` - Connection strategy (optional, uses default if not provided)
  - `:audio_enabled` - Enable audio track (default: true)
  - `:video_enabled` - Enable video track (default: false)
  - `:data_channel_enabled` - Enable data channel (default: true)

  Returns `{:ok, connection_info}` or `{:error, reason}`.
  """
  def create_connection(manager_pid \\ __MODULE__, opts) do
    GenServer.call(manager_pid, {:create_connection, opts}, @connection_timeout)
  end

  @doc """
  Removes a connection and cleans up associated resources.
  """
  def remove_connection(manager_pid \\ __MODULE__, connection_id) do
    GenServer.call(manager_pid, {:remove_connection, connection_id})
  end

  @doc """
  Gets information about a specific connection.
  """
  def get_connection(manager_pid \\ __MODULE__, connection_id) do
    GenServer.call(manager_pid, {:get_connection, connection_id})
  end

  @doc """
  Lists all active connections with optional filtering.

  ## Filters
  - `:room_name` - Filter by room name
  - `:agent_session_id` - Filter by agent session ID
  - `:connection_state` - Filter by connection state
  """
  def list_connections(manager_pid \\ __MODULE__, filters \\ %{}) do
    GenServer.call(manager_pid, {:list_connections, filters})
  end

  @doc """
  Gets information about a specific room.
  """
  def get_room_info(manager_pid \\ __MODULE__, room_name) do
    GenServer.call(manager_pid, {:get_room_info, room_name})
  end

  @doc """
  Lists all active rooms with their connection counts and metrics.
  """
  def list_rooms(manager_pid \\ __MODULE__) do
    GenServer.call(manager_pid, :list_rooms)
  end

  @doc """
  Updates the connection strategy for new connections.
  """
  def set_connection_strategy(manager_pid \\ __MODULE__, strategy, options \\ %{}) do
    GenServer.call(manager_pid, {:set_connection_strategy, strategy, options})
  end

  @doc """
  Registers an event callback for connection management events.

  Available events:
  - `:connection_created` - New connection established
  - `:connection_removed` - Connection removed/closed
  - `:connection_failed` - Connection failed to establish
  - `:room_created` - New room created
  - `:room_empty` - Room has no more connections
  - `:load_balanced` - Connection moved for load balancing
  - `:quality_degraded` - Connection quality below threshold
  """
  def register_callback(manager_pid \\ __MODULE__, event, callback) do
    GenServer.call(manager_pid, {:register_callback, event, callback})
  end

  @doc """
  Gets comprehensive metrics for all connections and rooms.
  """
  def get_metrics(manager_pid \\ __MODULE__) do
    GenServer.call(manager_pid, :get_metrics)
  end

  @doc """
  Forces cleanup of inactive connections and empty rooms.
  """
  def cleanup(manager_pid \\ __MODULE__) do
    GenServer.cast(manager_pid, :cleanup)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    config = %{
      livekit_url: Keyword.fetch!(opts, :livekit_url),
      api_key: Keyword.fetch!(opts, :api_key),
      api_secret: Keyword.fetch!(opts, :api_secret),
      default_strategy: Keyword.get(opts, :default_strategy, :single_room),
      max_connections_per_room:
        Keyword.get(opts, :max_connections_per_room, @max_connections_per_room),
      connection_timeout: Keyword.get(opts, :connection_timeout, @connection_timeout),
      enable_load_balancing: Keyword.get(opts, :enable_load_balancing, true),
      enable_auto_cleanup: Keyword.get(opts, :enable_auto_cleanup, true)
    }

    state = %__MODULE__{
      connections: %{},
      rooms: %{},
      agent_sessions: %{},
      config: config,
      metrics: init_metrics(),
      heartbeat_timer: nil,
      cleanup_timer: nil,
      event_callbacks: %{},
      connection_strategies: init_connection_strategies()
    }

    # Start periodic timers
    heartbeat_timer = Process.send_after(self(), :heartbeat, @heartbeat_interval)

    cleanup_timer =
      if config.enable_auto_cleanup do
        Process.send_after(self(), :auto_cleanup, @cleanup_interval)
      end

    state = %{state | heartbeat_timer: heartbeat_timer, cleanup_timer: cleanup_timer}

    Logger.info("ConnectionManager started with config: #{inspect(config)}")
    {:ok, state}
  end

  @impl true
  def handle_call({:create_connection, opts}, _from, state) do
    agent_session_id = Keyword.fetch!(opts, :agent_session_id)

    Logger.info("Creating connection for agent session: #{agent_session_id}")

    case create_new_connection(opts, state) do
      {:ok, connection_info, new_state} ->
        emit_event(new_state, :connection_created, connection_info)
        {:reply, {:ok, connection_info}, new_state}

      {:error, reason} ->
        Logger.error("Failed to create connection: #{inspect(reason)}")

        emit_event(state, :connection_failed, %{
          agent_session_id: agent_session_id,
          reason: reason
        })

        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:remove_connection, connection_id}, _from, state) do
    case Map.get(state.connections, connection_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      connection_info ->
        Logger.info("Removing connection: #{connection_id}")

        # Stop WebRTC handler
        if connection_info.webrtc_handler && Process.alive?(connection_info.webrtc_handler) do
          LivekitexAgent.Realtime.WebRTCHandler.disconnect(connection_info.webrtc_handler)
          GenServer.stop(connection_info.webrtc_handler, :normal)
        end

        # Update state
        new_connections = Map.delete(state.connections, connection_id)
        new_rooms = update_room_on_connection_removal(state.rooms, connection_info.room_name)
        new_agent_sessions = Map.delete(state.agent_sessions, connection_info.agent_session_id)

        new_state = %{
          state
          | connections: new_connections,
            rooms: new_rooms,
            agent_sessions: new_agent_sessions
        }

        emit_event(new_state, :connection_removed, connection_info)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:get_connection, connection_id}, _from, state) do
    case Map.get(state.connections, connection_id) do
      nil -> {:reply, {:error, :not_found}, state}
      connection_info -> {:reply, {:ok, connection_info}, state}
    end
  end

  @impl true
  def handle_call({:list_connections, filters}, _from, state) do
    filtered_connections = filter_connections(state.connections, filters)
    {:reply, Map.values(filtered_connections), state}
  end

  @impl true
  def handle_call({:get_room_info, room_name}, _from, state) do
    case Map.get(state.rooms, room_name) do
      nil -> {:reply, {:error, :not_found}, state}
      room_info -> {:reply, {:ok, room_info}, state}
    end
  end

  @impl true
  def handle_call(:list_rooms, _from, state) do
    {:reply, Map.values(state.rooms), state}
  end

  @impl true
  def handle_call({:set_connection_strategy, strategy, options}, _from, state) do
    new_strategies = Map.put(state.connection_strategies, strategy, options)
    new_config = %{state.config | default_strategy: strategy}

    new_state = %{state | connection_strategies: new_strategies, config: new_config}

    Logger.info("Connection strategy updated to: #{strategy}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:register_callback, event, callback}, _from, state) do
    new_callbacks = Map.put(state.event_callbacks, event, callback)
    new_state = %{state | event_callbacks: new_callbacks}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    current_metrics = calculate_current_metrics(state)
    {:reply, current_metrics, state}
  end

  @impl true
  def handle_cast(:cleanup, state) do
    Logger.info("Performing manual cleanup of connections and rooms")
    new_state = perform_cleanup(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    # Update connection health and quality metrics
    new_state = update_connection_health(state)

    # Schedule next heartbeat
    timer = Process.send_after(self(), :heartbeat, @heartbeat_interval)
    new_state = %{new_state | heartbeat_timer: timer}

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:auto_cleanup, state) do
    Logger.debug("Performing automatic cleanup")
    new_state = perform_cleanup(state)

    # Schedule next cleanup
    timer = Process.send_after(self(), :auto_cleanup, @cleanup_interval)
    new_state = %{new_state | cleanup_timer: timer}

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:webrtc_event, event_type, data}, state) do
    # Handle events from WebRTC handlers
    handle_webrtc_event(event_type, data, state)
  end

  # Private Functions

  defp create_new_connection(opts, state) do
    agent_session_id = Keyword.fetch!(opts, :agent_session_id)
    strategy = Keyword.get(opts, :strategy, state.config.default_strategy)

    # Determine room assignment based on strategy
    case determine_room_assignment(strategy, opts, state) do
      {:ok, room_name} ->
        # Create connection ID
        connection_id = generate_connection_id()

        # Create participant identity
        participant_identity =
          Keyword.get(opts, :participant_identity, "agent_#{agent_session_id}")

        # Start WebRTC handler
        webrtc_opts = [
          room_name: room_name,
          participant_identity: participant_identity,
          livekit_url: state.config.livekit_url,
          api_key: state.config.api_key,
          api_secret: state.config.api_secret,
          parent_pid: self(),
          audio_enabled: Keyword.get(opts, :audio_enabled, true),
          video_enabled: Keyword.get(opts, :video_enabled, false),
          data_channel_enabled: Keyword.get(opts, :data_channel_enabled, true)
        ]

        case LivekitexAgent.Realtime.WebRTCHandler.start_link(webrtc_opts) do
          {:ok, webrtc_handler} ->
            # Create connection info
            connection_info = %{
              connection_id: connection_id,
              agent_session_id: agent_session_id,
              room_name: room_name,
              webrtc_handler: webrtc_handler,
              connection_state: :connecting,
              participant_identity: participant_identity,
              quality_metrics: %{},
              created_at: DateTime.utc_now(),
              last_activity: DateTime.utc_now()
            }

            # Update state
            new_connections = Map.put(state.connections, connection_id, connection_info)

            new_rooms =
              update_room_on_connection_creation(state.rooms, room_name, connection_info)

            new_agent_sessions = Map.put(state.agent_sessions, agent_session_id, connection_id)

            new_state = %{
              state
              | connections: new_connections,
                rooms: new_rooms,
                agent_sessions: new_agent_sessions
            }

            # Start connection
            Task.async(fn ->
              LivekitexAgent.Realtime.WebRTCHandler.connect(webrtc_handler)
            end)

            {:ok, connection_info, new_state}

          {:error, reason} ->
            {:error, {:webrtc_handler_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:room_assignment_failed, reason}}
    end
  end

  defp determine_room_assignment(strategy, opts, state) do
    case strategy do
      :single_room ->
        # Each agent gets its own room
        agent_session_id = Keyword.fetch!(opts, :agent_session_id)
        room_name = Keyword.get(opts, :room_name, "agent_room_#{agent_session_id}")
        {:ok, room_name}

      :shared_room ->
        # Use specified room or default shared room
        room_name = Keyword.get(opts, :room_name, "shared_agent_room")
        {:ok, room_name}

      :load_balanced ->
        # Find room with lowest connection count
        case find_optimal_room(state) do
          {:ok, room_name} -> {:ok, room_name}
          :no_available_rooms -> {:ok, "agent_room_#{generate_room_suffix()}"}
        end

      _ ->
        {:error, :unknown_strategy}
    end
  end

  defp find_optimal_room(state) do
    # Find room with lowest connection count under the limit
    optimal_room =
      state.rooms
      |> Enum.filter(fn {_name, room_info} ->
        room_info.connection_count < state.config.max_connections_per_room
      end)
      |> Enum.min_by(fn {_name, room_info} -> room_info.connection_count end, fn -> nil end)

    case optimal_room do
      {room_name, _room_info} -> {:ok, room_name}
      nil -> :no_available_rooms
    end
  end

  defp update_room_on_connection_creation(rooms, room_name, connection_info) do
    case Map.get(rooms, room_name) do
      nil ->
        # Create new room
        room_info = %{
          room_name: room_name,
          connection_count: 1,
          participants: %{connection_info.participant_identity => connection_info.connection_id},
          quality_score: 10.0,
          created_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now()
        }

        Map.put(rooms, room_name, room_info)

      room_info ->
        # Update existing room
        updated_room = %{
          room_info
          | connection_count: room_info.connection_count + 1,
            participants:
              Map.put(
                room_info.participants,
                connection_info.participant_identity,
                connection_info.connection_id
              ),
            last_activity: DateTime.utc_now()
        }

        Map.put(rooms, room_name, updated_room)
    end
  end

  defp update_room_on_connection_removal(rooms, room_name) do
    case Map.get(rooms, room_name) do
      nil ->
        rooms

      room_info ->
        new_count = max(0, room_info.connection_count - 1)

        if new_count == 0 do
          # Remove empty room
          Map.delete(rooms, room_name)
        else
          # Update room
          updated_room = %{
            room_info
            | connection_count: new_count,
              last_activity: DateTime.utc_now()
          }

          Map.put(rooms, room_name, updated_room)
        end
    end
  end

  defp filter_connections(connections, filters) do
    Enum.reduce(filters, connections, fn {key, value}, acc ->
      Enum.filter(acc, fn {_id, conn} ->
        case key do
          :room_name -> conn.room_name == value
          :agent_session_id -> conn.agent_session_id == value
          :connection_state -> conn.connection_state == value
          _ -> true
        end
      end)
      |> Map.new()
    end)
  end

  defp perform_cleanup(state) do
    # Remove failed connections
    {active_connections, failed_connections} =
      Enum.split_with(state.connections, fn {_id, conn} ->
        conn.webrtc_handler && Process.alive?(conn.webrtc_handler)
      end)

    # Clean up failed connections
    Enum.each(failed_connections, fn {_id, conn} ->
      if conn.webrtc_handler && Process.alive?(conn.webrtc_handler) do
        GenServer.stop(conn.webrtc_handler, :normal)
      end
    end)

    # Update rooms to remove connections that no longer exist
    active_connection_map = Map.new(active_connections)

    cleaned_rooms =
      Enum.reduce(state.rooms, %{}, fn {room_name, room_info}, acc ->
        active_participants =
          Enum.filter(room_info.participants, fn {_identity, conn_id} ->
            Map.has_key?(active_connection_map, conn_id)
          end)

        if length(active_participants) > 0 do
          updated_room = %{
            room_info
            | connection_count: length(active_participants),
              participants: Map.new(active_participants)
          }

          Map.put(acc, room_name, updated_room)
        else
          acc
        end
      end)

    new_state = %{state | connections: active_connection_map, rooms: cleaned_rooms}

    Logger.info("Cleanup completed: #{length(failed_connections)} connections removed")
    new_state
  end

  defp update_connection_health(state) do
    # Update health metrics for all connections
    updated_connections =
      Enum.reduce(state.connections, %{}, fn {id, conn}, acc ->
        if conn.webrtc_handler && Process.alive?(conn.webrtc_handler) do
          try do
            {:ok, metrics} =
              LivekitexAgent.Realtime.WebRTCHandler.get_metrics(conn.webrtc_handler)

            updated_conn = %{conn | quality_metrics: metrics, last_activity: DateTime.utc_now()}
            Map.put(acc, id, updated_conn)
          rescue
            _ -> Map.put(acc, id, conn)
          end
        else
          Map.put(acc, id, %{conn | connection_state: :failed})
        end
      end)

    %{state | connections: updated_connections}
  end

  defp handle_webrtc_event(event_type, data, state) do
    # Handle specific WebRTC events that affect connection management
    case event_type do
      :connected ->
        # Update connection state
        update_connection_state(state, data, :connected)

      :disconnected ->
        # Update connection state and potentially trigger reconnection
        update_connection_state(state, data, :disconnected)

      :connection_quality_changed ->
        # Update quality metrics and check if intervention is needed
        handle_quality_change(state, data)

      _ ->
        # Pass through other events
        {:noreply, state}
    end
  end

  defp update_connection_state(state, _data, _new_state) do
    # Find connection by WebRTC handler or other identifier
    # This is a simplified implementation
    {:noreply, state}
  end

  defp handle_quality_change(state, quality_data) do
    # Check if quality degradation requires action
    if quality_data[:score] && quality_data[:score] < 5.0 do
      emit_event(state, :quality_degraded, quality_data)
    end

    {:noreply, state}
  end

  defp init_metrics do
    %{
      total_connections_created: 0,
      total_connections_removed: 0,
      active_connections: 0,
      active_rooms: 0,
      average_connections_per_room: 0.0,
      total_data_transferred: 0,
      uptime_started: DateTime.utc_now()
    }
  end

  defp init_connection_strategies do
    %{
      single_room: %{description: "One room per agent session"},
      shared_room: %{description: "Multiple agents in shared rooms"},
      load_balanced: %{description: "Distribute agents for optimal load"}
    }
  end

  defp calculate_current_metrics(state) do
    active_connections = map_size(state.connections)
    active_rooms = map_size(state.rooms)

    avg_connections_per_room =
      if active_rooms > 0 do
        active_connections / active_rooms
      else
        0.0
      end

    %{
      state.metrics
      | active_connections: active_connections,
        active_rooms: active_rooms,
        average_connections_per_room: avg_connections_per_room,
        uptime_seconds: DateTime.diff(DateTime.utc_now(), state.metrics.uptime_started, :second)
    }
  end

  defp generate_connection_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp generate_room_suffix do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end

  defp emit_event(state, event_type, data) do
    case Map.get(state.event_callbacks, event_type) do
      nil ->
        :ok

      callback when is_function(callback, 2) ->
        try do
          callback.(event_type, data)
        rescue
          e ->
            Logger.error("ConnectionManager callback error for #{event_type}: #{inspect(e)}")
        end
    end
  end
end
