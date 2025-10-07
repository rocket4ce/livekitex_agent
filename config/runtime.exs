# Runtime configuration for production
import Config

# This file is executed during runtime in production
# It allows for configuration to be set using environment variables
# without requiring a restart

if config_env() == :prod do
  # LiveKit configuration - read from environment at runtime
  livekit_url = System.get_env("LIVEKIT_URL")
  livekit_api_key = System.get_env("LIVEKIT_API_KEY")
  livekit_api_secret = System.get_env("LIVEKIT_API_SECRET")

  # OpenAI configuration - read from environment at runtime
  openai_api_key = System.get_env("OPENAI_API_KEY")

  if livekit_url && livekit_api_key && livekit_api_secret do
    config :livekitex_agent,
      livekit: [
        server_url: livekit_url,
        api_key: livekit_api_key,
        api_secret: livekit_api_secret
      ]
  end

  if openai_api_key do
    config :livekitex_agent,
      openai: [
        api_key: openai_api_key,
        base_url: System.get_env("OPENAI_BASE_URL") || "https://api.openai.com/v1",
        llm_model: System.get_env("OPENAI_LLM_MODEL") || "gpt-4-turbo-preview",
        stt_model: System.get_env("OPENAI_STT_MODEL") || "whisper-1",
        tts_model: System.get_env("OPENAI_TTS_MODEL") || "tts-1",
        tts_voice: System.get_env("OPENAI_TTS_VOICE") || "alloy"
      ]
  end

  # Worker configuration from environment
  if max_jobs = System.get_env("MAX_CONCURRENT_JOBS") do
    config :livekitex_agent,
      default_worker_options: [
        max_concurrent_jobs: String.to_integer(max_jobs),
        drain_timeout: String.to_integer(System.get_env("DRAIN_TIMEOUT") || "60000"),
        health_check_port: String.to_integer(System.get_env("HEALTH_CHECK_PORT") || "8080")
      ]
  end
end
