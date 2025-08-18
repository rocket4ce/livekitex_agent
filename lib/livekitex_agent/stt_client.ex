defmodule LivekitexAgent.STTClient do
  @moduledoc """
  Behaviour for Speech-to-Text (STT) client plugins.

  This behaviour defines the minimal message protocol used by `AgentSession`:
  - `{:process_audio, pcm16_binary}`: optional streaming input frames
  - `{:process_utterance, iodata}`: final utterance audio for transcription

  Implementations should send `{:stt_result, text}` back to the parent session pid.

  Typical start usage:
      start_link(parent: session_pid, opts: ...)
  """

  @type start_opts :: [parent: pid(), opts: keyword()]

  @callback start_link(start_opts) :: GenServer.on_start()
end
