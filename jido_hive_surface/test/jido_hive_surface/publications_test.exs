defmodule JidoHiveSurface.PublicationsTest do
  use ExUnit.Case, async: true

  alias JidoHiveSurface.Publications

  defmodule OperatorStub do
    def fetch_publication_plan(_api_base_url, _room_id) do
      {:ok,
       %{
         "duplicate_policy" => "canonical_only",
         "source_entries" => ["decision"],
         "publications" => [
           %{
             "channel" => "github",
             "required_bindings" => [%{"field" => "repo"}],
             "draft" => %{"title" => "Draft", "body" => "Body"}
           }
         ]
       }}
    end

    def load_auth_state(_api_base_url, _subject) do
      %{"github" => %{status: :cached, connection_id: "conn-1"}}
    end

    def publish_room(_api_base_url, _room_id, payload), do: {:ok, payload}
  end

  test "loads a publication workspace" do
    workspace =
      Publications.workspace("http://127.0.0.1:4000/api", "room-1", "alice",
        operator_module: OperatorStub
      )

    assert workspace.ready?
    assert workspace.selected_channel.channel == "github"
  end

  test "falls back to an operator default when the override is nil" do
    workspace =
      Publications.workspace("http://127.0.0.1:4000/api", "room-1", "alice",
        operator_module: nil,
        operator_module_fallback: OperatorStub
      )

    assert workspace.ready?
    assert workspace.selected_channel.channel == "github"
  end

  test "publishes a selected channel payload" do
    workspace =
      Publications.workspace("http://127.0.0.1:4000/api", "room-1", "alice",
        operator_module: OperatorStub
      )

    assert {:ok, payload} =
             Publications.publish(
               "http://127.0.0.1:4000/api",
               "room-1",
               workspace,
               %{"github" => %{"repo" => "nshkrdotcom/jido_hive"}},
               operator_module: OperatorStub
             )

    assert payload["channels"] == ["github"]
    assert payload["bindings"]["github"]["repo"] == "nshkrdotcom/jido_hive"
  end
end
