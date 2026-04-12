defmodule JidoHivePublicationsTest do
  use ExUnit.Case, async: false
  use JidoHivePublications.PersistenceCase

  alias JidoHivePublications

  defmodule OperatorStub do
    def fetch_room(_api_base_url, _room_id) do
      {:ok,
       %{
         "room_id" => "room-1",
         "brief" => "Publish the canonical review",
         "status" => "completed",
         "config" => %{"rules" => ["Preserve the strongest evidence."]},
         "context_objects" => [
           %{
             "context_id" => "ctx-1",
             "object_type" => "decision",
             "title" => "Use canonical transport",
             "body" => "All surfaces should consume canonical room resources."
           }
         ],
         "contributions" => [
           %{
             "participant_role" => "architect",
             "contribution_type" => "publish_request",
             "summary" => "Publish the final review",
             "authority_level" => "binding"
           }
         ]
       }}
    end

    def load_auth_state(_api_base_url, _subject) do
      %{"github" => %{status: :cached, connection_id: "conn-1"}}
    end
  end

  defmodule GatewayStub do
    @behaviour JidoHivePublications.Service.Gateway

    @impl true
    def invoke_publication(plan, input, _opts) do
      {:ok,
       %{
         run: %{run_id: "run-#{plan.channel}", status: :completed},
         output: %{"channel" => plan.channel, "input" => input}
       }}
    end
  end

  setup do
    old_gateway = Application.get_env(:jido_hive_publications, :publication_gateway)
    Application.put_env(:jido_hive_publications, :publication_gateway, GatewayStub)

    on_exit(fn ->
      if old_gateway do
        Application.put_env(:jido_hive_publications, :publication_gateway, old_gateway)
      else
        Application.delete_env(:jido_hive_publications, :publication_gateway)
      end
    end)

    :ok
  end

  test "loads a publication workspace from canonical room resources" do
    workspace =
      JidoHivePublications.load_publication_workspace(
        "http://127.0.0.1:4000/api",
        "room-1",
        "alice",
        operator_module: OperatorStub
      )

    assert workspace.ready?
    assert workspace.selected_channel.channel == "github"
    assert workspace.preview_lines |> hd() =~ "Hive review"
  end

  test "publishes a selected channel payload from the explicit extension seam" do
    workspace =
      JidoHivePublications.load_publication_workspace(
        "http://127.0.0.1:4000/api",
        "room-1",
        "alice",
        operator_module: OperatorStub
      )

    assert {:ok, %{room_id: "room-1", runs: [%{channel: "github"}]}} =
             JidoHivePublications.publish(
               "http://127.0.0.1:4000/api",
               "room-1",
               workspace,
               %{"github" => %{"repo" => "nshkrdotcom/jido_hive"}},
               operator_module: OperatorStub
             )
  end
end
