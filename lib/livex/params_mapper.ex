defmodule Livex.ParamsMapper do
  @moduledoc false

  alias Spark.Dsl.Extension

  @doc """
  Map and cast parameters for a given component, optionally scoped by an `id`.
  """
  @spec map_params(module(), map() | nil, any() | nil) :: map()
  def map_params(component, params, id \\ nil) do
    params
    |> fetch_scope(id)
    |> process(component)
  end

  defp fetch_scope(params, nil), do: params || %{}
  defp fetch_scope(params, id), do: get_in(params || %{}, [to_string(id)]) || %{}

  # No params? nothing to do
  defp process(%{} = params, component) do
    component
    |> Extension.get_entities([:attributes])
    |> Enum.reduce(%{}, &reduce_attr(&1, params, &2))
  end

  defp process(_, _), do: %{}

  # Handle each attribute: fetch, cast, then include if non-empty
  defp reduce_attr(%{name: name, type: type}, params, acc) do
    with {:ok, value} <- fetch_and_cast(name, type, params),
         false <- empty?(value) do
      Map.put(acc, name, value)
    else
      _ -> acc
    end
  end

  # Fetch raw data then cast based on type
  defp fetch_and_cast(name, type, params) do
    raw = get_in(params, [to_string(name)])

    value =
      cond do
        is_atom(type) and Code.ensure_loaded?(type) and
            function_exported?(type, :__info__, 1) ->
          type
          |> Extension.get_entities([:attributes])
          |> case do
            [] -> cast(raw, type)
            props -> build_props(raw || %{}, props)
          end

        true ->
          cast(raw, type)
      end

    wrap(value)
  end

  # Build nested props map for module-types
  defp build_props(data, props) do
    Enum.reduce(props, %{}, fn %{name: pname, type: ptype}, acc ->
      case Map.fetch(data, to_string(pname)) do
        {:ok, val} ->
          case cast(val, ptype) do
            nil -> acc
            casted -> Map.put(acc, pname, casted)
          end

        :error ->
          acc
      end
    end)
  end

  # Wrap into ok/error for pattern matching
  defp wrap(nil), do: {:error, :no_value}
  defp wrap(%{} = m), do: {:ok, m}
  defp wrap(val), do: {:ok, val}

  defp empty?(%{} = m), do: map_size(m) == 0
  defp empty?(nil), do: true
  defp empty?(_), do: false

  # Fallback casting rules
  @doc """
  Cast a value to the specified type.
  """
  @spec cast(any(), atom()) :: any()
  def cast(nil, _), do: nil
  def cast(val, :string), do: val
  def cast(val, :atom), do: safe_atom(val)
  def cast(val, :integer), do: safe_parse(&String.to_integer/1, val)
  def cast(val, :float), do: safe_parse(&String.to_float/1, val)
  def cast(val, :boolean), do: parse_bool(val)
  def cast(val, :date), do: parse_iso(&Date.from_iso8601/1, val)
  def cast(val, :time), do: parse_iso(&Time.from_iso8601/1, val)
  def cast(val, :naive_datetime), do: parse_iso(&NaiveDateTime.from_iso8601/1, val)
  def cast(val, :utc_datetime), do: parse_iso(&DateTime.from_iso8601/1, val)
  def cast(val, :decimal), do: safe_parse(&Decimal.new/1, val)
  def cast(val, :uuid), do: if(val =~ ~r/^[0-9A-Fa-f\-]{36}$/, do: val, else: nil)
  def cast(val, :map), do: decode_json(val, &is_map/1)
  def cast(val, :list), do: decode_json(val, &is_list/1)
  def cast(val, :json), do: decode_json(val, fn _ -> true end)
  def cast(val, :binary), do: if(is_binary(val), do: val)
  def cast(_, _), do: nil

  # Helpers for safe parsing
  @doc """
  Safely convert a string to an existing atom.
  """
  def safe_atom(val) do
    try do
      String.to_existing_atom(val)
    rescue
      _ -> nil
    end
  end

  @doc """
  Safely parse a value using the provided function.
  """
  def safe_parse(fun, val) do
    try do
      fun.(val)
    rescue
      _ -> nil
    end
  end

  @doc """
  Parse a string into a boolean value.
  """
  def parse_bool(val) do
    case String.downcase(val) do
      "true" -> true
      "false" -> false
      "1" -> true
      "0" -> false
      _ -> nil
    end
  end

  @doc """
  Parse an ISO formatted string using the provided function.
  """
  def parse_iso(fun, val) do
    case(fun.(val)) do
      {:ok, parsed} -> parsed
      _ -> nil
    end
  end

  @doc """
  Decode a JSON string and verify its type.
  """
  def decode_json(val, type_check) do
    with {:ok, decoded} <- Jason.decode(val),
         true <- type_check.(decoded) do
      decoded
    else
      _ -> nil
    end
  end

  @doc false
  def update_uri_from_assigns_with_attributes(mod, assigns, id \\ nil) do
    attribute_names =
      mod
      |> Extension.get_entities([:attributes])
      |> Enum.map(& &1.name)

    params =
      assigns
      |> Map.take(attribute_names)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.into(%{})

    if id, do: %{to_string(id) => params}, else: params
  end
end
