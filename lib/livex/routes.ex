defmodule Livex.Routes do
  @moduledoc """
  Utilities for working with LiveView routes in a type-safe manner.

  This module provides functions to generate paths with parameters and query strings
  based on the current LiveView's route pattern.
  """

  alias Livex.DeepConverter

  # Recursively removes nil values from maps and nested maps
  defp remove_nil_values(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {k, remove_nil_values(v)} end)
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  # Handle lists by mapping over each element
  defp remove_nil_values(list) when is_list(list) do
    list
    |> Enum.map(&remove_nil_values/1)
    |> Enum.reject(&is_nil/1)
  end

  # Everything else (numbers, strings, tuples, etc.) is left as-is
  defp remove_nil_values(other), do: other

  @doc """
  Generates a new path based on the current LiveView's route pattern and provided parameters.

  This function takes a socket and a map of parameters, and generates a path by:
  1. Extracting the current route pattern from the socket
  2. Substituting path variables with their values from the parameters map
  3. Adding any remaining parameters as query string parameters

  ## Parameters
    * `socket` - The LiveView socket containing route information
    * `params_map` - A map of parameters to include in the path
    
  ## Returns
    A string representing the generated path
    
  ## Examples
      iex> new_path(socket, %{id: "123", modal: %{sow_id: "456", live_action: :edit}})
      "/billing_projects/123?modal[sow_id]=456&modal[live_action]=edit"
  """
  def new_path(socket, params_map) when is_map(params_map) do
    # Convert structs to maps recursively
    params_map = DeepConverter.to_map(params_map)

    # Parse the URI from the socket
    %URI{path: current_path, host: host} = URI.parse(socket.assigns.uri)

    # Get the route pattern from the router
    %{route: pattern} =
      Phoenix.Router.route_info(socket.router, "GET", current_path, host)

    # Normalize incoming params to string keys
    params = for {k, v} <- params_map, into: %{}, do: {to_string(k), v}

    # Find all :vars in the pattern
    path_vars =
      pattern
      |> String.split("/", trim: true)
      |> Enum.filter(&String.starts_with?(&1, ":"))
      |> Enum.map(&String.trim_leading(&1, ":"))

    # Substitute each :var with its value
    substituted_path =
      Enum.reduce(path_vars, pattern, fn key, acc ->
        case Map.fetch(params, key) do
          {:ok, v} -> String.replace(acc, ":#{key}", URI.encode(to_string(v)))
          :error -> acc
        end
      end)

    # Drop the consumed keys and build the query string
    other_params =
      params
      |> Map.drop(path_vars)
      |> remove_nil_values()

    if map_size(other_params) > 0 do
      substituted_path <>
        "?" <>
        Phoenix.VerifiedRoutes.__encode_query__(other_params)
    else
      substituted_path
    end
  end
end
