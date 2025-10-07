defmodule LivekitexAgent.RealtimeWSClient do
  @moduledoc """
  Minimal WebSocket client for realtime audio/text conversations with an LLM service.

  This module is designed to work with OpenAI's Realtime API over WebSocket, but keeps
  event names and some details configurable to avoid hard-coding protocol-specific bits.

  It streams microphone PCM16 audio chunks, sends text inputs, and relays server events
  back to a parent process (typically `LivekitexAgent.AgentSession`).

  Notes and assumptions (adjust via config if needed):
  - Server URL is a wss:// endpoint that accepts Bearer auth and a beta header.
  - Outgoing client events are JSON text frames.
  - Audio is base64-encoded PCM16 mono at a fixed sample rate (e.g., 16000 Hz).
  - Typical client events include:
      * "input_audio_buffer.append"  -> with base64 "audio" field
      * "input_audio_buffer.commit"  -> indicates end of user audio turn
      * "input_text.append" or "input_text" -> send text
      * "response.create"            -> ask server to produce an answer
      * "response.cancel"            -> interrupt current response
  - Typical server events include audio/text/status deltas and completions.
  """

  use WebSockex
  require Logger

  @typedoc "Configuration for the realtime websocket client"
  @type config :: %{
          required(:url) => String.t(),
          optional(:headers) => [{String.t(), String.t()}],
          optional(:model) => String.t(),
          optional(:sample_rate) => pos_integer(),
          optional(:protocol_header) => {String.t(), String.t()},
          optional(:auth_header) => {String.t(), String.t()},
          optional(:beta_header) => {String.t(), String.t()},
          optional(:extra_headers) => [{String.t(), String.t()}],
          optional(:client_event_names) => map(),
          optional(:server_event_audio_fields) => [String.t()],
          optional(:log_frames) => boolean(),
          optional(:api_key) => String.t()
        }

  defstruct [
    :parent,
    :config,
    :connected?,
    :pending_response,
    :last_ping_at
  ]

  @type t :: %__MODULE__{
          parent: pid(),
          config: config(),
          connected?: boolean(),
          pending_response: boolean(),
          last_ping_at: integer() | nil
        }

  # Public API

  @doc """
  Start the realtime client.

  Options:
  - :parent (required) -> pid to receive {:realtime_event, map} and {:realtime_closed, reason}
  - :config (required) -> map() with :url and optional headers/options
  """
  def start_link(opts) do
    parent = Keyword.fetch!(opts, :parent)
    config = Keyword.fetch!(opts, :config)

    headers =
      build_headers(config)
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    state = %__MODULE__{
      parent: parent,
      config: normalize_config(config),
      connected?: false,
      pending_response: false,
      last_ping_at: nil
    }

    WebSockex.start_link(config.url, __MODULE__, state, extra_headers: headers)
  end

  @doc """
  Send a raw client event map as a JSON text frame.
  """
  def send_event(pid, %{} = event) do
    WebSockex.cast(pid, {:send_event, event})
  end

  @doc """
  Append a PCM16 audio chunk (binary) to the input audio buffer.
  """
  def send_audio_chunk(pid, pcm16_binary) when is_binary(pcm16_binary) do
    WebSockex.cast(pid, {:send_audio, pcm16_binary})
  end

  @doc """
  Commit the input audio buffer to signal end of user turn.
  """
  def commit_input(pid) do
    WebSockex.cast(pid, :commit_input)
  end

  @doc """
  Send a text input to the model (appended into the current turn) and request a response.
  """
  def send_text(pid, text) when is_binary(text) do
    WebSockex.cast(pid, {:send_text, text})
  end

  @doc """
  Ask the server to create a response based on current buffer/context.
  """
  def request_response(pid, extra_opts \\ %{}) do
    WebSockex.cast(pid, {:request_response, extra_opts})
  end

  @doc """
  Cancel the current response if one is in progress.
  """
  def cancel_response(pid) do
    WebSockex.cast(pid, :cancel_response)
  end

  # WebSockex callbacks

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("RealtimeWS connected")
    send(state.parent, {:realtime_event, %{type: "socket.connected"}})
    {:ok, %{state | connected?: true}}
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    Logger.warning("RealtimeWS disconnected: #{inspect(reason)}")
    send(state.parent, {:realtime_closed, reason})
    {:ok, %{state | connected?: false}}
  end

  @impl true
  def handle_cast({:send_event, event}, state) do
    maybe_log_frame(state, :out, event)
    {:reply, {:text, Jason.encode!(event)}, state}
  end

  def handle_cast({:send_audio, pcm16}, state) do
    evt_name =
      get_in(state.config, [:client_event_names, :audio_append]) || "input_audio_buffer.append"

    audio_b64 = Base.encode64(pcm16)

    event = %{"type" => evt_name, "audio" => audio_b64}
    maybe_log_frame(state, :out, event)
    {:reply, {:text, Jason.encode!(event)}, state}
  end

  def handle_cast(:commit_input, state) do
    evt_name =
      get_in(state.config, [:client_event_names, :audio_commit]) || "input_audio_buffer.commit"

    event = %{"type" => evt_name}
    maybe_log_frame(state, :out, event)
    {:reply, {:text, Jason.encode!(event)}, state}
  end

  def handle_cast({:send_text, text}, state) do
    # Some servers accept input_text.append + response.create; keep it flexible
    append_evt = get_in(state.config, [:client_event_names, :text_append]) || "input_text.append"

    create_evt =
      get_in(state.config, [:client_event_names, :response_create]) || "response.create"

    append = %{"type" => append_evt, "text" => text}
    create = %{"type" => create_evt}

    maybe_log_frame(state, :out, append)
    maybe_log_frame(state, :out, create)

    # Send the first frame immediately, schedule the second one
    # WebSockex cannot handle multiple frames in one reply
    Process.send_after(self(), {:delayed_frame, Jason.encode!(create)}, 50)
    {:reply, {:text, Jason.encode!(append)}, %{state | pending_response: true}}
  end

  def handle_cast({:request_response, extra_opts}, state) do
    create_evt =
      get_in(state.config, [:client_event_names, :response_create]) || "response.create"

    event = Map.put(%{"type" => create_evt}, "response", Map.new(extra_opts))
    maybe_log_frame(state, :out, event)
    {:reply, {:text, Jason.encode!(event)}, %{state | pending_response: true}}
  end

  def handle_cast(:cancel_response, state) do
    cancel_evt =
      get_in(state.config, [:client_event_names, :response_cancel]) || "response.cancel"

    event = %{"type" => cancel_evt}
    maybe_log_frame(state, :out, event)
    {:reply, {:text, Jason.encode!(event)}, state}
  end

  @impl true
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, %{} = event} ->
        maybe_log_frame(state, :in, event)
        send_event_to_parent(event, state)
        {:ok, state_after(event, state)}

      _ ->
        Logger.debug("RealtimeWS received non-JSON text: #{String.slice(msg, 0, 200)}")
        {:ok, state}
    end
  end

  def handle_frame({:binary, payload}, state) do
    # Some servers might send binary audio frames; forward raw
    send(state.parent, {:realtime_event, %{type: "binary", payload: payload}})
    {:ok, state}
  end

  @impl true
  def handle_info({:delayed_frame, json_frame}, state) do
    # Send the delayed frame
    {:reply, {:text, json_frame}, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("RealtimeWS terminating: #{inspect(reason)}")
    send(state.parent, {:realtime_closed, reason})
    :ok
  end

  # Internal helpers

  defp state_after(event, state) do
    case event["type"] do
      t when is_binary(t) ->
        if String.ends_with?(t, ".completed") do
          %{state | pending_response: false}
        else
          state
        end

      _ ->
        state
    end
  end

  defp send_event_to_parent(event, state) do
    # Attempt to decode audio payload if present under known keys
    audio_fields =
      Map.get(state.config, :server_event_audio_fields, [
        "audio",
        "delta",
        "pcm"
      ])

    decoded_event =
      case find_audio_base64(event, audio_fields) do
        {path, b64} when is_binary(b64) ->
          with {:ok, bin} <- Base.decode64(b64) do
            put_in_path(event, path, bin)
          else
            _ -> event
          end

        _ ->
          event
      end

    send(state.parent, {:realtime_event, decoded_event})
  end

  defp find_audio_base64(%{} = event, fields) do
    Enum.find_value(fields, fn field ->
      case event do
        %{"audio" => val} when field == "audio" ->
          {[:audio], val}

        %{"response" => %{"output" => [%{"content" => [%{"audio" => %{"data" => val}} | _]} | _]}}
        when field == "data" ->
          {[
             "response",
             "output",
             0,
             "content",
             0,
             "audio",
             "data"
           ], val}

        _ ->
          case Map.get(event, field) do
            val when is_binary(val) -> {[field], val}
            _ -> nil
          end
      end
    end)
  end

  defp put_in_path(map, path, value) do
    update_in(map, Enum.map(path, &accessor/1), fn _ -> value end)
  end

  defp accessor(k) when is_integer(k), do: Access.at(k)
  defp accessor(k), do: Access.key(k)

  defp maybe_log_frame(%{config: %{log_frames: true}}, dir, payload) do
    Logger.debug("RealtimeWS #{dir}: #{inspect(payload, pretty: true)}")
  end

  defp maybe_log_frame(_state, _dir, _payload), do: :ok

  defp build_headers(config) do
    # Build a conservative, overridable set of headers
    default = [
      {"User-Agent", "LivekitexAgent/0.1 (Elixir)"}
    ]

    protocol = Map.get(config, :protocol_header)
    auth = Map.get(config, :auth_header)
    beta = Map.get(config, :beta_header)
    extras = Map.get(config, :extra_headers, [])

    default
    |> add_opt(protocol)
    |> add_opt(auth)
    |> add_opt(beta)
    |> Kernel.++(extras)
  end

  defp add_opt(list, nil), do: list
  defp add_opt(list, {k, v}), do: [{k, v} | list]

  defp normalize_config(config) do
    # Sensible defaults tuned for OpenAI Realtime API; override as needed
    config
    |> Map.put_new(:sample_rate, 16_000)
    |> Map.put_new(:protocol_header, {"Sec-WebSocket-Protocol", "realtime"})
    |> Map.put_new(:beta_header, {"OpenAI-Beta", "realtime=v1"})
    |> Map.put_new(:client_event_names, %{
      audio_append: "input_audio_buffer.append",
      audio_commit: "input_audio_buffer.commit",
      text_append: "input_text.append",
      response_create: "response.create",
      response_cancel: "response.cancel"
    })
    |> Map.put_new(:server_event_audio_fields, ["audio", "delta"])
    |> then(fn cfg ->
      case Map.fetch(cfg, :api_key) do
        {:ok, key} when is_binary(key) and byte_size(key) > 0 ->
          Map.put_new(cfg, :auth_header, {"Authorization", "Bearer " <> key})

        _ ->
          cfg
      end
    end)
  end
end
