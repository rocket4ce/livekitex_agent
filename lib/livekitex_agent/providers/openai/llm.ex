defmodule LivekitexAgent.Providers.OpenAI.LLM do
  @moduledoc """
  OpenAI Language Model provider for LivekitexAgent.

  Handles communication with OpenAI's GPT models for text generation,
  conversation handling, and function calling capabilities.

  Supports:
  - GPT-4 and GPT-3.5-turbo models
  - Function calling with tool definitions
  - Streaming and non-streaming responses
  - Temperature and other generation parameters
  - Token usage tracking
  """

  use GenServer
  require Logger

  @default_model "gpt-4"
  @default_temperature 0.7
  @default_max_tokens 1000
  @api_base_url "https://api.openai.com/v1"

  defstruct [
    :api_key,
    :model,
    :temperature,
    :max_tokens,
    :parent,
    :http_client,
    :tools,
    :system_instructions,
    :conversation_history,
    :request_timeout
  ]

  @type t :: %__MODULE__{
          api_key: String.t(),
          model: String.t(),
          temperature: float(),
          max_tokens: integer(),
          parent: pid(),
          http_client: atom(),
          tools: list(),
          system_instructions: String.t() | nil,
          conversation_history: list(),
          request_timeout: integer()
        }

  # Client API

  @doc """
  Starts the OpenAI LLM provider.

  ## Options
  - `:api_key` - OpenAI API key (required)
  - `:model` - Model to use (default: "gpt-4")
  - `:temperature` - Generation temperature (default: 0.7)
  - `:max_tokens` - Maximum tokens to generate (default: 1000)
  - `:parent` - Parent process for event callbacks
  - `:tools` - Available function tools
  - `:system_instructions` - System prompt
  - `:request_timeout` - HTTP request timeout in ms (default: 30000)

  ## Example
      {:ok, llm} = LivekitexAgent.Providers.OpenAI.LLM.start_link(
        api_key: "sk-...",
        model: "gpt-4",
        parent: self()
      )
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Processes a message with conversation context.
  """
  def process_message(llm_pid, message, context \\ [], instructions \\ nil) do
    GenServer.cast(llm_pid, {:process_message, message, context, instructions})
  end

  @doc """
  Continues processing with updated context (for tool results).
  """
  def continue_with_context(llm_pid, context) do
    GenServer.cast(llm_pid, {:continue_with_context, context})
  end

  @doc """
  Updates the system instructions.
  """
  def update_instructions(llm_pid, instructions) do
    GenServer.call(llm_pid, {:update_instructions, instructions})
  end

  @doc """
  Updates the available tools.
  """
  def update_tools(llm_pid, tools) do
    GenServer.call(llm_pid, {:update_tools, tools})
  end

  @doc """
  Gets the current configuration.
  """
  def get_config(llm_pid) do
    GenServer.call(llm_pid, :get_config)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    api_key = Keyword.fetch!(opts, :api_key)

    state = %__MODULE__{
      api_key: api_key,
      model: Keyword.get(opts, :model, @default_model),
      temperature: Keyword.get(opts, :temperature, @default_temperature),
      max_tokens: Keyword.get(opts, :max_tokens, @default_max_tokens),
      parent: Keyword.get(opts, :parent),
      http_client: HTTPoison,
      tools: Keyword.get(opts, :tools, []),
      system_instructions: Keyword.get(opts, :system_instructions),
      conversation_history: [],
      request_timeout: Keyword.get(opts, :request_timeout, 30_000)
    }

    Logger.info("OpenAI LLM provider started with model: #{state.model}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:process_message, message, context, instructions}, state) do
    Logger.debug("Processing message with OpenAI LLM")

    # Update instructions if provided
    state = if instructions, do: %{state | system_instructions: instructions}, else: state

    # Build the messages array for OpenAI API
    messages = build_messages_array(message, context, state.system_instructions)

    # Make API request
    Task.start(fn ->
      case make_completion_request(state, messages) do
        {:ok, response} ->
          if state.parent, do: send(state.parent, {:llm_response, response})

        {:error, error} ->
          Logger.error("OpenAI LLM error: #{inspect(error)}")
          if state.parent, do: send(state.parent, {:llm_error, error})
      end
    end)

    {:noreply, %{state | conversation_history: messages}}
  end

  @impl true
  def handle_cast({:continue_with_context, context}, state) do
    Logger.debug("Continuing with updated context")

    # Extract the latest messages for continuation
    messages = context

    Task.start(fn ->
      case make_completion_request(state, messages) do
        {:ok, response} ->
          if state.parent, do: send(state.parent, {:llm_response, response})

        {:error, error} ->
          Logger.error("OpenAI LLM continuation error: #{inspect(error)}")
          if state.parent, do: send(state.parent, {:llm_error, error})
      end
    end)

    {:noreply, %{state | conversation_history: messages}}
  end

  @impl true
  def handle_call({:update_instructions, instructions}, _from, state) do
    {:reply, :ok, %{state | system_instructions: instructions}}
  end

  @impl true
  def handle_call({:update_tools, tools}, _from, state) do
    {:reply, :ok, %{state | tools: tools}}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    config = %{
      model: state.model,
      temperature: state.temperature,
      max_tokens: state.max_tokens,
      tools_count: length(state.tools)
    }

    {:reply, config, state}
  end

  # Private Functions

  defp build_messages_array(message, context, system_instructions) do
    base_messages =
      if system_instructions do
        [%{role: "system", content: system_instructions}]
      else
        []
      end

    # Add conversation context
    messages_with_context = base_messages ++ context

    # Add current message if it's not already in context
    if Enum.any?(context, fn msg -> msg[:content] == message end) do
      messages_with_context
    else
      messages_with_context ++ [%{role: "user", content: message}]
    end
  end

  defp make_completion_request(state, messages) do
    url = "#{@api_base_url}/chat/completions"

    headers = [
      {"Authorization", "Bearer #{state.api_key}"},
      {"Content-Type", "application/json"},
      {"User-Agent", "LivekitexAgent/1.0"}
    ]

    # Build request body
    body = %{
      model: state.model,
      messages: messages,
      temperature: state.temperature,
      max_tokens: state.max_tokens
    }

    # Add tools if available
    body =
      if length(state.tools) > 0 do
        Map.put(body, :tools, format_tools_for_openai(state.tools))
      else
        body
      end

    case Jason.encode(body) do
      {:ok, json_body} ->
        case state.http_client.post(url, json_body, headers, timeout: state.request_timeout) do
          {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
            parse_completion_response(response_body)

          {:ok, %HTTPoison.Response{status_code: status_code, body: error_body}} ->
            Logger.error("OpenAI API error #{status_code}: #{error_body}")
            {:error, {:api_error, status_code, error_body}}

          {:error, error} ->
            Logger.error("HTTP request error: #{inspect(error)}")
            {:error, {:http_error, error}}
        end

      {:error, encode_error} ->
        Logger.error("JSON encoding error: #{inspect(encode_error)}")
        {:error, {:encoding_error, encode_error}}
    end
  end

  defp parse_completion_response(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"choices" => [%{"message" => message} | _]}} ->
        # Extract the response content
        content = Map.get(message, "content", "")

        # Check for tool calls
        tool_calls = Map.get(message, "tool_calls", [])

        if length(tool_calls) > 0 do
          {:ok, %{tool_calls: tool_calls}}
        else
          {:ok, content}
        end

      {:ok, %{"error" => error}} ->
        {:error, {:api_error, error}}

      {:error, decode_error} ->
        Logger.error("JSON decode error: #{inspect(decode_error)}")
        {:error, {:decode_error, decode_error}}

      _ ->
        {:error, :invalid_response}
    end
  end

  defp format_tools_for_openai(tools) when is_list(tools) do
    Enum.map(tools, fn tool ->
      %{
        type: "function",
        function: %{
          name: to_string(tool),
          description: get_tool_description(tool),
          parameters: get_tool_parameters(tool)
        }
      }
    end)
  end

  defp get_tool_description(tool_name) do
    # Try to get description from tool registry or FunctionTool module
    try do
      case LivekitexAgent.ToolRegistry.get_tool(tool_name) do
        {:ok, tool_info} ->
          Map.get(tool_info, :description, "Tool: #{tool_name}")

        {:error, _} ->
          "Tool: #{tool_name}"
      end
    rescue
      # Fallback if ToolRegistry is not available
      _ -> "Tool: #{tool_name}"
    end
  end

  defp get_tool_parameters(tool_name) do
    # Try to get parameters from tool registry or FunctionTool module
    try do
      case LivekitexAgent.ToolRegistry.get_tool(tool_name) do
        {:ok, tool_info} ->
          Map.get(tool_info, :schema, %{type: "object", properties: %{}})

        {:error, _} ->
          %{type: "object", properties: %{}}
      end
    rescue
      # Fallback if ToolRegistry is not available
      _ -> %{type: "object", properties: %{}}
    end
  end
end
