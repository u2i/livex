defmodule Livex.Schema.LivexComponentTransformer do
  @moduledoc """
  Transforms LivexComponent modules by injecting functions for component state management.

  This transformer is responsible for generating the necessary functions that
  enable LivexComponent modules to manage their state and communicate with parent LiveViews.
  """
  use Spark.Dsl.Transformer

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias Phoenix.LiveView.Socket
  alias Spark.Dsl.Extension

  @type socket :: LiveView.Socket.t()

  @impl Spark.Dsl.Transformer
  def transform(dsl_state) do
    # Generate functions for the LivexComponent module
    functions =
      quote do
        @doc """
        Initializes the private assigns map in the socket.
        """
        def initialize_private(socket) do
          Livex.Schema.LivexComponentTransformer.initialize_private(socket)
        end

        @doc """
        Pushes the private assigns to the component and resets private assigns.

        This function is typically called after state changes to update the URL.
        """
        def push_state(socket) do
          Livex.Schema.LivexComponentTransformer.push_state(socket)
        end

        @doc """
        Sends a message to delete the component.
        """
        def push_delete(socket) do
          Livex.Schema.LivexComponentTransformer.push_delete(socket)
        end

        @doc """
        Assigns a value to a key in the socket assigns and tracks it in private assigns if it's a schema field.
        """
        def assign(socket, key, value) do
          Livex.Schema.LivexComponentTransformer.assign(__MODULE__, socket, key, value)
        end

        @doc """
        Assigns a map of values to the socket assigns.
        """
        def assign(socket, map) do
          Livex.Schema.LivexComponentTransformer.assign_map(socket, map)
        end
      end

    {:ok, Spark.Dsl.Transformer.eval(dsl_state, [], functions)}
  end

  @doc """
  Initializes the private assigns map in the socket.
  """
  @spec initialize_private(socket()) :: socket()
  def initialize_private(socket) do
    %Socket{
      socket
      | private: put_in(socket.private, [Access.key(:assigns, %{})], %{})
    }
  end

  @doc """
  Pushes the private assigns to the component and resets private assigns.

  This function is typically called after state changes to update the URL.
  """
  @spec push_state(socket()) :: socket()
  def push_state(socket) do
    private_assigns = get_in(socket.private, [Access.key(:assigns, %{})]) || %{}

    if private_assigns != %{} do
      send(self(), {:update_component, socket.assigns.path, private_assigns})
    end

    socket
    |> initialize_private()
  end

  # @doc """
  #  Sends a message to delete the component.
  #  """

  # @spec push_delete(socket()) :: socket()
  # def push_delete(socket) do
  #   send(self(), {:update_component, assigns(socket).path, nil})
  #
  #   socket
  # end

  @doc """
  Assigns a value to a key in the socket assigns and tracks it in private assigns if it's a schema field.
  """
  @spec assign(module(), socket(), atom(), any()) :: socket()
  def assign(module, socket, key, value) do
    socket = Component.assign(socket, key, value)

    fields =
      (Extension.get_entities(module, [:attributes]) ++
         Extension.get_entities(module, [:components]))
      |> Enum.map(& &1.name)

    if key in fields do
      %Socket{
        socket
        | private: put_in(socket.private, [Access.key(:assigns, %{}), key], value)
      }
      |> Component.assign(key, value)
    else
      socket
    end
  end

  @doc """
  Assigns a map of values to the socket assigns.
  """
  @spec assign_map(socket(), map()) :: socket()
  def assign_map(socket, map) do
    Component.assign(socket, map)
  end
end
