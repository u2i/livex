defmodule Livex.UtilsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias Phoenix.LiveView.JS
  alias Livex.Utils

  describe "push_emit/3" do
    test "handles string events" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          "phx-saved": "handle_saved"
        }
      }

      result = Utils.push_emit(socket, :saved, value: %{id: "123"})
      
      # Extract the pushed event from the result
      assert [
        {:push_event, _, "js-execute", %{ops: ops_json}}
      ] = result.ops
      
      # Parse the JSON to get the operations
      ops = Jason.decode!(ops_json)
      
      # Verify the push operation was created correctly
      assert [push_op] = ops
      assert push_op["kind"] == "push"
      assert push_op["event"] == "handle_saved"
      assert push_op["value"] == %{"id" => "123"}
    end

    test "merges value map into existing JS operations" do
      # Create a JS struct with an existing push operation
      js = JS.push("existing_event", value: %{existing: "value"})
      
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          "phx-saved": js
        }
      }

      # Call push_emit with a new value map
      result = Utils.push_emit(socket, :saved, value: %{new: "value"})
      
      # Extract the pushed event from the result
      assert [
        {:push_event, _, "js-execute", %{ops: ops_json}}
      ] = result.ops
      
      # Parse the JSON to get the operations
      ops = Jason.decode!(ops_json)
      
      # Verify the push operation was updated correctly
      assert [push_op] = ops
      assert push_op["kind"] == "push"
      assert push_op["event"] == "existing_event"
      assert push_op["value"] == %{"existing" => "value", "new" => "value"}
    end

    test "adds push operation if none exists in JS struct" do
      # Create a JS struct with a non-push operation
      js = JS.transition("fade-in")
      
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          "phx-saved": js
        }
      }

      # Call push_emit with a value map
      result = Utils.push_emit(socket, :saved, value: %{id: "123"})
      
      # Extract the pushed event from the result
      assert [
        {:push_event, _, "js-execute", %{ops: ops_json}}
      ] = result.ops
      
      # Parse the JSON to get the operations
      ops = Jason.decode!(ops_json)
      
      # Verify both operations exist
      assert length(ops) == 2
      
      # First operation should be the transition
      assert Enum.at(ops, 0)["kind"] == "transition"
      
      # Second operation should be the push with our value
      push_op = Enum.at(ops, 1)
      assert push_op["kind"] == "push"
      assert push_op["event"] == ""  # Empty event name
      assert push_op["value"] == %{"id" => "123"}
    end
  end
end
