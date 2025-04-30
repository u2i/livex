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

        def dispatch_component_event(event, params, socket) do
          Livex.Schema.LivexViewTransformer.dispatch_component_event(
            __MODULE__,
            event,
            params,
            socket
          )
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
    |> IO.inspect(label: :before)
    |> Component.assign(:uri, uri)
    |> module.apply_params_to_assigns(params)
    |> mount_components(module)
    |> IO.inspect(label: :after_mount)
    |> then(&{:cont, &1})
  end

  @doc """
  Updates socket assigns based on provided parameters.

  Applies the changeset to the parameters, ensuring type safety, and updates
  the socket assigns with the resulting values. Also ensures all required fields
  have default values when not provided. Additionally, calls mount on each component
  module to allow components to initialize their state.
  """
  @spec apply_params_to_assigns(module(), socket(), map()) :: socket()
  def apply_params_to_assigns(module, socket, params) do
    # Apply changeset to convert and validate parameters
    IO.inspect(socket.assigns, label: :socket_assigns)
    changeset = module.changeset(socket.assigns, params |> IO.inspect(label: :params))

    validated_assigns = Changeset.apply_changes(changeset)

    # Ensure all attributes and components have at least their default values
    #  socket = merge_assigns_with_defaults(socket, validated_assigns, module)

    # Call mount on each component module
    socket = Map.put(socket, :assigns, validated_assigns)

    socket
  end

  @doc """
  Mounts all components in the socket assigns.

  Uses a simple path-based traversal to mount components at any nesting level.
  """
  @spec mount_components(socket(), module()) :: socket()
  def mount_components(socket, module) do
    component_entities = Extension.get_entities(module, [:components])

    # Process each top-level component
    Enum.reduce(component_entities, socket, fn component, acc_socket ->
      nested_name = component.name
      nested_module = component.related
      nested_path = [nested_name]

      mount_component_at_path(acc_socket, nested_path, nested_module)
    end)
  end

  @doc """
  Mounts a component at a specific path in the socket assigns.

  Traverses the path to find the component, mounts it if needed,
  then recursively processes any child components only if the component exists.
  """
  @spec mount_component_at_path(socket(), [atom()], module()) :: socket()
  def mount_component_at_path(socket, path, component_module) do
    # Return unchanged socket if socket is nil
    if is_nil(socket) do
      socket
    else
      # Get component struct at the given path
      component_struct = assigns_from_path(socket, path)

      # Only proceed if we have a component at this path
      if is_nil(component_struct |> IO.inspect(label: :compstruct)) do
        IO.inspect(path, label: :stopping)
        socket
      else
        IO.inspect(path, label: :going_in)
        IO.inspect(component_module, label: :module)
        # Mount the component if it has a mount function
        socket =
          if function_exported?(component_module, :mount, 2) do
            component_context = {socket, path}

            case component_module.mount(component_struct, component_context) do
              {:ok, {updated_component_struct, _path}} ->
                # Update the socket assigns at the specific path
                updated_component_struct

              _ ->
                socket
            end
          else
            socket
          end

        # Process child components only if we have a component at this path
        nested_components = Extension.get_entities(component_module, [:components])

        Enum.reduce(nested_components, socket, fn nested_component, acc_socket ->
          nested_name = nested_component.name
          nested_module = nested_component.related
          nested_path = path ++ [nested_name]

          # Recursively mount the nested component
          mount_component_at_path(acc_socket, nested_path, nested_module)
        end)
      end
    end
  end

  def assigns_from_path(socket, [one]) do
    socket.assigns[one]
  end

  def assigns_from_path(socket, path) do
    [head | tail] = path

    tail
    |> Enum.map(&Access.key(&1, %{}))
    |> then(fn path ->
      get_in(socket.assigns[head] || %{}, path)
    end)
  end

  @doc """
  Updates a value at a specific path in the socket assigns.

  Helper function to update deeply nested values in the socket.
  """
  @spec put_in_socket(socket(), [atom()], any()) :: socket()
  def put_in_socket(socket, path, value) do
    updated_assigns = put_in(socket.assigns, path, value)
    %{socket | assigns: updated_assigns}
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

  # Gets component field structure with nested components
  @spec get_component_field_names(module()) :: %{
          attributes: [atom()],
          components: %{atom() => module()}
        }
  defp get_component_field_names(component_module) do
    attributes =
      Extension.get_entities(component_module, [:attributes])
      |> Enum.map(& &1.name)

    components =
      Extension.get_entities(component_module, [:components])
      |> Enum.map(fn component -> {component.name, component.related} end)
      |> Enum.into(%{})

    %{attributes: attributes, components: components}
  end

  # Extracts non-nil values from a struct based on specified fields
  # and recursively processes nested components
  @spec extract_non_nil_fields(map(), %{attributes: [atom()], components: %{atom() => module()}}) ::
          map()
  defp extract_non_nil_fields(struct, %{attributes: attribute_names, components: components}) do
    # Extract attribute values
    attribute_values =
      struct
      |> Map.take(attribute_names)
      |> Enum.reject(fn {_, value} -> is_nil(value) end)
      |> Enum.into(%{})

    # Process nested components
    component_values =
      Enum.reduce(components, %{}, fn {component_name, component_module}, acc ->
        case Map.get(struct, component_name) do
          nil ->
            acc

          component_struct ->
            nested_field_structure = get_component_field_names(component_module)
            nested_values = extract_non_nil_fields(component_struct, nested_field_structure)

            if map_size(nested_values) > 0 do
              Map.put(acc, component_name, nested_values)
            else
              acc
            end
        end
      end)

    # Merge attribute and component values
    Map.merge(attribute_values, component_values)
  end

  def dispatch_component_event(module, event, %{"__target_path" => path_str} = params, socket) do
    path = String.split(path_str, "/") |> Enum.map(&String.to_existing_atom(&1))

    dispatch_component_event_impl(module, event, path, params, {socket, path})
  end

  defp dispatch_component_event_impl(module, event, [head], params, {socket, path}) do
    component =
      Extension.get_entities(module, [:components])
      |> Enum.find(&(&1.name == head))

    {return, {socket, _}} = component.related.handle_event(event, params, {socket, path})
    {return, socket}
  end

  defp dispatch_component_event_impl(module, event, [_head | tail], params, {socket, path}) do
    component =
      Extension.get_entities(module, [:components])
      |> Enum.find(&(&1.name == Enum.at(path, 0)))

    dispatch_component_event_impl(component.related, event, tail, params, {socket, path})
  end
end
