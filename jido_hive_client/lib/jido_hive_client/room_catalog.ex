defmodule JidoHiveClient.RoomCatalog do
  @moduledoc """
  Reusable room catalog helpers for headless and interactive operator clients.
  """

  alias JidoHiveClient.Operator

  @type room_summary :: %{
          room_id: String.t(),
          brief: String.t(),
          status: String.t(),
          dispatch_policy_id: String.t(),
          completed_slots: non_neg_integer(),
          total_slots: non_neg_integer(),
          participant_count: non_neg_integer(),
          flagged: boolean(),
          fetch_error: boolean()
        }

  @spec list(String.t(), keyword()) :: [room_summary()]
  def list(api_base_url, opts \\ []) when is_binary(api_base_url) and is_list(opts) do
    operator_module = Keyword.get(opts, :operator_module, Operator)

    api_base_url
    |> operator_module.list_saved_rooms()
    |> Enum.map(&load_room_summary(api_base_url, &1, operator_module))
  end

  defp load_room_summary(api_base_url, room_id, operator_module) do
    case operator_module.fetch_room(api_base_url, room_id) do
      {:ok, snapshot} -> room_summary(snapshot)
      {:error, reason} -> missing_room_summary(room_id, reason)
    end
  end

  defp room_summary(snapshot) do
    dispatch_state = Map.get(snapshot, "dispatch_state", %{})

    %{
      room_id: Map.get(snapshot, "room_id", "unknown"),
      brief: Map.get(snapshot, "brief", ""),
      status: Map.get(snapshot, "status", "unknown"),
      dispatch_policy_id: Map.get(snapshot, "dispatch_policy_id", ""),
      completed_slots: Map.get(dispatch_state, "completed_slots", 0),
      total_slots: Map.get(dispatch_state, "total_slots", 0),
      participant_count: snapshot |> Map.get("participants", []) |> length(),
      flagged: Map.get(snapshot, "status") in ["needs_resolution", "failed"],
      fetch_error: false
    }
  end

  defp missing_room_summary(room_id, _reason) do
    %{
      room_id: room_id,
      brief: "",
      status: "missing",
      dispatch_policy_id: "",
      completed_slots: 0,
      total_slots: 0,
      participant_count: 0,
      flagged: false,
      fetch_error: true
    }
  end
end
