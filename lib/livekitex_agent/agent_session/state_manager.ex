defmodule LivekitexAgent.AgentSession.StateManager do
  @moduledoc """
  Persistent state management for agent conversations.

  The StateManager provides:
  - Multiple storage backends (ETS, file system, database)
  - Conversation state serialization and deserialization
  - Turn history persistence and recovery
  - Automatic cleanup of expired states
  - Compression and encryption support
  - Backup and restore capabilities

  ## Storage Backends

  ### ETS Backend
  - Fast in-memory storage with optional persistence to disk
  - Suitable for development and single-node deployments
  - Automatic TTL-based cleanup

  ### File Backend
  - JSON-based file storage with compression
  - Suitable for small to medium deployments
  - Human-readable format for debugging

  ### Database Backend (Future)
  - PostgreSQL/MySQL integration for production deployments
  - Full ACID compliance and replication support
  - Advanced querying and analytics capabilities

  ## Data Structure

  Persisted conversation state includes:
  - Session metadata (ID, created_at, participants)
  - Complete turn history with timestamps
  - Conversation context and custom data
  - Audio/media processing state
  - Tool execution history and results
  - Performance metrics and quality data
  """

  require Logger

  @ets_table_name :agent_conversation_states
  @default_storage_path "./conversation_states"
  @default_ttl 86_400  # 24 hours in seconds

  @type storage_backend :: :ets | :file | :database
  @type storage_options :: [
    storage_backend: storage_backend(),
    storage_path: String.t(),
    compression: boolean(),
    ttl: pos_integer(),
    encryption_key: binary() | nil
  ]

  @type conversation_state :: %{
    session_id: String.t(),
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    conversation_state: map(),
    turn_history: list(),
    participants: map(),
    room_id: String.t() | nil,
    metadata: map(),
    performance_metrics: map()
  }

  # Public API

  @doc """
  Initializes the state manager and storage backends.

  Should be called during application startup.
  """
  def init do
    # Initialize ETS table for fast access
    case :ets.whereis(@ets_table_name) do
      :undefined ->
        :ets.new(@ets_table_name, [
          :set,
          :public,
          :named_table,
          {:read_concurrency, true},
          {:write_concurrency, true}
        ])
        Logger.info("StateManager ETS table initialized")

      _ ->
        Logger.debug("StateManager ETS table already exists")
    end

    # Ensure default storage directory exists
    File.mkdir_p!(@default_storage_path)

    # Start cleanup process
    start_cleanup_process()

    :ok
  end

  @doc """
  Saves conversation state to persistent storage.

  ## Options
  - `:storage_backend` - Backend to use (:ets, :file) (default: :ets)
  - `:storage_path` - Path for file storage (default: "./conversation_states")
  - `:compression` - Enable compression (default: true)
  - `:ttl` - Time-to-live in seconds (default: 86400)
  - `:encryption_key` - Encryption key for sensitive data (default: nil)
  """
  def save_state(session, opts \\ []) do
    storage_backend = Keyword.get(opts, :storage_backend, :ets)

    # Prepare state data for persistence
    state_data = prepare_state_data(session)

    case storage_backend do
      :ets -> save_to_ets(state_data, opts)
      :file -> save_to_file(state_data, opts)
      :database -> {:error, :not_implemented}
      _ -> {:error, :unknown_storage_backend}
    end
  end

  @doc """
  Loads conversation state from persistent storage.
  """
  def load_state(session_id, opts \\ []) do
    storage_backend = Keyword.get(opts, :storage_backend, :ets)

    case storage_backend do
      :ets -> load_from_ets(session_id, opts)
      :file -> load_from_file(session_id, opts)
      :database -> {:error, :not_implemented}
      _ -> {:error, :unknown_storage_backend}
    end
  end

  @doc """
  Deletes persisted conversation state.
  """
  def delete_state(session_id, opts \\ []) do
    storage_backend = Keyword.get(opts, :storage_backend, :ets)

    case storage_backend do
      :ets -> delete_from_ets(session_id)
      :file -> delete_from_file(session_id, opts)
      :database -> {:error, :not_implemented}
      _ -> {:error, :unknown_storage_backend}
    end
  end

  @doc """
  Lists all persisted conversation states.
  """
  def list_states(opts \\ []) do
    storage_backend = Keyword.get(opts, :storage_backend, :ets)

    case storage_backend do
      :ets -> list_from_ets()
      :file -> list_from_file(opts)
      :database -> {:error, :not_implemented}
      _ -> {:error, :unknown_storage_backend}
    end
  end

  @doc """
  Performs cleanup of expired conversation states.
  """
  def cleanup_expired_states(opts \\ []) do
    Logger.info("Starting cleanup of expired conversation states")

    # Cleanup ETS entries
    cleanup_ets_expired()

    # Cleanup file entries if file backend is used
    if Keyword.get(opts, :cleanup_files, true) do
      cleanup_file_expired(opts)
    end

    Logger.info("Cleanup completed")
    :ok
  end

  # Private Functions - Data Preparation

  defp prepare_state_data(session) do
    %{
      session_id: session.session_id,
      created_at: session.created_at || DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      conversation_state: session.conversation_state || %{},
      turn_history: session.turn_history || [],
      participants: session.participants || %{},
      room_id: session.room_id,
      metadata: %{
        status: session.status,
        last_activity_at: session.last_activity_at
      },
      performance_metrics: extract_performance_metrics(session)
    }
  end

  defp extract_performance_metrics(session) do
    %{
      total_turns: length(session.turn_history || []),
      session_duration: calculate_session_duration(session),
      last_activity: session.last_activity_at
    }
  end

  defp calculate_session_duration(session) do
    if session.created_at && session.last_activity_at do
      DateTime.diff(session.last_activity_at, session.created_at, :second)
    else
      0
    end
  end

  # Private Functions - ETS Storage

  defp save_to_ets(state_data, opts) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    expires_at = DateTime.add(DateTime.utc_now(), ttl, :second)

    storage_record = {
      state_data.session_id,
      state_data,
      expires_at
    }

    :ets.insert(@ets_table_name, storage_record)

    Logger.debug("Saved conversation state to ETS: #{state_data.session_id}")
    {:ok, %{session_id: state_data.session_id, expires_at: expires_at}}
  end

  defp load_from_ets(session_id, _opts) do
    case :ets.lookup(@ets_table_name, session_id) do
      [{^session_id, state_data, expires_at}] ->
        if DateTime.before?(DateTime.utc_now(), expires_at) do
          Logger.debug("Loaded conversation state from ETS: #{session_id}")
          {:ok, state_data}
        else
          Logger.debug("Conversation state expired in ETS: #{session_id}")
          :ets.delete(@ets_table_name, session_id)
          {:error, :expired}
        end

      [] ->
        Logger.debug("Conversation state not found in ETS: #{session_id}")
        {:error, :not_found}
    end
  end

  defp delete_from_ets(session_id) do
    :ets.delete(@ets_table_name, session_id)
    Logger.debug("Deleted conversation state from ETS: #{session_id}")
    :ok
  end

  defp list_from_ets do
    states = :ets.tab2list(@ets_table_name)
    |> Enum.filter(fn {_id, _data, expires_at} ->
      DateTime.before?(DateTime.utc_now(), expires_at)
    end)
    |> Enum.map(fn {session_id, state_data, expires_at} ->
      %{
        session_id: session_id,
        created_at: state_data.created_at,
        updated_at: state_data.updated_at,
        expires_at: expires_at,
        turn_count: length(state_data.turn_history),
        participant_count: map_size(state_data.participants)
      }
    end)

    {:ok, states}
  end

  defp cleanup_ets_expired do
    now = DateTime.utc_now()
    expired_keys = :ets.tab2list(@ets_table_name)
    |> Enum.filter(fn {_id, _data, expires_at} ->
      DateTime.after?(now, expires_at)
    end)
    |> Enum.map(fn {session_id, _data, _expires_at} -> session_id end)

    Enum.each(expired_keys, fn session_id ->
      :ets.delete(@ets_table_name, session_id)
    end)

    if length(expired_keys) > 0 do
      Logger.info("Cleaned up #{length(expired_keys)} expired ETS entries")
    end
  end

  # Private Functions - File Storage

  defp save_to_file(state_data, opts) do
    storage_path = Keyword.get(opts, :storage_path, @default_storage_path)
    compression = Keyword.get(opts, :compression, true)
    ttl = Keyword.get(opts, :ttl, @default_ttl)

    # Ensure directory exists
    File.mkdir_p!(storage_path)

    # Add expiration info
    expires_at = DateTime.add(DateTime.utc_now(), ttl, :second)
    file_data = Map.put(state_data, :expires_at, expires_at)

    # Prepare file path
    filename = "#{state_data.session_id}.json"
    filepath = Path.join(storage_path, filename)

    try do
      # Serialize data
      json_data = Jason.encode!(file_data)

      # Apply compression if enabled
      final_data = if compression do
        :zlib.compress(json_data)
      else
        json_data
      end

      # Write to file
      File.write!(filepath, final_data)

      Logger.debug("Saved conversation state to file: #{filepath}")
      {:ok, %{session_id: state_data.session_id, filepath: filepath, expires_at: expires_at}}

    rescue
      e ->
        Logger.error("Failed to save conversation state to file: #{inspect(e)}")
        {:error, {:file_write_failed, e}}
    end
  end

  defp load_from_file(session_id, opts) do
    storage_path = Keyword.get(opts, :storage_path, @default_storage_path)
    compression = Keyword.get(opts, :compression, true)

    filename = "#{session_id}.json"
    filepath = Path.join(storage_path, filename)

    try do
      case File.read(filepath) do
        {:ok, raw_data} ->
          # Decompress if needed
          json_data = if compression do
            :zlib.uncompress(raw_data)
          else
            raw_data
          end

          # Parse JSON
          state_data = Jason.decode!(json_data, keys: :atoms)

          # Check expiration
          if state_data[:expires_at] do
            expires_at = DateTime.from_iso8601(state_data.expires_at) |> elem(1)
            if DateTime.before?(DateTime.utc_now(), expires_at) do
              Logger.debug("Loaded conversation state from file: #{filepath}")
              {:ok, Map.delete(state_data, :expires_at)}
            else
              Logger.debug("Conversation state expired in file: #{filepath}")
              File.rm(filepath)
              {:error, :expired}
            end
          else
            # No expiration info, assume valid
            Logger.debug("Loaded conversation state from file (no expiration): #{filepath}")
            {:ok, state_data}
          end

        {:error, :enoent} ->
          Logger.debug("Conversation state file not found: #{filepath}")
          {:error, :not_found}

        {:error, reason} ->
          Logger.error("Failed to read conversation state file #{filepath}: #{inspect(reason)}")
          {:error, {:file_read_failed, reason}}
      end

    rescue
      e ->
        Logger.error("Failed to load conversation state from file: #{inspect(e)}")
        {:error, {:file_parse_failed, e}}
    end
  end

  defp delete_from_file(session_id, opts) do
    storage_path = Keyword.get(opts, :storage_path, @default_storage_path)
    filename = "#{session_id}.json"
    filepath = Path.join(storage_path, filename)

    case File.rm(filepath) do
      :ok ->
        Logger.debug("Deleted conversation state file: #{filepath}")
        :ok
      {:error, :enoent} ->
        Logger.debug("Conversation state file not found for deletion: #{filepath}")
        :ok
      {:error, reason} ->
        Logger.error("Failed to delete conversation state file #{filepath}: #{inspect(reason)}")
        {:error, {:file_delete_failed, reason}}
    end
  end

  defp list_from_file(opts) do
    storage_path = Keyword.get(opts, :storage_path, @default_storage_path)

    try do
      case File.ls(storage_path) do
        {:ok, files} ->
          states = files
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.map(fn filename ->
            session_id = String.replace_suffix(filename, ".json", "")
            case load_from_file(session_id, opts) do
              {:ok, state_data} ->
                %{
                  session_id: session_id,
                  created_at: state_data.created_at,
                  updated_at: state_data.updated_at,
                  turn_count: length(state_data.turn_history || []),
                  participant_count: map_size(state_data.participants || %{})
                }
              {:error, _} ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

          {:ok, states}

        {:error, reason} ->
          Logger.error("Failed to list conversation state files: #{inspect(reason)}")
          {:error, {:directory_read_failed, reason}}
      end

    rescue
      e ->
        Logger.error("Failed to list conversation states from files: #{inspect(e)}")
        {:error, {:file_listing_failed, e}}
    end
  end

  defp cleanup_file_expired(opts) do
    storage_path = Keyword.get(opts, :storage_path, @default_storage_path)

    case File.ls(storage_path) do
      {:ok, files} ->
        expired_files = files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.filter(fn filename ->
          session_id = String.replace_suffix(filename, ".json", "")
          case load_from_file(session_id, opts) do
            {:error, :expired} -> true
            _ -> false
          end
        end)

        Enum.each(expired_files, fn filename ->
          filepath = Path.join(storage_path, filename)
          File.rm(filepath)
        end)

        if length(expired_files) > 0 do
          Logger.info("Cleaned up #{length(expired_files)} expired file entries")
        end

      {:error, reason} ->
        Logger.error("Failed to cleanup expired files: #{inspect(reason)}")
    end
  end

  # Private Functions - Cleanup Process

  defp start_cleanup_process do
    # Start a periodic cleanup process
    spawn(fn ->
      cleanup_loop()
    end)
  end

  defp cleanup_loop do
    # Cleanup every hour
    Process.sleep(3_600_000)

    try do
      cleanup_expired_states()
    rescue
      e ->
        Logger.error("Cleanup process error: #{inspect(e)}")
    end

    cleanup_loop()
  end
end
