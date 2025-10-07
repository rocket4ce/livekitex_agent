defmodule LivekitexAgent.VADClient do
  @moduledoc """
  Behaviour for Voice Activity Detection (VAD) client plugins.

  Message protocol expected by `AgentSession`:
  - `{:process_audio, pcm16_binary}`: stream frames into VAD

  The client should send back one or more of the following events to parent session pid:
  - `{:vad_event, :speech_start}`
  - `{:vad_event, :speech_end}`
  - `{:vad_event, {:speech_prob, float_0_1}}`

  Typical start usage:
      start_link(parent: session_pid, opts: ...)
  """

  @type start_opts :: [parent: pid(), opts: keyword()]

  @callback start_link(start_opts) :: GenServer.on_start()
end
