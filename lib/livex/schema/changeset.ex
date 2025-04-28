defmodule Livex.Schema.Changeset do
  @moduledoc """
  A simplified changeset implementation that works with plain maps,
  supports nested casting, basic validations, change tracking, embeds, and applying changes.
  """

  defstruct data: %{},
            types: %{},
            params: %{},
            changes: %{},
            errors: [],
            valid?: true,
            action: nil

  @type t :: %__MODULE__{
          data: map,
          types: %{optional(atom) => atom | map | {:embed, map} | {:embed, :many, map}},
          params: map,
          changes: map,
          errors: [{atom | [atom | integer], String.t()}],
          valid?: boolean,
          action: nil | atom
        }

  @doc """
  Cast external params for a struct: converts struct to map and delegates to map-based cast.
  """
  @spec cast(map, module, map, [atom]) :: t
  def cast(%{} = data, module, raw_params, permitted)
      when is_atom(module) and is_map(data) do
    types = module.__changeset__()
    cast({data, types}, raw_params, permitted)
  end

  @spec cast({map, %{atom => atom | map | {:embed, map} | {:embed, :many, map}}}, map, [atom]) ::
          t
  def cast({data, types}, raw_params, permitted) when is_map(data) and is_map(types) do
    params = normalize_params(raw_params)

    Enum.reduce(permitted, %__MODULE__{data: data, types: types, params: params}, fn field, acc ->
      key = Atom.to_string(field)
      type = Map.get(types, field)

      case Map.fetch(params, key) do
        {:ok, value} ->
          cond do
            is_map(type) and is_map(value) and not match?({:embed, _}, type) ->
              nested_data = Map.get(data, field, %{})
              nested_cs = cast({nested_data, type}, value, Map.keys(type))

              if nested_cs.changes != %{} do
                put_in(acc.changes[field], nested_cs)
              else
                acc
              end

            match?({:embed, _}, type) or match?({:embed, :many, _}, type) ->
              acc

            true ->
              case cast_field(value, type) do
                {:ok, casted} ->
                  if casted != Map.get(acc.data, field) do
                    put_in(acc.changes[field], casted)
                  else
                    acc
                  end

                _ ->
                  acc
              end
          end

        :error ->
          acc
      end
    end)
  end

  @spec cast(t, map, [atom]) :: t
  def cast(%__MODULE__{data: data, types: types}, raw_params, permitted) when is_map(data) do
    cast({data, types}, raw_params, permitted)
  end

  @doc """
  Casts and merges an embedded map or list of maps for the given field.
  """
  @spec cast_embed(t, atom) :: t
  def cast_embed(%__MODULE__{} = cs, field) do
    key = Atom.to_string(field)
    type = Map.get(cs.types, field)

    case Map.fetch(cs.params, key) do
      {:ok, raw} ->
        case {type, raw} do
          {{:embed, inner_types}, value} when is_map(value) ->
            base = Map.get(cs.data, field, %{})
            nested = cast({base, inner_types}, value, Map.keys(inner_types))
            update_embed_change(cs, field, nested)

          {{:embed, :many, inner_types}, values} when is_list(values) ->
            base_list = Map.get(cs.data, field, [])

            nested_list =
              values
              |> Enum.with_index()
              |> Enum.reduce([], fn {val, idx}, acc ->
                existing = Enum.at(base_list, idx, %{})
                nested_cs = cast({existing, inner_types}, val, Map.keys(inner_types))
                if nested_cs.changes != %{}, do: [nested_cs | acc], else: acc
              end)

            if nested_list != [] do
              put_in(cs.changes[field], Enum.reverse(nested_list))
            else
              cs
            end

          _ ->
            cs
        end

      :error ->
        cs
    end
  end

  defp update_embed_change(cs, field, %__MODULE__{changes: changes} = nested) do
    if changes != %{} do
      put_in(cs.changes[field], nested)
    else
      cs
    end
  end

  @doc """
  Checks if a given field (top-level) has a change.
  """
  @spec changed?(t, atom) :: boolean
  def changed?(%__MODULE__{changes: changes}, field) when is_atom(field) do
    case Map.fetch(changes, field) do
      {:ok, %__MODULE__{} = nested_cs} -> nested_cs.changes != %{}
      {:ok, _} -> true
      :error -> false
    end
  end

  @doc """
  Validates that given fields are present (non-nil and non-empty).
  """
  @spec validate_required(t, [atom]) :: t
  def validate_required(%__MODULE__{} = cs, fields) do
    Enum.reduce(fields, cs, fn field, acc ->
      {value, is_nested} = fetch_value(acc, field)

      cond do
        is_nested and value == %__MODULE__{} ->
          acc

        is_nested and value.changes == %{} and value.data == %{} ->
          add_error_for(acc, field, "can't be blank")

        not is_nested and value in [nil, ""] ->
          add_error_for(acc, field, "can't be blank")

        true ->
          acc
      end
    end)
  end

  @doc """
  Applies the accumulated changes to the original data.
  """
  @spec apply_changes(t) :: map
  def apply_changes(%__MODULE__{data: data, changes: changes}) do
    Enum.reduce(changes, data, fn
      {field, %__MODULE__{} = nested_cs}, acc -> Map.put(acc, field, apply_changes(nested_cs))
      {field, value}, acc -> Map.put(acc, field, value)
    end)
  end

  @doc """
  Applies the action if valid, else returns error tuple.
  """
  @spec apply_action(t, atom) :: {:ok, map} | {:error, t}
  def apply_action(%__MODULE__{valid?: true} = cs, action) when is_atom(action) do
    {:ok, apply_changes(%{cs | action: action})}
  end

  def apply_action(%__MODULE__{} = cs, action) when is_atom(action),
    do: {:error, %{cs | action: action}}

  # -- Internal Helpers -------------------------------------------------------

  defp normalize_params(params) when is_map(params) do
    Enum.into(params, %{}, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} when is_binary(k) -> {k, v}
    end)
  end

  defp cast_field(value, nil), do: {:ok, value}

  defp cast_field(value, :integer) when is_binary(value) do
    case Integer.parse(value) do
      {i, ""} -> {:ok, i}
      _ -> {:ok, nil}
    end
  end

  defp cast_field(value, :integer) when is_integer(value), do: {:ok, value}

  defp cast_field(value, :boolean) when is_binary(value) do
    case String.downcase(value) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> {:ok, nil}
    end
  end

  defp cast_field(value, :boolean) when is_boolean(value), do: {:ok, value}

  defp cast_field(value, :string) when is_binary(value), do: {:ok, value}
  defp cast_field(value, :string), do: {:ok, to_string(value)}

  defp cast_field(value, type) when is_atom(type) do
    case Ecto.Type.cast(type, value) do
      {:ok, v} -> {:ok, v}
      :error -> {:ok, nil}
    end
  end

  defp cast_field(value, type) when is_tuple(type) do
    case Ecto.Type.cast(type, value) do
      {:ok, v} -> {:ok, v}
      :error -> {:ok, nil}
    end
  end

  defp cast_field(_value, _type), do: {:ok, nil}

  defp fetch_value(%__MODULE__{changes: ch, data: d}, f) do
    case Map.fetch(ch, f) do
      {:ok, %__MODULE__{} = nested} -> {nested, true}
      {:ok, v} -> {v, false}
      :error -> {Map.get(d, f), false}
    end
  end

  defp add_error_for(cs, field, msg) do
    %{cs | valid?: false, errors: [{field, msg} | cs.errors]}
  end
end
