defmodule LivekitexAgent.Utils.Validation do
  @moduledoc """
  Parameter validation utilities for agent configuration and API requests.

  This module provides:
  - Schema-based validation for complex structures
  - Type checking and coercion functions
  - Configuration validation for providers
  - Request parameter validation
  - Custom validation rules and constraints
  - Detailed error reporting with field paths

  ## Validation Rules

  Common validation rules include:
  - `:required` - Field must be present and non-nil
  - `:string` - Must be a string with optional length constraints
  - `:integer` - Must be an integer with optional range constraints
  - `:float` - Must be a float with optional range constraints
  - `:boolean` - Must be true or false
  - `:atom` - Must be an atom, optionally from a specific set
  - `:list` - Must be a list with optional element validation
  - `:map` - Must be a map with optional key/value validation
  - `:one_of` - Must be one of the specified values
  - `:custom` - Custom validation function

  ## Examples

      # Simple validation
      validate_string("hello", min_length: 1, max_length: 10)
      validate_integer(42, min: 0, max: 100)

      # Schema validation
      schema = %{
        name: [:required, :string, min_length: 1],
        age: [:integer, min: 0, max: 150],
        email: [:string, :email]
      }
      validate_schema(data, schema)
  """

  @type validation_rule :: atom() | {atom(), keyword()} | {atom(), any()}
  @type validation_schema :: %{atom() => [validation_rule()]}
  @type validation_result :: :ok | {:error, [validation_error()]}
  @type validation_error :: %{
          field: atom() | [atom()],
          rule: atom(),
          message: String.t(),
          value: any()
        }

  ## Schema Validation

  @doc """
  Validates data against a schema definition.

  ## Examples

      schema = %{
        name: [:required, :string, min_length: 1],
        age: [:integer, min: 0, max: 150],
        active: [:boolean, default: true]
      }

      validate_schema(%{name: "John", age: 30}, schema)
      # => :ok

      validate_schema(%{name: "", age: -5}, schema)
      # => {:error, [%{field: :name, rule: :min_length, message: "...", value: ""}]}
  """
  def validate_schema(data, schema) when is_map(data) and is_map(schema) do
    errors =
      Enum.flat_map(schema, fn {field, rules} ->
        value = Map.get(data, field)
        validate_field(field, value, rules)
      end)

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  def validate_schema(data, _schema) do
    {:error, [validation_error(nil, :type, "Data must be a map", data)]}
  end

  @doc """
  Validates a single field against a list of validation rules.
  """
  def validate_field(field, value, rules) when is_list(rules) do
    Enum.reduce(rules, [], fn rule, errors ->
      case apply_validation_rule(field, value, rule) do
        :ok -> errors
        {:error, error} -> [error | errors]
      end
    end)
    |> Enum.reverse()
  end

  ## Type Validation

  @doc """
  Validates that a value is a string with optional constraints.
  """
  def validate_string(value, opts \\ [])

  def validate_string(value, opts) when is_binary(value) do
    with :ok <- check_string_length(value, opts),
         :ok <- check_string_pattern(value, opts) do
      :ok
    end
  end

  def validate_string(value, _opts) do
    {:error, "Expected string, got #{inspect(value)}"}
  end

  @doc """
  Validates that a value is an integer with optional constraints.
  """
  def validate_integer(value, opts \\ [])

  def validate_integer(value, opts) when is_integer(value) do
    with :ok <- check_integer_range(value, opts) do
      :ok
    end
  end

  def validate_integer(value, _opts) do
    {:error, "Expected integer, got #{inspect(value)}"}
  end

  @doc """
  Validates that a value is a float with optional constraints.
  """
  def validate_float(value, opts \\ [])

  def validate_float(value, opts) when is_float(value) do
    with :ok <- check_float_range(value, opts) do
      :ok
    end
  end

  def validate_float(value, _opts) do
    {:error, "Expected float, got #{inspect(value)}"}
  end

  @doc """
  Validates that a value is a boolean.
  """
  def validate_boolean(value) when is_boolean(value), do: :ok
  def validate_boolean(value), do: {:error, "Expected boolean, got #{inspect(value)}"}

  @doc """
  Validates that a value is an atom with optional allowed values.
  """
  def validate_atom(value, opts \\ [])

  def validate_atom(value, opts) when is_atom(value) do
    case Keyword.get(opts, :one_of) do
      nil ->
        :ok

      allowed when is_list(allowed) ->
        if value in allowed do
          :ok
        else
          {:error, "Atom must be one of #{inspect(allowed)}, got #{inspect(value)}"}
        end
    end
  end

  def validate_atom(value, _opts) do
    {:error, "Expected atom, got #{inspect(value)}"}
  end

  @doc """
  Validates that a value is a list with optional element validation.
  """
  def validate_list(value, opts \\ [])

  def validate_list(value, opts) when is_list(value) do
    with :ok <- check_list_length(value, opts),
         :ok <- check_list_elements(value, opts) do
      :ok
    end
  end

  def validate_list(value, _opts) do
    {:error, "Expected list, got #{inspect(value)}"}
  end

  @doc """
  Validates that a value is a map with optional key/value validation.
  """
  def validate_map(value, opts \\ [])

  def validate_map(value, opts) when is_map(value) do
    with :ok <- check_map_keys(value, opts),
         :ok <- check_map_values(value, opts) do
      :ok
    end
  end

  def validate_map(value, _opts) do
    {:error, "Expected map, got #{inspect(value)}"}
  end

  ## Domain-Specific Validation

  @doc """
  Validates an email address format.
  """
  def validate_email(value) when is_binary(value) do
    email_regex = ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/

    if Regex.match?(email_regex, value) do
      :ok
    else
      {:error, "Invalid email format"}
    end
  end

  def validate_email(value) do
    {:error, "Expected string for email, got #{inspect(value)}"}
  end

  @doc """
  Validates a URL format.
  """
  def validate_url(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        :ok

      _ ->
        {:error, "Invalid URL format"}
    end
  end

  def validate_url(value) do
    {:error, "Expected string for URL, got #{inspect(value)}"}
  end

  @doc """
  Validates a UUID format.
  """
  def validate_uuid(value) when is_binary(value) do
    uuid_regex = ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

    if Regex.match?(uuid_regex, value) do
      :ok
    else
      {:error, "Invalid UUID format"}
    end
  end

  def validate_uuid(value) do
    {:error, "Expected string for UUID, got #{inspect(value)}"}
  end

  ## Agent-Specific Validation

  @doc """
  Validates agent configuration parameters.
  """
  def validate_agent_config(config) do
    schema = %{
      agent_id: [:string, min_length: 1, max_length: 255],
      instructions: [:required, :string, min_length: 1, max_length: 10_000],
      tools: [:list, element_type: :atom],
      llm_config: [:map],
      stt_config: [:map],
      tts_config: [:map],
      vad_config: [:map],
      metadata: [:map]
    }

    validate_schema(config, schema)
  end

  @doc """
  Validates provider configuration based on provider type.
  """
  def validate_provider_config(provider_type, config) do
    case provider_type do
      :openai_llm ->
        validate_openai_llm_config(config)

      :openai_stt ->
        validate_openai_stt_config(config)

      :openai_tts ->
        validate_openai_tts_config(config)

      :webrtc_vad ->
        validate_webrtc_vad_config(config)

      _ ->
        {:error,
         [validation_error(:provider_type, :unknown, "Unknown provider type", provider_type)]}
    end
  end

  @doc """
  Validates session parameters.
  """
  def validate_session_params(params) do
    schema = %{
      session_id: [:string, min_length: 1],
      room_id: [:string, min_length: 1],
      participant_identity: [:string, min_length: 1],
      user_data: [:map]
    }

    validate_schema(params, schema)
  end

  @doc """
  Validates function tool parameters.
  """
  def validate_tool_params(tool_name, params, schema) do
    # Tool-specific validation based on the tool's parameter schema
    case validate_schema(params, schema) do
      :ok ->
        :ok

      {:error, errors} ->
        # Add tool context to errors
        tool_errors =
          Enum.map(errors, fn error ->
            %{error | field: [:tool, tool_name, error.field]}
          end)

        {:error, tool_errors}
    end
  end

  ## Private Helper Functions

  defp apply_validation_rule(field, value, rule) do
    case rule do
      :required -> validate_required(field, value)
      :string -> validate_string_rule(field, value, [])
      :integer -> validate_integer_rule(field, value, [])
      :float -> validate_float_rule(field, value, [])
      :boolean -> validate_boolean_rule(field, value)
      :atom -> validate_atom_rule(field, value, [])
      :list -> validate_list_rule(field, value, [])
      :map -> validate_map_rule(field, value, [])
      :email -> validate_email_rule(field, value)
      :url -> validate_url_rule(field, value)
      :uuid -> validate_uuid_rule(field, value)
      {rule_type, opts} -> apply_validation_rule_with_opts(field, value, rule_type, opts)
      _ -> {:error, validation_error(field, :unknown_rule, "Unknown validation rule", rule)}
    end
  end

  defp apply_validation_rule_with_opts(field, value, rule_type, opts) do
    case rule_type do
      :string -> validate_string_rule(field, value, opts)
      :integer -> validate_integer_rule(field, value, opts)
      :float -> validate_float_rule(field, value, opts)
      :atom -> validate_atom_rule(field, value, opts)
      :list -> validate_list_rule(field, value, opts)
      :map -> validate_map_rule(field, value, opts)
      :one_of -> validate_one_of_rule(field, value, opts)
      :custom -> validate_custom_rule(field, value, opts)
      :default -> apply_default_value(field, value, opts)
      _ -> {:error, validation_error(field, :unknown_rule, "Unknown validation rule", rule_type)}
    end
  end

  defp validate_required(field, nil) do
    {:error, validation_error(field, :required, "Field is required", nil)}
  end

  defp validate_required(_field, _value), do: :ok

  defp validate_string_rule(field, value, opts) do
    case validate_string(value, opts) do
      :ok -> :ok
      {:error, message} -> {:error, validation_error(field, :string, message, value)}
    end
  end

  defp validate_integer_rule(field, value, opts) do
    case validate_integer(value, opts) do
      :ok -> :ok
      {:error, message} -> {:error, validation_error(field, :integer, message, value)}
    end
  end

  defp validate_float_rule(field, value, opts) do
    case validate_float(value, opts) do
      :ok -> :ok
      {:error, message} -> {:error, validation_error(field, :float, message, value)}
    end
  end

  defp validate_boolean_rule(field, value) do
    case validate_boolean(value) do
      :ok -> :ok
      {:error, message} -> {:error, validation_error(field, :boolean, message, value)}
    end
  end

  defp validate_atom_rule(field, value, opts) do
    case validate_atom(value, opts) do
      :ok -> :ok
      {:error, message} -> {:error, validation_error(field, :atom, message, value)}
    end
  end

  defp validate_list_rule(field, value, opts) do
    case validate_list(value, opts) do
      :ok -> :ok
      {:error, message} -> {:error, validation_error(field, :list, message, value)}
    end
  end

  defp validate_map_rule(field, value, opts) do
    case validate_map(value, opts) do
      :ok -> :ok
      {:error, message} -> {:error, validation_error(field, :map, message, value)}
    end
  end

  defp validate_email_rule(field, value) do
    case validate_email(value) do
      :ok -> :ok
      {:error, message} -> {:error, validation_error(field, :email, message, value)}
    end
  end

  defp validate_url_rule(field, value) do
    case validate_url(value) do
      :ok -> :ok
      {:error, message} -> {:error, validation_error(field, :url, message, value)}
    end
  end

  defp validate_uuid_rule(field, value) do
    case validate_uuid(value) do
      :ok -> :ok
      {:error, message} -> {:error, validation_error(field, :uuid, message, value)}
    end
  end

  defp validate_one_of_rule(field, value, allowed_values) when is_list(allowed_values) do
    if value in allowed_values do
      :ok
    else
      message = "Value must be one of #{inspect(allowed_values)}"
      {:error, validation_error(field, :one_of, message, value)}
    end
  end

  defp validate_custom_rule(field, value, validation_fun) when is_function(validation_fun, 1) do
    case validation_fun.(value) do
      :ok -> :ok
      {:error, message} -> {:error, validation_error(field, :custom, message, value)}
      false -> {:error, validation_error(field, :custom, "Custom validation failed", value)}
      true -> :ok
    end
  end

  defp apply_default_value(_field, nil, default_value), do: {:ok, default_value}
  defp apply_default_value(_field, value, _default), do: {:ok, value}

  # String validation helpers
  defp check_string_length(value, opts) do
    length = String.length(value)

    with :ok <- check_min_length(length, opts),
         :ok <- check_max_length(length, opts) do
      :ok
    end
  end

  defp check_min_length(length, opts) do
    case Keyword.get(opts, :min_length) do
      nil -> :ok
      min when length >= min -> :ok
      min -> {:error, "String too short (minimum #{min} characters)"}
    end
  end

  defp check_max_length(length, opts) do
    case Keyword.get(opts, :max_length) do
      nil -> :ok
      max when length <= max -> :ok
      max -> {:error, "String too long (maximum #{max} characters)"}
    end
  end

  defp check_string_pattern(value, opts) do
    case Keyword.get(opts, :pattern) do
      nil ->
        :ok

      pattern when is_struct(pattern, Regex) ->
        if Regex.match?(pattern, value) do
          :ok
        else
          {:error, "String does not match required pattern"}
        end
    end
  end

  # Integer validation helpers
  defp check_integer_range(value, opts) do
    with :ok <- check_integer_min(value, opts),
         :ok <- check_integer_max(value, opts) do
      :ok
    end
  end

  defp check_integer_min(value, opts) do
    case Keyword.get(opts, :min) do
      nil -> :ok
      min when value >= min -> :ok
      min -> {:error, "Integer too small (minimum #{min})"}
    end
  end

  defp check_integer_max(value, opts) do
    case Keyword.get(opts, :max) do
      nil -> :ok
      max when value <= max -> :ok
      max -> {:error, "Integer too large (maximum #{max})"}
    end
  end

  # Float validation helpers
  defp check_float_range(value, opts) do
    with :ok <- check_float_min(value, opts),
         :ok <- check_float_max(value, opts) do
      :ok
    end
  end

  defp check_float_min(value, opts) do
    case Keyword.get(opts, :min) do
      nil -> :ok
      min when value >= min -> :ok
      min -> {:error, "Float too small (minimum #{min})"}
    end
  end

  defp check_float_max(value, opts) do
    case Keyword.get(opts, :max) do
      nil -> :ok
      max when value <= max -> :ok
      max -> {:error, "Float too large (maximum #{max})"}
    end
  end

  # List validation helpers
  defp check_list_length(value, opts) do
    length = length(value)

    with :ok <- check_list_min_length(length, opts),
         :ok <- check_list_max_length(length, opts) do
      :ok
    end
  end

  defp check_list_min_length(length, opts) do
    case Keyword.get(opts, :min_length) do
      nil -> :ok
      min when length >= min -> :ok
      min -> {:error, "List too short (minimum #{min} elements)"}
    end
  end

  defp check_list_max_length(length, opts) do
    case Keyword.get(opts, :max_length) do
      nil -> :ok
      max when length <= max -> :ok
      max -> {:error, "List too long (maximum #{max} elements)"}
    end
  end

  defp check_list_elements(value, opts) do
    case Keyword.get(opts, :element_type) do
      nil -> :ok
      :atom -> check_all_atoms(value)
      :string -> check_all_strings(value)
      :integer -> check_all_integers(value)
      element_type -> {:error, "Unsupported element type: #{element_type}"}
    end
  end

  defp check_all_atoms(list) do
    if Enum.all?(list, &is_atom/1) do
      :ok
    else
      {:error, "All list elements must be atoms"}
    end
  end

  defp check_all_strings(list) do
    if Enum.all?(list, &is_binary/1) do
      :ok
    else
      {:error, "All list elements must be strings"}
    end
  end

  defp check_all_integers(list) do
    if Enum.all?(list, &is_integer/1) do
      :ok
    else
      {:error, "All list elements must be integers"}
    end
  end

  # Map validation helpers
  defp check_map_keys(_value, opts) do
    # TODO: Implement key validation if needed
    case Keyword.get(opts, :required_keys) do
      nil -> :ok
      # Simplified for now
      _keys -> :ok
    end
  end

  defp check_map_values(_value, _opts) do
    # TODO: Implement value validation if needed
    :ok
  end

  # Provider-specific validation
  defp validate_openai_llm_config(config) do
    schema = %{
      api_key: [:required, :string, min_length: 1],
      model: [:required, :string, one_of: ["gpt-3.5-turbo", "gpt-4", "gpt-4-turbo"]],
      temperature: [:float, min: 0.0, max: 2.0],
      max_tokens: [:integer, min: 1, max: 4096]
    }

    validate_schema(config, schema)
  end

  defp validate_openai_stt_config(config) do
    schema = %{
      api_key: [:required, :string, min_length: 1],
      model: [:string, one_of: ["whisper-1"]],
      language: [:string, min_length: 2, max_length: 5]
    }

    validate_schema(config, schema)
  end

  defp validate_openai_tts_config(config) do
    schema = %{
      api_key: [:required, :string, min_length: 1],
      model: [:string, one_of: ["tts-1", "tts-1-hd"]],
      voice: [:string, one_of: ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]]
    }

    validate_schema(config, schema)
  end

  defp validate_webrtc_vad_config(config) do
    schema = %{
      sensitivity: [:float, min: 0.0, max: 1.0],
      frame_duration_ms: [:integer, one_of: [10, 20, 30]]
    }

    validate_schema(config, schema)
  end

  defp validation_error(field, rule, message, value) do
    %{
      field: field,
      rule: rule,
      message: message,
      value: value
    }
  end
end
