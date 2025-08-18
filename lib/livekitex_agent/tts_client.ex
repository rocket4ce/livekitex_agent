defmodule LivekitexAgent.TTSClient do
  @moduledoc """
  Behaviour for Text-to-Speech (TTS) client plugins.

  Message protocol expected by `AgentSession`:
  - `{:synthesize, text}` -> client should synthesize audio and may emit `{:tts_audio, pcm16}`
    chunks and/or `{:tts_complete, pcm16_concat}` to the session pid.
  - `:stop` -> optional, should stop any ongoing synthesis.

  Typical start usage:
      start_link(parent: session_pid, opts: ...)
  """

  @type start_opts :: [parent: pid(), opts: keyword()]

  @callback start_link(start_opts) :: GenServer.on_start()
end
