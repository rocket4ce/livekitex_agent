defmodule LivekitexAgent.SimpleEnergyVAD do
  @moduledoc """
  A minimal energy-based VAD suitable as a default plugin.

  It computes short-time RMS energy over PCM16 mono frames and emits speech start/end
  events using thresholds and hangover duration. It is not language-specific and
  works offline.

  Options:
  - :frame_ms (default 20)
  - :sample_rate (default 16000)
  - :start_threshold (default 0.02)  # normalized RMS to trigger speech start
  - :end_threshold (default 0.01)    # normalized RMS below which silence is counted
  - :hangover_ms (default 300)       # required continuous silence to mark speech_end
  """

  use GenServer
  require Logger

  @behaviour LivekitexAgent.VADClient

  defstruct [
    :parent,
    frame_bytes: nil,
    sample_rate: 16_000,
    frame_ms: 20,
    start_threshold: 0.02,
    end_threshold: 0.01,
    hangover_ms: 300,
    speech?: false,
    silence_ms: 0,
    leftover: <<>>
  ]

  @type opts :: [
          parent: pid(),
          opts: [
            frame_ms: pos_integer(),
            sample_rate: pos_integer(),
            start_threshold: float(),
            end_threshold: float(),
            hangover_ms: pos_integer()
          ]
        ]

  @impl true
  def start_link(parent: parent, opts: user_opts) do
    GenServer.start_link(__MODULE__, %{parent: parent, opts: user_opts})
  end

  @impl true
  def init(%{parent: parent, opts: opts}) do
    frame_ms = Keyword.get(opts, :frame_ms, 20)
    sr = Keyword.get(opts, :sample_rate, 16_000)

    state = %__MODULE__{
      parent: parent,
      frame_ms: frame_ms,
      sample_rate: sr,
      start_threshold: Keyword.get(opts, :start_threshold, 0.02),
      end_threshold: Keyword.get(opts, :end_threshold, 0.01),
      hangover_ms: Keyword.get(opts, :hangover_ms, 300)
    }

    {:ok, %{state | frame_bytes: div(sr * 2 * frame_ms, 1000)}}
  end

  @impl true
  def handle_info({:process_audio, pcm16}, state) when is_binary(pcm16) do
    process_stream(pcm16, state)
  end

  @impl true
  def handle_cast({:process_audio, pcm16}, state) do
    process_stream(pcm16, state)
  end

  defp process_stream(pcm16, state) do
    data = state.leftover <> pcm16
    fb = state.frame_bytes

    {state, rest} = consume_frames(data, state, fb)
    {:noreply, %{state | leftover: rest}}
  end

  defp consume_frames(data, state, fb) do
    case data do
      _ when byte_size(data) < fb ->
        {state, data}

      _ ->
        <<frame::binary-size(fb), rest::binary>> = data
        state = detect(frame, state)
        consume_frames(rest, state, fb)
    end
  end

  defp detect(frame, state) do
    rms = rms16(frame)

    cond do
      state.speech? == false and rms >= state.start_threshold ->
        send(state.parent, {:vad_event, :speech_start})
        %{state | speech?: true, silence_ms: 0}

      state.speech? and rms < state.end_threshold ->
        silence_ms = state.silence_ms + state.frame_ms

        if silence_ms >= state.hangover_ms do
          send(state.parent, {:vad_event, :speech_end})
          %{state | speech?: false, silence_ms: 0}
        else
          %{state | silence_ms: silence_ms}
        end

      state.speech? ->
        %{state | silence_ms: 0}

      true ->
        state
    end
  end

  defp rms16(pcm16) do
    # PCM16 little endian mono
    samples = for <<s::little-signed-16 <- pcm16>>, do: s / 32768.0
    n = max(length(samples), 1)
    energy = Enum.reduce(samples, 0.0, fn x, acc -> acc + x * x end) / n
    :math.sqrt(energy)
  end
end
