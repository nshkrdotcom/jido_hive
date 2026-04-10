defmodule JidoHiveClient.RoomFlow do
  @moduledoc """
  Pure room interaction state machine shared by non-TUI harnesses and the console.
  """

  defstruct [
    :room_id,
    :latest_snapshot,
    :latest_submit,
    :latest_run
  ]

  @type t :: %__MODULE__{
          room_id: String.t(),
          latest_snapshot: map() | nil,
          latest_submit: map() | nil,
          latest_run: map() | nil
        }

  @spec new(String.t()) :: t()
  def new(room_id) when is_binary(room_id) do
    %__MODULE__{room_id: room_id, latest_snapshot: nil, latest_submit: nil, latest_run: nil}
  end

  @spec submit_accepted(t(), map()) :: t()
  def submit_accepted(%__MODULE__{} = flow, operation) when is_map(operation) do
    %{flow | latest_submit: normalize_submit(operation)}
  end

  @spec run_accepted(t(), map()) :: t()
  def run_accepted(%__MODULE__{} = flow, operation) when is_map(operation) do
    %{flow | latest_run: normalize_run(operation)}
  end

  @spec ingest_snapshot(t(), map()) :: t()
  def ingest_snapshot(%__MODULE__{} = flow, snapshot) when is_map(snapshot) do
    latest_submit =
      flow.latest_submit
      |> merge_submit_operation(snapshot)
      |> maybe_mark_submit_visible(snapshot)

    latest_run =
      case latest_run_operation(snapshot) do
        nil -> flow.latest_run
        operation -> merge_run_operation(flow.latest_run, operation)
      end

    %{flow | latest_snapshot: snapshot, latest_submit: latest_submit, latest_run: latest_run}
  end

  @spec pending_submit?(t()) :: boolean()
  def pending_submit?(%__MODULE__{latest_submit: nil}), do: false

  def pending_submit?(%__MODULE__{latest_submit: submit}) do
    status = value(submit, "status")
    visible? = value(submit, "visible") == true
    not visible? and status not in ["failed", "visible"]
  end

  @spec pending_run?(t()) :: boolean()
  def pending_run?(%__MODULE__{latest_run: nil}), do: false

  def pending_run?(%__MODULE__{latest_run: run}) do
    value(run, "status") in ["accepted", "running"]
  end

  @spec status(t()) :: {:info | :warn | :error, String.t()}
  def status(%__MODULE__{} = flow) do
    [
      &submit_pending_status/1,
      &submit_failed_status/1,
      &run_pending_status/1,
      &run_failed_status/1,
      &submit_visible_status/1,
      &run_completed_status/1
    ]
    |> Enum.find_value(fn resolver -> resolver.(flow) end)
    |> case do
      nil -> {:info, "Ready"}
      status -> status
    end
  end

  @spec pending_submit(t()) :: map() | nil
  def pending_submit(%__MODULE__{} = flow) do
    if pending_submit?(flow), do: flow.latest_submit, else: nil
  end

  @spec pending_run(t()) :: map() | nil
  def pending_run(%__MODULE__{} = flow) do
    if pending_run?(flow), do: flow.latest_run, else: nil
  end

  defp normalize_submit(operation) do
    %{
      "operation_id" => value(operation, "operation_id"),
      "status" => value(operation, "status") || "accepted",
      "text" => value(operation, "text"),
      "visible" => false,
      "error" => value(operation, "error")
    }
  end

  defp normalize_run(operation) do
    %{
      "operation_id" => value(operation, "operation_id"),
      "client_operation_id" => value(operation, "client_operation_id"),
      "status" => value(operation, "status") || "accepted",
      "kind" => value(operation, "kind") || "room_run",
      "error" => value(operation, "error")
    }
  end

  defp merge_submit_operation(nil, _snapshot), do: nil

  defp merge_submit_operation(submit, snapshot) do
    case find_operation(snapshot, value(submit, "operation_id")) do
      nil ->
        submit

      operation ->
        normalized = normalize_submit(operation)

        submit
        |> Map.merge(normalized)
        |> preserve_existing_if_nil("text", submit, normalized)
        |> preserve_existing_if_nil("error", submit, normalized)
    end
  end

  defp maybe_mark_submit_visible(nil, _snapshot), do: nil

  defp maybe_mark_submit_visible(submit, snapshot) do
    if submit_visible_in_snapshot?(snapshot, value(submit, "text")) do
      submit
      |> Map.put("visible", true)
      |> Map.put("status", "visible")
    else
      submit
    end
  end

  defp latest_run_operation(snapshot) do
    snapshot
    |> operations()
    |> Enum.filter(
      &(value(&1, "kind") == "room_run" or
          String.starts_with?(to_string(value(&1, "operation_id") || ""), "room_run-"))
    )
    |> List.first()
  end

  defp merge_run_operation(nil, operation), do: normalize_run(operation)

  defp merge_run_operation(existing, operation) do
    existing
    |> Map.merge(normalize_run(operation))
    |> Map.put_new("client_operation_id", value(existing, "client_operation_id"))
  end

  defp submit_visible_in_snapshot?(snapshot, text) when is_binary(text) and text != "" do
    Enum.any?(timeline_entries(snapshot), &(value(&1, "body") == text)) or
      Enum.any?(context_objects(snapshot), fn object ->
        value(object, "object_type") == "message" and value(object, "body") == text
      end)
  end

  defp submit_visible_in_snapshot?(_snapshot, _text), do: false

  defp find_operation(snapshot, operation_id) when is_binary(operation_id) do
    Enum.find(operations(snapshot), &(value(&1, "operation_id") == operation_id))
  end

  defp find_operation(_snapshot, _operation_id), do: nil

  defp preserve_existing_if_nil(operation, key, existing, normalized) do
    if is_nil(value(normalized, key)) and not is_nil(value(existing, key)) do
      Map.put(operation, key, value(existing, key))
    else
      operation
    end
  end

  defp timeline_entries(snapshot) do
    case value(snapshot, "timeline") do
      entries when is_list(entries) -> entries
      _other -> []
    end
  end

  defp context_objects(snapshot) do
    case value(snapshot, "context_objects") do
      objects when is_list(objects) -> objects
      _other -> []
    end
  end

  defp operations(snapshot) do
    case value(snapshot, "operations") do
      operations when is_list(operations) -> operations
      _other -> []
    end
  end

  defp run_operation_label(server_operation_id, client_operation_id)
       when is_binary(server_operation_id) and is_binary(client_operation_id) and
              server_operation_id != client_operation_id do
    "server_op=#{server_operation_id} client_op=#{client_operation_id}"
  end

  defp run_operation_label(server_operation_id, _client_operation_id)
       when is_binary(server_operation_id) do
    "op=#{server_operation_id}"
  end

  defp run_operation_label(_server_operation_id, _client_operation_id), do: "op=unknown"

  defp submit_pending_status(flow) do
    if pending_submit?(flow) do
      {:info,
       "Chat submit accepted; waiting for server confirmation. op=#{value(flow.latest_submit, "operation_id")}"}
    end
  end

  defp submit_failed_status(%__MODULE__{latest_submit: submit}) when is_map(submit) do
    if value(submit, "status") == "failed" do
      {:error, "Submit failed: #{value(submit, "error") || "unknown error"}"}
    end
  end

  defp submit_failed_status(_flow), do: nil

  defp run_pending_status(flow) do
    if pending_run?(flow) do
      run = flow.latest_run

      {:info,
       "Room run #{value(run, "status")}; " <>
         run_operation_label(value(run, "operation_id"), value(run, "client_operation_id"))}
    end
  end

  defp run_failed_status(%__MODULE__{latest_run: run}) when is_map(run) do
    if value(run, "status") == "failed" do
      {:error,
       "Room run failed: #{value(run, "error") || "unknown error"} #{run_operation_label(value(run, "operation_id"), value(run, "client_operation_id"))}"}
    end
  end

  defp run_failed_status(_flow), do: nil

  defp submit_visible_status(%__MODULE__{latest_submit: submit}) when is_map(submit) do
    if value(submit, "visible"), do: {:info, "Submitted chat message"}
  end

  defp submit_visible_status(_flow), do: nil

  defp run_completed_status(%__MODULE__{latest_run: run}) when is_map(run) do
    if value(run, "status") == "completed", do: {:info, "Room run completed"}
  end

  defp run_completed_status(_flow), do: nil

  defp value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
