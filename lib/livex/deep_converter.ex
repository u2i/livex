defmodule Livex.DeepConverter do
  @moduledoc """
  Recursively converts structs (and any nested structs/lists) into plain maps.

  This module provides functions to convert complex nested data structures containing
  structs into plain maps, which is useful for serialization and parameter passing.
  """

  @doc """
  Converts a struct or nested data structure into plain maps.

  ## Parameters
    * `struct` - A struct, map, list, or other value to convert
    
  ## Returns
    The converted data structure with all structs converted to maps
    
  ## Examples
      iex> to_map(%User{name: "John", settings: %Settings{theme: "dark"}})
      %{name: "John", settings: %{theme: "dark"}}
  """
  def to_map(%_{} = struct), do: struct |> Map.from_struct() |> convert_map()
  def to_map(other), do: convert_map(other)

  # Handle maps (could be the result of Map.from_struct or any map)
  defp convert_map(map) when is_map(map) do
    map
    |> Enum.map(fn
      # drop the __struct__ key if it sneaks in
      {:__struct__, _} -> nil
      # recurse into values
      {key, value} -> {key, to_map(value)}
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{})
  end

  # Handle lists by mapping over each element
  defp convert_map(list) when is_list(list) do
    Enum.map(list, &to_map/1)
  end

  # Everything else (numbers, strings, tuples, etc.) is left as-is
  defp convert_map(other), do: other
end
