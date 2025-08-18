defmodule LivekitexAgent.ExampleTools do
  @moduledoc """
  Example tools demonstrating how to create function tools for the agent.
  """

  require Logger

  @doc """
  Get weather information for a specific location.
  """
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

  @doc """
  Calculate the sum of two numbers.
  """
  @spec add_numbers(number(), number()) :: number()
  def add_numbers(a, b) when is_number(a) and is_number(b) do
    a + b
  end

  @doc """
  Search for information on the web.
  """
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

  @doc """
  Get the current time in a specific timezone.
  """
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

  @doc """
  Generate a random number between min and max values.
  """
  @spec random_number(integer(), integer()) :: integer()
  def random_number(min, max) when is_integer(min) and is_integer(max) and min <= max do
    Enum.random(min..max)
  end

  def random_number(_min, _max) do
    raise ArgumentError, "min and max must be integers and min <= max"
  end

  @doc """
  Convert text to uppercase.
  """
  @spec to_uppercase(String.t()) :: String.t()
  def to_uppercase(text) when is_binary(text) do
    String.upcase(text)
  end

  @doc """
  Count words in a text.
  """
  @spec count_words(String.t()) :: integer()
  def count_words(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.split(~r/\s+/)
    |> length()
  end

  @doc """
  Store a key-value pair in user data.
  """
  @spec store_user_data(String.t(), String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def store_user_data(key, value, context) do
    LivekitexAgent.RunContext.put_user_data(context, key, value)
    LivekitexAgent.RunContext.log_info(context, "Stored user data: #{key} = #{value}")

    "Stored #{key} = #{value} in user data"
  end

  @doc """
  Retrieve a value from user data.
  """
  @spec get_user_data(String.t(), LivekitexAgent.RunContext.t()) :: String.t()
  def get_user_data(key, context) do
    case LivekitexAgent.RunContext.get_user_data(context, key) do
      nil ->
        "No data found for key: #{key}"

      value ->
        "#{key}: #{value}"
    end
  end

  @doc """
  Calculate factorial of a number.
  """
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
