#!/usr/bin/env elixir
Mix.install([
  {:jason, "~> 1.4"}
])

Code.append_path("lib")
Code.compile_file("lib/livekitex_agent.ex")
Code.compile_file("lib/livekitex_agent/agent.ex")
Code.compile_file("lib/livekitex_agent/agent_session.ex")
Code.compile_file("lib/livekitex_agent/realtime_ws_client.ex")
Code.compile_file("lib/livekitex_agent/audio_sink.ex")

# Simple CLI-driven push-to-talk demo using the RealtimeWSClient.
# Commands:
#   start <wav_file>  -> streams WAV (mono, 16kHz PCM16) to the realtime server
#   text <prompt>     -> send a text prompt
#   commit            -> end the audio turn and request a response
#   cancel            -> cancel current response
#   quit              -> exit

# Load helper wav reader
Code.compile_file("examples/support/wav_reader.ex")

api_key = System.get_env("OPENAI_API_KEY") || System.get_env("OAI_API_KEY")
url = System.get_env("OAI_REALTIME_URL") ||
        "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17"

agent = LivekitexAgent.Agent.new(
  instructions: "You are a helpful assistant.",
  tools: [],
  agent_id: "ptt_agent"
)

rt_cfg = %{
  url: url,
  api_key: api_key,
  log_frames: true
}

{:ok, session} = LivekitexAgent.AgentSession.start_link(agent: agent, realtime_config: rt_cfg)

IO.puts("Push-to-talk demo connected. Type commands. Example: start ./sample.wav, then commit")

stream_wav = fn path ->
  case Examples.WavReader.read_pcm16(path) do
    {:ok, %{pcm: pcm, sample_rate: 16_000}} ->
      # chunk into ~320ms (5120 bytes PCM16 mono at 16kHz)
      chunk_size = 5120
      for <<chunk::binary-size(chunk_size) <- pcm>> do
        LivekitexAgent.AgentSession.stream_audio(session, chunk)
        Process.sleep(320)
      end
      rem = rem(byte_size(pcm), chunk_size)
      if rem > 0 do
        last = binary_part(pcm, byte_size(pcm) - rem, rem)
        LivekitexAgent.AgentSession.stream_audio(session, last)
      end
      :ok

    {:ok, %{sample_rate: sr}} ->
      IO.puts("Unsupported sample rate #{sr}; please use 16000 Hz mono PCM16")
    {:error, reason} -> IO.puts("WAV read error: #{inspect(reason)}")
  end
end

loop = fn loop ->
  IO.write("> ")
  case IO.gets("") do
    :eof -> :ok
    {:error, _} -> :ok
    line ->
      case String.trim(line) do
        "" -> loop.(loop)
        "quit" -> :ok
        "commit" ->
          LivekitexAgent.AgentSession.commit_audio(session)
          loop.(loop)
        "cancel" ->
          LivekitexAgent.AgentSession.cancel_response(session)
          loop.(loop)
        cmd when String.starts_with?(cmd, "start ") ->
          <<_::binary-6, path::binary>> = cmd
          path = String.trim(path)
          Task.start(fn -> stream_wav.(path) end)
          loop.(loop)
        cmd when String.starts_with?(cmd, "text ") ->
          prompt = String.trim_binary_part(cmd, 5)
          LivekitexAgent.AgentSession.send_text(session, prompt)
          loop.(loop)
        other ->
          IO.puts("Unknown command: #{other}")
          loop.(loop)
      end
  end
end

loop.(loop)
