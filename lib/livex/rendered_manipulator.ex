defmodule Livex.RenderedManipulator do
  @moduledoc """
  A utility library for manipulating Phoenix.LiveView.Rendered structs.
  """

  alias Phoenix.LiveView.Rendered
  alias Phoenix.HTML
  alias Livex.Schema.{State}

  def wrap_in_div(%Rendered{} = rendered, module, assigns) do
    manipulate_rendered(
      :wrap,
      rendered,
      Spark.Dsl.Extension.get_entities(module, [:attributes]),
      assigns,
      tag: "div",
      id: "lv-page-params"
    )
  end

  @doc """
  Manipulates a Phoenix.LiveView.Rendered struct by either injecting attributes or wrapping content.

  ## Options
    * `:inject` - Injects attributes into the first static chunk
    * `:wrap` - Wraps the content with a new tag that has the specified attributes

  ## Parameters
    * `mode` - Either `:inject` or `:wrap`
    * `rendered` - The Phoenix.LiveView.Rendered struct to manipulate
    * `attributes` - List of attribute strings to add
    * `options` - Additional options depending on the mode:
      * For `:inject` mode:
        * `hook_name` - Optional hook name to add
      * For `:wrap` mode:
        * `tag` - The HTML tag to wrap content with
        * `hook_name` - Optional hook name to add
        * `id` - Optional ID to add to the wrapping tag
  """
  def manipulate_rendered(
        mode,
        rendered,
        attributes,
        assigns,
        options \\ nil
      )

  def manipulate_rendered(
        :inject = mode,
        %Rendered{
          static: static,
          dynamic: old_dyn,
          fingerprint: old_fingerprint
        } = rendered,
        attributes,
        assigns,
        options
      ) do
    with attribute_snippets <-
           attribute_snippets(attributes, assigns),
         attribute_snippets <- maybe_prepend_route(mode, attribute_snippets),
         attributes_str <- Enum.join(attribute_snippets, " "),
         new_static <- build_static(mode, static, attributes_str, options) do
      new_dyn = fn arg ->
        [head | tail] = old_dyn.(arg)
        [head] ++ [attributes_str] ++ tail
      end

      # new_fingerprint <- fingerprint(old_fingerprint, attributes_str) do
      %Rendered{
        rendered
        | static: new_static,
          dynamic: new_dyn,
          fingerprint: old_fingerprint
      }
    end
  end

  def manipulate_rendered(
        :wrap = mode,
        %Rendered{
          static: static,
          dynamic: old_dyn,
          fingerprint: old_fingerprint
        } = rendered,
        attributes,
        assigns,
        options
      ) do
    with attribute_snippets <-
           attribute_snippets(attributes, assigns),
         attribute_snippets <- maybe_prepend_route(mode, attribute_snippets),
         attributes_str <- Enum.join(attribute_snippets, " "),
         new_static <- build_static(mode, static, attributes_str, options) do
      id = Keyword.get(options, :id)
      id_str = maybe_add_dom_id(id)

      new_dyn = fn arg ->
        new = old_dyn.(arg)
        [id_str <> attributes_str] ++ [" "] ++ new
      end

      # new_fingerprint <- fingerprint(old_fingerprint, attributes_str) do
      %Rendered{
        rendered
        | static: new_static,
          dynamic: new_dyn,
          fingerprint: old_fingerprint
      }
    end
  end

  # Build static content for inject mode
  defp build_static(:inject, [first_chunk | rest_static], _attributes_str, _options) do
    [first_chunk] ++ [" "] ++ rest_static
  end

  # Build static content for wrap mode
  defp build_static(:wrap, rest_static, _attributes_str, options) do
    tag = Keyword.fetch!(options, :tag)
    [last_chunk | rest_reverse] = Enum.reverse(rest_static)
    new_last = "</#{tag}>" <> last_chunk

    ["<#{tag}"] ++ [">"] ++ Enum.reverse(rest_reverse) ++ [new_last]
  end

  @doc """
  Formats an attribute for inclusion in an HTML tag.

  ## Parameters

  * `name` - The attribute name
  * `value` - The attribute value
  * `prefix` - Optional prefix for the attribute name
  * `type` - Optional type for the attribute name

  ## Returns

  * A formatted attribute string
  """
  def format_attribute(name, value, prefix \\ nil, type \\ nil) do
    attr_name =
      [prefix, type, name]
      |> Enum.filter(& &1)
      |> Enum.join("-")

    "#{attr_name}=\"#{encode(value)}\""
  end

  @doc false
  def encode(value) do
    value
    |> Jason.encode!()
    |> HTML.html_escape()
    |> HTML.safe_to_string()
  end

  @doc false
  def encode_string(value) do
    value
    |> HTML.html_escape()
    |> HTML.safe_to_string()
  end

  # # a bit crude, but should work - take the fingerprint of the underlying compute_fingerprint
  # # and add all the attributes added to the tag
  # defp fingerprint(underlying, attributes) do
  #   <<fingerprint::8*16>> =
  #     [underlying, attributes]
  #     |> :erlang.term_to_binary()
  #     |> :erlang.md5()
  #
  #   fingerprint
  # end

  def attribute_snippets(attributes, assigns) do
    attributes
    |> Enum.filter(&match?(%State{}, &1))
    |> Enum.reduce([], fn attribute, acc ->
      case Map.fetch(assigns, attribute.name) do
        {:ok, nil} ->
          acc

        :error ->
          acc

        {:ok, value} ->
          type = if Map.get(attribute, :url?, false), do: "url", else: "data"
          [format_attribute(attribute.name, value, "lv", type) | acc]
      end
    end)
    |> Enum.reverse()
  end

  def maybe_prepend_route(:wrap, attributes) do
    route_attr =
      " lv-route=\"#{encode_string(Process.get(:__current_route))}\""

    [route_attr | attributes]
  end

  def maybe_prepend_route(_, attributes), do: attributes

  @doc """
  Conditionally adds an ID attribute to an HTML element.

  Returns an ID attribute string if the ID is provided, otherwise returns an empty string.

  ## Examples

      iex> maybe_add_dom_id("my-element")
      " id=\\"my-element\\""
      
      iex> maybe_add_dom_id(nil)
      ""
  """
  def maybe_add_dom_id(nil), do: ""
  def maybe_add_dom_id(id) when is_binary(id), do: " id=\"#{id}\""
end
