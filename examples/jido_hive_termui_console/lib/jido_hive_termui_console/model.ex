defmodule JidoHiveTermuiConsole.Model do
  @moduledoc false

  alias JidoHiveTermuiConsole.Projection

  defstruct [
    :embedded,
    :embedded_module,
    :room_id,
    :participant_id,
    :participant_role,
    :poll_interval_ms,
    :snapshot,
    input_buffer: "",
    selected_context_index: 0,
    status_line: "Ready",
    screen_width: 120,
    screen_height: 32
  ]

  @type t :: %__MODULE__{}

  @spec new(keyword()) :: t()
  def new(opts) do
    snapshot = Keyword.get(opts, :snapshot, %{timeline: [], context_objects: []})

    %__MODULE__{
      embedded: Keyword.fetch!(opts, :embedded),
      embedded_module: Keyword.get(opts, :embedded_module, JidoHiveClient.Embedded),
      room_id: Keyword.fetch!(opts, :room_id),
      participant_id: Keyword.get(opts, :participant_id, "human-local"),
      participant_role: Keyword.get(opts, :participant_role, "collaborator"),
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, 500),
      snapshot: snapshot
    }
    |> apply_snapshot(snapshot)
  end

  @spec apply_snapshot(t(), map()) :: t()
  def apply_snapshot(%__MODULE__{} = state, snapshot) when is_map(snapshot) do
    selected_index =
      snapshot
      |> Projection.display_context_objects()
      |> clamp_index(state.selected_context_index)

    %{state | snapshot: snapshot, selected_context_index: selected_index}
  end

  @spec append_input(t(), String.t()) :: t()
  def append_input(%__MODULE__{} = state, chunk) when is_binary(chunk) do
    %{state | input_buffer: state.input_buffer <> chunk}
  end

  @spec backspace(t()) :: t()
  def backspace(%__MODULE__{} = state) do
    graphemes = String.graphemes(state.input_buffer)
    %{state | input_buffer: graphemes |> Enum.drop(-1) |> Enum.join()}
  end

  @spec clear_input(t()) :: t()
  def clear_input(%__MODULE__{} = state), do: %{state | input_buffer: ""}

  @spec move_selection(t(), integer()) :: t()
  def move_selection(%__MODULE__{} = state, delta) when is_integer(delta) do
    max_index = max(length(Projection.display_context_objects(state.snapshot)) - 1, 0)
    next_index = min(max(state.selected_context_index + delta, 0), max_index)
    %{state | selected_context_index: next_index}
  end

  @spec selected_context(t()) :: map() | nil
  def selected_context(%__MODULE__{} = state) do
    state.snapshot
    |> Projection.display_context_objects()
    |> Enum.at(state.selected_context_index)
  end

  @spec resize(t(), pos_integer(), pos_integer()) :: t()
  def resize(%__MODULE__{} = state, width, height)
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    %{state | screen_width: width, screen_height: height}
  end

  @spec set_status(t(), String.t()) :: t()
  def set_status(%__MODULE__{} = state, message) when is_binary(message) do
    %{state | status_line: message}
  end

  defp clamp_index([], _selected_index), do: 0

  defp clamp_index(context_objects, selected_index) do
    max_index = max(length(context_objects) - 1, 0)
    min(max(selected_index, 0), max_index)
  end
end
