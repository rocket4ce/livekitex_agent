#!/usr/bin/env elixir

# Weather Agent Example with Custom Tools
#
# This example demonstrates how to create a specialized weather agent
# that uses custom function tools to provide weather information,
# forecasts, and weather-related advice.
#
# Usage:
#   export OPENAI_API_KEY="your-key-here"
#   export LIVEKIT_URL="wss://your-livekit-server.com"
#   export LIVEKIT_API_KEY="your-api-key"
#   export LIVEKIT_API_SECRET="your-api-secret"
#   elixir examples/weather_agent.exs

Mix.install([
  {:livekitex_agent, path: ".."},
  {:httpoison, "~> 2.0"},
  {:jason, "~> 1.4"}
])

defmodule WeatherTools do
  @moduledoc """
  Custom weather-related tools for the agent.

  This module demonstrates:
  - Custom tool definitions with @tool macro
  - Parameter validation and type conversion
  - External API integration patterns
  - Error handling in tool functions
  - Context usage for logging and session data
  """

  use LivekitexAgent.FunctionTool
  require Logger

  @tool "Get current weather conditions for any city worldwide"
  @spec get_weather(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def get_weather(location, context) do
    LivekitexAgent.RunContext.log_info(context, "Fetching weather for: #{location}")

    # In a real implementation, you would call a weather API
    # For this example, we'll simulate the API call
    simulate_weather_api_call(location, context)
  end

  @tool "Get detailed 5-day weather forecast for a location"
  @spec get_forecast(String.t(), integer(), LivekitexAgent.RunContext.t()) :: String.t()
  def get_forecast(location, days \\ 5, context) when days > 0 and days <= 7 do
    LivekitexAgent.RunContext.log_info(context, "Fetching #{days}-day forecast for: #{location}")

    simulate_forecast_api_call(location, days, context)
  end

  @tool "Get weather alerts and warnings for a specific location"
  @spec get_weather_alerts(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def get_weather_alerts(location, context) do
    LivekitexAgent.RunContext.log_info(context, "Checking weather alerts for: #{location}")

    # Simulate checking for weather alerts
    simulate_weather_alerts(location, context)
  end

  @tool "Recommend clothing based on weather conditions"
  @spec recommend_clothing(String.t(), String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def recommend_clothing(location, activity \\ "general", context) do
    LivekitexAgent.RunContext.log_info(context, "Getting clothing recommendations for #{activity} in #{location}")

    # Get weather first, then make recommendations
    weather_conditions = get_simulated_conditions(location)
    generate_clothing_recommendations(weather_conditions, activity, context)
  end

  @tool "Check air quality index for a location"
  @spec get_air_quality(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def get_air_quality(location, context) do
    LivekitexAgent.RunContext.log_info(context, "Checking air quality for: #{location}")

    simulate_air_quality_check(location, context)
  end

  @tool "Get sunrise and sunset times for a location"
  @spec get_sun_times(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def get_sun_times(location, context) do
    LivekitexAgent.RunContext.log_info(context, "Getting sun times for: #{location}")

    simulate_sun_times(location, context)
  end

  @tool "Save a location as user's favorite for quick weather access"
  @spec save_favorite_location(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def save_favorite_location(location, context) do
    # Store in user data
    favorites = LivekitexAgent.RunContext.get_user_data(context, "favorite_locations") || []

    unless location in favorites do
      updated_favorites = [location | favorites]
      LivekitexAgent.RunContext.put_user_data(context, "favorite_locations", updated_favorites)

      LivekitexAgent.RunContext.log_info(context, "Added #{location} to favorites")
      "✅ Added #{location} to your favorite locations. You now have #{length(updated_favorites)} favorites."
    else
      "📍 #{location} is already in your favorite locations."
    end
  end

  @tool "Get weather for all saved favorite locations"
  @spec get_favorites_weather(LivekitexAgent.RunContext.t()) :: String.t()
  def get_favorites_weather(context) do
    case LivekitexAgent.RunContext.get_user_data(context, "favorite_locations") do
      nil ->
        "📍 You haven't saved any favorite locations yet. Use 'save favorite location' to add some!"

      [] ->
        "📍 No favorite locations found."

      favorites ->
        LivekitexAgent.RunContext.log_info(context, "Getting weather for #{length(favorites)} favorite locations")

        weather_reports =
          Enum.map(favorites, fn location ->
            "📍 #{location}: #{get_simulated_conditions(location).summary}"
          end)

        "🌤️ Weather for your favorite locations:\n" <> Enum.join(weather_reports, "\n")
    end
  end

  # Private helper functions

  defp simulate_weather_api_call(location, context) do
    # Simulate API delay
    :timer.sleep(Enum.random(100..500))

    conditions = get_simulated_conditions(location)

    case conditions.status do
      :success ->
        "🌤️ Current weather in #{location}:\n" <>
        "Temperature: #{conditions.temperature}°C (feels like #{conditions.feels_like}°C)\n" <>
        "Conditions: #{conditions.summary}\n" <>
        "Humidity: #{conditions.humidity}%\n" <>
        "Wind: #{conditions.wind_speed} km/h #{conditions.wind_direction}\n" <>
        "Visibility: #{conditions.visibility} km"

      :error ->
        LivekitexAgent.RunContext.log_error(context, "Weather API error for #{location}")
        "❌ Sorry, I couldn't get weather information for #{location}. Please check the location name."
    end
  end

  defp simulate_forecast_api_call(location, days, _context) do
    :timer.sleep(Enum.random(200..800))

    forecast_days =
      1..days
      |> Enum.map(fn day ->
        date = Date.add(Date.utc_today(), day)
        temp_high = Enum.random(15..30)
        temp_low = temp_high - Enum.random(5..12)
        condition = Enum.random(["Sunny", "Partly Cloudy", "Cloudy", "Light Rain", "Showers"])

        "#{Date.to_string(date)}: #{condition}, High #{temp_high}°C, Low #{temp_low}°C"
      end)

    "📅 #{days}-day forecast for #{location}:\n" <> Enum.join(forecast_days, "\n")
  end

  defp simulate_weather_alerts(location, _context) do
    # Randomly simulate alerts for demonstration
    if Enum.random(1..10) > 7 do
      alert_type = Enum.random(["Thunderstorm Watch", "Heavy Rain Advisory", "High Wind Warning", "Heat Advisory"])
      "⚠️ Weather Alert for #{location}: #{alert_type} in effect until tomorrow evening. Please take appropriate precautions."
    else
      "✅ No weather alerts or warnings for #{location} at this time."
    end
  end

  defp generate_clothing_recommendations(conditions, activity, _context) do
    base_recommendations = case conditions.temperature do
      temp when temp < 0 -> ["heavy winter coat", "warm hat", "insulated gloves", "winter boots"]
      temp when temp < 10 -> ["warm jacket", "long pants", "closed shoes", "light scarf"]
      temp when temp < 20 -> ["light jacket or sweater", "long or short pants", "comfortable shoes"]
      temp when temp < 30 -> ["light clothing", "shorts or light pants", "breathable shirt", "sun hat"]
      _ -> ["minimal clothing", "shorts", "light t-shirt", "sun protection", "plenty of water"]
    end

    activity_additions = case String.downcase(activity) do
      "running" -> ["moisture-wicking fabrics", "running shoes", "reflective gear if dark"]
      "hiking" -> ["sturdy hiking boots", "layers for temperature changes", "rain protection"]
      "work" -> ["professional attire", "weather-appropriate outerwear"]
      "outdoor" -> ["sun protection", "weather-resistant materials"]
      _ -> []
    end

    weather_additions =
      cond do
        String.contains?(String.downcase(conditions.summary), "rain") ->
          ["waterproof jacket", "umbrella", "waterproof shoes"]
        String.contains?(String.downcase(conditions.summary), "snow") ->
          ["waterproof boots", "warm layers", "gloves"]
        String.contains?(String.downcase(conditions.summary), "wind") ->
          ["windbreaker", "secure hat"]
        String.contains?(String.downcase(conditions.summary), "sun") ->
          ["sunglasses", "sunscreen", "hat"]
        true ->
          []
      end

    all_items = base_recommendations ++ activity_additions ++ weather_additions
    unique_items = Enum.uniq(all_items)

    "👕 Clothing recommendations for #{activity} in #{conditions.temperature}°C weather:\n" <>
    "• " <> Enum.join(unique_items, "\n• ") <>
    "\n\nCurrent conditions: #{conditions.summary}"
  end

  defp simulate_air_quality_check(location, _context) do
    aqi = Enum.random(15..150)

    {level, description, advice} = case aqi do
      aqi when aqi <= 50 -> {"Good", "Air quality is satisfactory", "Great day for outdoor activities!"}
      aqi when aqi <= 100 -> {"Moderate", "Air quality is acceptable", "Outdoor activities are okay for most people"}
      aqi when aqi <= 150 -> {"Unhealthy for Sensitive Groups", "May cause issues for sensitive people", "Limit outdoor activities if you're sensitive"}
      _ -> {"Unhealthy", "May cause health issues", "Avoid prolonged outdoor activities"}
    end

    "🌬️ Air Quality in #{location}:\n" <>
    "AQI: #{aqi} (#{level})\n" <>
    "Description: #{description}\n" <>
    "Recommendation: #{advice}"
  end

  defp simulate_sun_times(location, _context) do
    # Simulate sunrise/sunset times (would normally use location-based calculation)
    sunrise_hour = Enum.random(5..7)
    sunrise_minute = Enum.random(0..59)
    sunset_hour = Enum.random(17..20)
    sunset_minute = Enum.random(0..59)

    "☀️ Sun times for #{location} today:\n" <>
    "Sunrise: #{sunrise_hour}:#{String.pad_leading(to_string(sunrise_minute), 2, "0")} AM\n" <>
    "Sunset: #{sunset_hour}:#{String.pad_leading(to_string(sunset_minute), 2, "0")} PM\n" <>
    "Daylight duration: #{sunset_hour - sunrise_hour} hours #{sunset_minute - sunrise_minute + 60} minutes"
  end

  defp get_simulated_conditions(location) do
    # Simulate realistic weather conditions
    success_rate = if String.length(location) > 2, do: 0.9, else: 0.3

    if :rand.uniform() < success_rate do
      %{
        status: :success,
        temperature: Enum.random(-10..35),
        feels_like: Enum.random(-15..40),
        humidity: Enum.random(30..90),
        wind_speed: Enum.random(0..25),
        wind_direction: Enum.random(["N", "NE", "E", "SE", "S", "SW", "W", "NW"]),
        visibility: Enum.random(5..50),
        summary: Enum.random([
          "Clear skies", "Partly cloudy", "Mostly cloudy", "Overcast",
          "Light rain", "Heavy rain", "Thunderstorms", "Snow showers",
          "Sunny", "Foggy", "Windy", "Calm"
        ])
      }
    else
      %{status: :error}
    end
  end
end

defmodule WeatherAgent do
  @moduledoc """
  A specialized weather agent that provides comprehensive weather information
  and personalized recommendations using custom tools.
  """

  alias LivekitexAgent.{Agent, AgentSession, WorkerOptions, WorkerManager}
  require Logger

  def run do
    Logger.info("🌤️ Starting Weather Agent...")

    # Register our custom weather tools
    case LivekitexAgent.FunctionTool.register_module(WeatherTools) do
      {:ok, count} ->
        Logger.info("Registered #{count} weather tools")

      {:error, reason} ->
        Logger.error("Failed to register weather tools: #{inspect(reason)}")
        System.halt(1)
    end

    # Configure worker options
    worker_options = %WorkerOptions{
      agent_name: "weather-agent",
      worker_type: :voice_agent,
      server_url: System.get_env("LIVEKIT_URL"),
      api_key: System.get_env("LIVEKIT_API_KEY"),
      api_secret: System.get_env("LIVEKIT_API_SECRET"),
      timeout: 60_000,
      max_concurrent_jobs: 5,
      entry_point: &handle_weather_job/1
    }

    Logger.info("Weather Agent ready - connecting to LiveKit...")
    WorkerManager.start_worker(worker_options)
  end

  def handle_weather_job(job_context) do
    Logger.info("New weather session: #{inspect(job_context)}")

    # Create specialized weather agent session
    session_config = %{
      instructions: """
      You are WeatherBot, a friendly and knowledgeable weather assistant.

      Your expertise includes:
      - Current weather conditions worldwide
      - Multi-day weather forecasts
      - Weather alerts and warnings
      - Clothing and activity recommendations
      - Air quality information
      - Sunrise/sunset times
      - Managing user's favorite locations

      Always be helpful, accurate, and provide actionable advice. When users ask about weather,
      use your tools to get real-time information. You can save locations as favorites and
      provide quick updates for multiple cities.

      Be conversational and personable - weather affects everyone's daily life!
      """,
      metadata: %{
        agent_type: "weather_specialist",
        version: "1.0",
        capabilities: [
          "current_weather", "forecasts", "alerts", "recommendations",
          "air_quality", "sun_times", "favorites_management"
        ]
      },
      tools: [
        # Our custom weather tools will be automatically discovered
        :get_weather, :get_forecast, :get_weather_alerts,
        :recommend_clothing, :get_air_quality, :get_sun_times,
        :save_favorite_location, :get_favorites_weather
      ]
    }

    # Start the weather agent session
    {:ok, session} = AgentSession.create(session_config)

    # Register event callbacks for weather-specific interactions
    register_weather_callbacks(session)

    AgentSession.start(session)
  end

  defp register_weather_callbacks(session) do
    # Welcome message with weather capabilities
    AgentSession.on_event(session, :session_started, fn session ->
      Logger.info("Weather session started: #{session.session_id}")

      greeting = """
      Hello! I'm WeatherBot, your personal weather assistant! 🌤️

      I can help you with:
      • Current weather conditions anywhere in the world
      • 5-day weather forecasts
      • Weather alerts and warnings
      • Clothing recommendations based on weather
      • Air quality information
      • Sunrise and sunset times
      • Save your favorite locations for quick updates

      Just ask me something like "What's the weather in Tokyo?" or "Should I wear a jacket in London?"
      """

      AgentSession.generate_response(session, greeting)
    end)

    # Log tool usage for weather tools specifically
    AgentSession.on_event(session, :tool_called, fn session, %{tool_name: tool_name, arguments: args} ->
      if String.contains?(to_string(tool_name), ["weather", "forecast", "air_quality", "sun", "favorite"]) do
        Logger.info("Weather tool called: #{tool_name} with #{inspect(args)}")
      end
    end)

    # Enhanced responses for weather-related queries
    AgentSession.on_event(session, :text_received, fn session, %{text: text} ->
      if weather_related?(text) do
        Logger.info("Weather-related query detected: #{text}")
      end
    end)
  end

  defp weather_related?(text) do
    weather_keywords = [
      "weather", "temperature", "rain", "snow", "sunny", "cloudy",
      "forecast", "climate", "hot", "cold", "humid", "wind",
      "storm", "alert", "air quality", "sunrise", "sunset"
    ]

    text_lower = String.downcase(text)
    Enum.any?(weather_keywords, &String.contains?(text_lower, &1))
  end
end

# Configuration validation
defmodule ConfigValidator do
  def validate! do
    required_vars = [
      "OPENAI_API_KEY",
      "LIVEKIT_URL",
      "LIVEKIT_API_KEY",
      "LIVEKIT_API_SECRET"
    ]

    missing_vars =
      required_vars
      |> Enum.filter(&is_nil(System.get_env(&1)))

    unless Enum.empty?(missing_vars) do
      IO.puts("❌ Missing required environment variables:")
      Enum.each(missing_vars, &IO.puts("  #{&1}"))
      IO.puts("\nSet these environment variables and try again.")
      System.halt(1)
    end

    IO.puts("✅ All required environment variables are set")
    IO.puts("🌤️ Weather Agent configuration validated")
  end
end

# Validate configuration and run
ConfigValidator.validate!()
WeatherAgent.run()
