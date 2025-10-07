defmodule LivekitexAgent.ExampleTools do
  @moduledoc """
  Comprehensive example tools demonstrating FunctionTool capabilities.

  This module showcases:
  - Basic tool definitions with @tool macro
  - Parameter validation and type conversion
  - RunContext usage for session management
  - Error handling and logging
  - Advanced tool patterns
  """

  use LivekitexAgent.FunctionTool
  require Logger

  @doc """
  Auto-generated entry point function for Phoenix integration.

  This function is automatically used when no explicit entry_point is configured,
  enabling zero-configuration Phoenix integration. It provides basic job handling
  with logging for development purposes.

  ## Parameters
  - `job_context` (LivekitexAgent.JobContext.t()): Job context containing room info and metadata

  ## Returns
  - `:ok`: Indicates successful job handling

  ## Example
      # Automatically used in WorkerOptions.from_config/0
      opts = WorkerOptions.from_config()
      # => %WorkerOptions{entry_point: &LivekitexAgent.ExampleTools.auto_entry_point/1, ...}

      # Can be used explicitly
      LivekitexAgent.ExampleTools.auto_entry_point(job_context)
  """
  @spec auto_entry_point(LivekitexAgent.JobContext.t()) :: :ok
  def auto_entry_point(%LivekitexAgent.JobContext{} = job_context) do
    Logger.info("Auto-generated entry point handling job: #{inspect(job_context.job_request)}")

    # Extract basic job information
    room_name = job_context.room_name || "unknown_room"
    participant_count = length(job_context.participants || [])

    Logger.info("""
    Phoenix Integration Job Handler:
    - Room: #{room_name}
    - Participants: #{participant_count}
    - Agent ready for custom implementation

    To customize this behavior, provide your own entry_point:
    config :livekitex_agent, default_worker_options: [
      entry_point: &MyAgent.handle_job/1
    ]
    """)

    # Simulate basic job processing
    :timer.sleep(1000)

    Logger.info("Auto-generated entry point completed successfully")
    :ok
  end

  @spec get_weather(String.t()) :: String.t()
  def get_weather(location) do
    # Mock weather API call
    Logger.info("Getting weather for: #{location}")

    # Simulate API delay
    :timer.sleep(100)

    weather_conditions = ["Sunny", "Cloudy", "Rainy", "Snowy", "Partly Cloudy"]
    condition = Enum.random(weather_conditions)
    temperature = Enum.random(15..30)

    "Weather in #{location}: #{condition}, #{temperature}°C"
  end

  @spec add_numbers(number(), number()) :: number()
  def add_numbers(a, b) when is_number(a) and is_number(b) do
    a + b
  end

  @spec search_web(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def search_web(query, context) do
    LivekitexAgent.RunContext.log_info(context, "Performing web search for: #{query}")

    # Mock search results
    results = [
      "Result 1: Information about #{query}",
      "Result 2: More details on #{query}",
      "Result 3: Latest news about #{query}"
    ]

    # Simulate search delay
    :timer.sleep(200)

    Enum.join(results, "\n")
  end

  @spec get_current_time(String.t()) :: String.t()
  def get_current_time(timezone \\ "UTC") do
    try do
      now = DateTime.utc_now()

      case timezone do
        "UTC" ->
          DateTime.to_string(now)

        "EST" ->
          # Mock EST conversion (UTC-5)
          est_time = DateTime.add(now, -5 * 3600, :second)
          "#{DateTime.to_string(est_time)} EST"

        "PST" ->
          # Mock PST conversion (UTC-8)
          pst_time = DateTime.add(now, -8 * 3600, :second)
          "#{DateTime.to_string(pst_time)} PST"

        _ ->
          "#{DateTime.to_string(now)} (#{timezone} conversion not supported)"
      end
    rescue
      error ->
        "Error getting time: #{inspect(error)}"
    end
  end

  @spec random_number(integer(), integer()) :: integer()
  def random_number(min, max) when is_integer(min) and is_integer(max) and min <= max do
    Enum.random(min..max)
  end

  def random_number(_min, _max) do
    raise ArgumentError, "min and max must be integers and min <= max"
  end

  @spec to_uppercase(String.t()) :: String.t()
  def to_uppercase(text) when is_binary(text) do
    String.upcase(text)
  end

  @spec count_words(String.t()) :: integer()
  def count_words(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.split(~r/\s+/)
    |> length()
  end

  @spec store_user_data(String.t(), String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def store_user_data(key, value, context) do
    LivekitexAgent.RunContext.put_user_data(context, key, value)
    LivekitexAgent.RunContext.log_info(context, "Stored user data: #{key} = #{value}")

    "Stored #{key} = #{value} in user data"
  end

  @spec get_user_data(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def get_user_data(key, context) do
    case LivekitexAgent.RunContext.get_user_data(context, key) do
      nil ->
        "No data found for key: #{key}"

      value ->
        "#{key}: #{value}"
    end
  end

  @spec factorial(non_neg_integer()) :: non_neg_integer()
  def factorial(0), do: 1

  def factorial(n) when is_integer(n) and n > 0 do
    n * factorial(n - 1)
  end

  def factorial(_n) do
    raise ArgumentError, "factorial requires a non-negative integer"
  end

  @doc """
  Check if a number is prime.
  """
  @spec prime?(integer()) :: boolean()
  def prime?(n) when n < 2, do: false
  def prime?(2), do: true
  def prime?(n) when rem(n, 2) == 0, do: false

  def prime?(n) do
    limit = :math.sqrt(n) |> trunc()
    not Enum.any?(3..limit//2, fn i -> rem(n, i) == 0 end)
  end

  @doc """
  Pause execution for a specified number of seconds.
  """
  @spec sleep(integer(), LivekitexAgent.RunContext.t()) :: String.t()
  def sleep(seconds, context) when is_integer(seconds) and seconds > 0 and seconds <= 10 do
    LivekitexAgent.RunContext.log_info(context, "Sleeping for #{seconds} seconds")

    :timer.sleep(seconds * 1000)

    "Slept for #{seconds} seconds"
  end

  def sleep(seconds, _context) when seconds > 10 do
    "Sleep duration limited to 10 seconds maximum"
  end

  def sleep(_seconds, _context) do
    "Sleep duration must be a positive integer"
  end

  # Advanced tool examples showcasing enhanced features

  @spec convert_temperature(number(), String.t()) :: String.t()
  def convert_temperature(temp, unit) when unit in ["C", "F", "celsius", "fahrenheit"] do
    case String.downcase(unit) do
      unit when unit in ["c", "celsius"] ->
        fahrenheit = temp * 9 / 5 + 32
        "#{temp}°C = #{Float.round(fahrenheit, 2)}°F"

      unit when unit in ["f", "fahrenheit"] ->
        celsius = (temp - 32) * 5 / 9
        "#{temp}°F = #{Float.round(celsius, 2)}°C"
    end
  end

  def convert_temperature(_temp, unit) do
    "Unsupported unit: #{unit}. Use 'C', 'F', 'celsius', or 'fahrenheit'"
  end

  @spec compound_interest(number(), number(), number(), integer()) :: String.t()
  def compound_interest(principal, rate, time, compounds_per_year \\ 1)
      when is_number(principal) and is_number(rate) and is_number(time) and
             is_integer(compounds_per_year) do
    # A = P(1 + r/n)^(nt)
    amount =
      principal * :math.pow(1 + rate / (100 * compounds_per_year), compounds_per_year * time)

    interest = amount - principal

    "Principal: $#{Float.round(principal, 2)}, " <>
      "Rate: #{rate}%, Time: #{time} years, " <>
      "Final Amount: $#{Float.round(amount, 2)}, " <>
      "Interest Earned: $#{Float.round(interest, 2)}"
  end

  @spec generate_password(integer(), String.t()) :: String.t()
  def generate_password(length \\ 12, options \\ "all")
      when is_integer(length) and length > 0 and length <= 100 do
    chars =
      case String.downcase(options) do
        "numbers" -> "0123456789"
        "letters" -> "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        "symbols" -> "!@#$%^&*()_+-=[]{}|;:,.<>?"
        "simple" -> "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        _ -> "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-="
      end

    password =
      1..length
      |> Enum.map(fn _ -> Enum.random(String.graphemes(chars)) end)
      |> Enum.join("")

    "Generated #{length}-character password: #{password}"
  end

  @spec validate_email(String.t()) :: String.t()
  def validate_email(email) when is_binary(email) do
    email_regex = ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/

    if Regex.match?(email_regex, email) do
      formatted = String.downcase(String.trim(email))
      "✓ Valid email: #{formatted}"
    else
      "✗ Invalid email format: #{email}"
    end
  end

  @spec calculate_bmi(number(), number(), String.t()) :: String.t()
  def calculate_bmi(weight, height, unit \\ "metric")
      when is_number(weight) and is_number(height) do
    # Convert to metric if needed
    {weight_kg, height_m} =
      case String.downcase(unit) do
        # lbs to kg, inches to meters
        "imperial" -> {weight * 0.453592, height * 0.0254}
        # assume kg and cm
        _ -> {weight, height / 100}
      end

    bmi = weight_kg / (height_m * height_m)

    category =
      cond do
        bmi < 18.5 -> "Underweight"
        bmi < 25 -> "Normal weight"
        bmi < 30 -> "Overweight"
        true -> "Obese"
      end

    "BMI: #{Float.round(bmi, 1)} (#{category})"
  end

  @spec interrupt_and_respond(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def interrupt_and_respond(message, context) do
    case LivekitexAgent.RunContext.interrupt_speech(context) do
      :ok ->
        LivekitexAgent.RunContext.log_info(context, "Speech interrupted for immediate response")
        "🔊 [INTERRUPTING] #{message}"

      {:error, reason} ->
        LivekitexAgent.RunContext.log_warning(
          context,
          "Failed to interrupt speech: #{inspect(reason)}"
        )

        "📢 #{message}"
    end
  end

  @spec adjust_speech_volume(number(), LivekitexAgent.RunContext.t()) :: String.t()
  def adjust_speech_volume(volume, context) when volume >= 0 and volume <= 1 do
    case LivekitexAgent.RunContext.control_speech(context, {:set_volume, volume}) do
      :ok ->
        "🔊 Speech volume adjusted to #{trunc(volume * 100)}%"

      {:error, reason} ->
        "Failed to adjust volume: #{inspect(reason)}"
    end
  end

  def adjust_speech_volume(volume, _context) do
    "Volume must be between 0.0 and 1.0, got: #{volume}"
  end

  @doc """
  Returns all available tools as a map for registration.
  """
  def get_tools do
    %{
      "get_weather" => %{
        name: "get_weather",
        description: "Get weather information for a specific location",
        module: __MODULE__,
        function: :get_weather,
        arity: 1,
        parameters: [%{name: "location", type: "string", required: true, position: 0}]
      },
      "add_numbers" => %{
        name: "add_numbers",
        description: "Calculate the sum of two numbers",
        module: __MODULE__,
        function: :add_numbers,
        arity: 2,
        parameters: [
          %{name: "a", type: "number", required: true, position: 0},
          %{name: "b", type: "number", required: true, position: 1}
        ]
      },
      "search_web" => %{
        name: "search_web",
        description: "Search for information on the web",
        module: __MODULE__,
        function: :search_web,
        arity: 2,
        parameters: [
          %{name: "query", type: "string", required: true, position: 0}
        ]
      },
      "get_current_time" => %{
        name: "get_current_time",
        description: "Get the current time in a specific timezone",
        module: __MODULE__,
        function: :get_current_time,
        arity: 1,
        parameters: [%{name: "timezone", type: "string", required: false, position: 0}]
      },
      "random_number" => %{
        name: "random_number",
        description: "Generate a random number between min and max values",
        module: __MODULE__,
        function: :random_number,
        arity: 2,
        parameters: [
          %{name: "min", type: "integer", required: true, position: 0},
          %{name: "max", type: "integer", required: true, position: 1}
        ]
      },
      "to_uppercase" => %{
        name: "to_uppercase",
        description: "Convert text to uppercase",
        module: __MODULE__,
        function: :to_uppercase,
        arity: 1,
        parameters: [%{name: "text", type: "string", required: true, position: 0}]
      },
      "count_words" => %{
        name: "count_words",
        description: "Count words in a text",
        module: __MODULE__,
        function: :count_words,
        arity: 1,
        parameters: [%{name: "text", type: "string", required: true, position: 0}]
      },
      "factorial" => %{
        name: "factorial",
        description: "Calculate factorial of a number",
        module: __MODULE__,
        function: :factorial,
        arity: 1,
        parameters: [%{name: "n", type: "integer", required: true, position: 0}]
      },
      "prime?" => %{
        name: "prime?",
        description: "Check if a number is prime",
        module: __MODULE__,
        function: :prime?,
        arity: 1,
        parameters: [%{name: "n", type: "integer", required: true, position: 0}]
      },
      # Backward-compatible alias for older callers
      "is_prime" => %{
        name: "prime?",
        description: "Check if a number is prime (alias)",
        module: __MODULE__,
        function: :prime?,
        arity: 1,
        parameters: [%{name: "n", type: "integer", required: true, position: 0}]
      }
    }
  end
end
