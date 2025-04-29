defmodule Livex.Schema.LivexViewTransformer do
  @moduledoc """
  Transforms LivexView modules by injecting hook functions for URL state management.

  This transformer is responsible for generating the necessary hook functions that
  enable LivexView modules to maintain state in the URL and synchronize between
  URL parameters and LiveView assigns.
  """
  use Spark.Dsl.Transformer

  alias Livex.Routes
  alias Livex.Schema.Changeset
  alias Phoenix.Component
  alias Phoenix.LiveView
  alias Spark.Dsl.Extension
  alias Spark.Dsl.Transformer

  @type socket :: LiveView.Socket.t()

  @impl Spark.Dsl.Transformer
  def transform(dsl_state) do
    # Generate hook functions for the LivexView module
    hooks =
      quote do
        @doc """
        Updates the URL based on the current socket assigns.

        This hook is attached to the :after_render lifecycle and ensures
        the URL reflects the current state of the LiveView.
        """
        def update_uri_from_assigns(socket) do
          Livex.Schema.LivexViewTransformer.update_uri_from_assigns(__MODULE__, socket)
        end

        @doc """
        Updates socket assigns from URL parameters when the URL changes.

        This hook is attached to the :handle_params lifecycle and ensures
        the LiveView assigns are synchronized with URL parameters.
        """
        def update_assigns_from_uri(params, uri, socket) do
          Livex.Schema.LivexViewTransformer.update_assigns_from_uri(
            __MODULE__,
            params,
            uri,
            socket
          )
        end

        @doc """
        Updates socket assigns based on provided parameters.

        Applies the changeset to the parameters and updates the socket assigns,
        ensuring all required fields have default values when not provided.
        """
        def apply_params_to_assigns(socket, params) do
          Livex.Schema.LivexViewTransformer.apply_params_to_assigns(__MODULE__, socket, params)
        end
      end

    {:ok, Transformer.eval(dsl_state, [], hooks)}
  end

  @doc """
  Updates the URL based on the current socket assigns.

  Extracts relevant fields from the socket assigns and generates a new URL path
  that reflects the current state of the LiveView.
  """
  @spec update_uri_from_assigns(module(), socket()) :: socket()
  def update_uri_from_assigns(module, socket) when is_atom(module) do
    case Extension.get_entities(module, [:attributes]) ++
           Extension.get_entities(module, [:components]) do
      [] ->
        update_uri_from_assigns_without_attributes(module, socket)

      attribute_entities ->
        update_uri_from_assigns_with_attributes(module, socket, attribute_entities)
    end
  end

  @doc """
  Updates the URL when no attributes are defined in the module.

  This is a no-op since the module isn't using the DSL.
  """
  @spec update_uri_from_assigns_without_attributes(module(), socket()) :: socket()
  def update_uri_from_assigns_without_attributes(_module, socket), do: socket

  @doc """
  Updates the URL when attributes are defined in the module.

  Extracts relevant fields from the socket assigns and generates a new URL path
  that reflects the current state of the LiveView.
  """
  @spec update_uri_from_assigns_with_attributes(module(), socket(), list()) :: socket()
  def update_uri_from_assigns_with_attributes(module, socket, attribute_entities) do
    # Extract primary fields and embed fields from the schema
    primary_field_names = Enum.map(attribute_entities, & &1.name)
    component_entities = Extension.get_entities(module, [:components])

    # Build URL parameters from assigns
    url_parameters =
      socket.assigns
      |> Map.take(primary_field_names)
      |> Map.merge(extract_component_parameters(socket.assigns, component_entities, module))

    # Push URL update event to the client
    LiveView.push_event(
      socket,
      "update_url",
      %{uri: Routes.new_path(socket, url_parameters)}
    )
  end

  @doc """
  Updates socket assigns from URL parameters when the URL changes.

  Updates the socket assigns based on the URL parameters and returns a continuation
  tuple to allow the LiveView to continue processing the event.
  """
  @spec update_assigns_from_uri(module(), map(), String.t(), socket()) :: {:cont, socket()}
  def update_assigns_from_uri(module, params, uri, socket)
      when is_atom(module) and is_map(params) do
    socket
    |> Component.assign(:uri, uri)
    |> module.apply_params_to_assigns(params)
    |> then(&{:cont, &1})
  end

  @doc """
  Updates socket assigns based on provided parameters.

  Applies the changeset to the parameters, ensuring type safety, and updates
  the socket assigns with the resulting values. Also ensures all required fields
  have default values when not provided.
  """
  @spec apply_params_to_assigns(module(), socket(), map()) :: socket()
  def apply_params_to_assigns(module, socket, params) do
    # Apply changeset to convert and validate parameters
    changeset = module.changeset(socket.assigns, params)

    validated_assigns = Changeset.apply_changes(changeset)

    # Ensure all attributes and components have at least their default values
    socket
    |> merge_assigns_with_defaults(validated_assigns, module)
  end

  # Private helper functions

  # Updates socket assigns with processed values and defaults
  @spec merge_assigns_with_defaults(socket(), map(), module()) :: socket()
  defp merge_assigns_with_defaults(socket, assigns, module) do
    attributes = Extension.get_entities(module, [:attributes])
    components = Extension.get_entities(module, [:components])

    updated_assigns =
      assigns
      |> apply_default_attributes(module, [:attributes])
      |> apply_default_attributes(module, [:components])

    %{socket | assigns: updated_assigns}
  end

  # Ensures all fields of a given type have at least their default values
  @spec apply_default_attributes(map(), module(), [:attributes | :components]) :: map()
  defp apply_default_attributes(assigns, module, entity_type) do
    entities = Extension.get_entities(module, entity_type)

    Enum.reduce(entities, assigns, fn entity, acc ->
      result = Map.put_new(acc, entity.name, entity.default)
      result
    end)
  end

  # Extracts component data for URL generation.
  @spec extract_component_parameters(map(), list(), module()) :: map()
  defp extract_component_parameters(assigns, component_entities, _view_module) do
    Enum.reduce(component_entities, %{}, fn component, acc ->
      with %{} = component_struct <- Map.get(assigns, component.name),
           component_module <- component.related,
           component_field_names <- get_component_field_names(component_module),
           component_params <- extract_non_nil_fields(component_struct, component_field_names),
           true <- map_size(component_params) > 0 do
        Map.put(acc, component.name, component_params)
      else
        _ -> acc
      end
    end)
  end

  # Gets all field names from a component's schema
  @spec get_component_field_names(module()) :: [atom()]
  defp get_component_field_names(component_module) do
    (Extension.get_entities(component_module, [:attributes]) ++
       Extension.get_entities(component_module, [:components]))
    |> Enum.map(& &1.name)
  end

  # Extracts non-nil values from a struct based on specified fields
  @spec extract_non_nil_fields(map(), [atom()]) :: map()
  defp extract_non_nil_fields(struct, field_names) do
    struct
    |> Map.take(field_names)
    |> Enum.reject(fn {_, value} -> is_nil(value) end)
    |> Enum.into(%{})
  end
end
