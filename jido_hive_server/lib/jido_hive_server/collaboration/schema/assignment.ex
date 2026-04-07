defmodule JidoHiveServer.Collaboration.Schema.Assignment do
  @moduledoc false

  @type t :: %__MODULE__{
          assignment_id: String.t(),
          room_id: String.t(),
          participant_id: String.t(),
          participant_role: String.t(),
          target_id: String.t() | nil,
          capability_id: String.t() | nil,
          phase: String.t(),
          objective: String.t(),
          contribution_contract: map(),
          context_view: map(),
          task_context: map(),
          plan_slot_index: non_neg_integer(),
          status: String.t(),
          opened_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          session: map()
        }

  defstruct [
    :assignment_id,
    :room_id,
    :participant_id,
    :participant_role,
    :target_id,
    :capability_id,
    :phase,
    :objective,
    contribution_contract: %{},
    context_view: %{},
    task_context: %{},
    plan_slot_index: 0,
    status: "running",
    opened_at: nil,
    completed_at: nil,
    session: %{}
  ]

  @spec new(map()) :: {:ok, t()} | {:error, {:missing_field, String.t()}}
  def new(attrs) when is_map(attrs) do
    with :ok <-
           require_fields(attrs, [
             "assignment_id",
             "room_id",
             "participant_id",
             "participant_role",
             "phase",
             "objective"
           ]) do
      {:ok,
       %__MODULE__{
         assignment_id: value(attrs, "assignment_id"),
         room_id: value(attrs, "room_id"),
         participant_id: value(attrs, "participant_id"),
         participant_role: value(attrs, "participant_role"),
         target_id: value(attrs, "target_id"),
         capability_id: value(attrs, "capability_id"),
         phase: value(attrs, "phase"),
         objective: value(attrs, "objective"),
         contribution_contract: normalize_map(value(attrs, "contribution_contract")),
         context_view: normalize_map(value(attrs, "context_view")),
         task_context: normalize_map(value(attrs, "task_context")),
         plan_slot_index: integer_value(value(attrs, "plan_slot_index"), 0),
         status: value(attrs, "status") || "running",
         opened_at: datetime_value(value(attrs, "opened_at")) || DateTime.utc_now(),
         completed_at: datetime_value(value(attrs, "completed_at")),
         session: normalize_map(value(attrs, "session"))
       }}
    end
  end

  defp require_fields(attrs, fields) do
    case Enum.find(fields, &missing?(attrs, &1)) do
      nil -> :ok
      field -> {:error, {:missing_field, field}}
    end
  end

  defp missing?(attrs, field) do
    case value(attrs, field) do
      value when is_binary(value) -> String.trim(value) == ""
      nil -> true
      _other -> false
    end
  end

  defp value(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) || Map.get(map, existing_atom_key(key))
  end

  defp existing_atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_other), do: %{}

  defp integer_value(value, _default) when is_integer(value), do: value

  defp integer_value(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> default
    end
  end

  defp integer_value(_value, default), do: default

  defp datetime_value(%DateTime{} = value), do: value

  defp datetime_value(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp datetime_value(_value), do: nil
end
