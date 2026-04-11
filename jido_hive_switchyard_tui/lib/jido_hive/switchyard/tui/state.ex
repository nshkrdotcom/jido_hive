defmodule JidoHive.Switchyard.TUI.State do
  @moduledoc false

  alias JidoHive.Switchyard.Site.Client

  @enforce_keys []
  defstruct client_module: Client,
            screen: :rooms,
            rooms: [],
            room_cursor: 0,
            room_id: nil,
            room_workspace: nil,
            selected_context_id: nil,
            context_cursor: 0,
            draft: "",
            overlay: nil,
            publication_workspace: nil,
            publish_bindings: %{},
            publish_field_cursor: 0

  @type overlay :: %{kind: atom(), payload: map()} | nil

  @type t :: %__MODULE__{
          client_module: module(),
          screen: :rooms | :room,
          rooms: [map()],
          room_cursor: non_neg_integer(),
          room_id: String.t() | nil,
          room_workspace: map() | nil,
          selected_context_id: String.t() | nil,
          context_cursor: non_neg_integer(),
          draft: String.t(),
          overlay: overlay(),
          publication_workspace: map() | nil,
          publish_bindings: map(),
          publish_field_cursor: non_neg_integer()
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []), do: struct(__MODULE__, opts)

  @spec put_rooms(t(), [map()]) :: t()
  def put_rooms(%__MODULE__{} = state, rooms) when is_list(rooms) do
    %{state | rooms: rooms, room_cursor: clamp_index(state.room_cursor, rooms), screen: :rooms}
  end

  @spec move_room_cursor(t(), integer()) :: t()
  def move_room_cursor(%__MODULE__{} = state, delta) when is_integer(delta) do
    %{state | room_cursor: clamp_index(state.room_cursor + delta, state.rooms)}
  end

  @spec selected_room(t()) :: map() | nil
  def selected_room(%__MODULE__{} = state), do: Enum.at(state.rooms, state.room_cursor)

  @spec open_room(t(), map()) :: t()
  def open_room(%__MODULE__{} = state, workspace) when is_map(workspace) do
    selected_context_id =
      Map.get(workspace, :selected_context_id) || Map.get(workspace, "selected_context_id")

    %{
      state
      | screen: :room,
        room_id: Map.get(workspace, :room_id) || Map.get(workspace, "room_id"),
        room_workspace: with_selected_detail(workspace, selected_context_id),
        selected_context_id: selected_context_id,
        context_cursor: context_index(workspace, selected_context_id)
    }
  end

  @spec move_context_cursor(t(), integer()) :: t()
  def move_context_cursor(%__MODULE__{room_workspace: nil} = state, _delta), do: state

  def move_context_cursor(%__MODULE__{} = state, delta) when is_integer(delta) do
    items = context_items(state.room_workspace)
    next_cursor = clamp_index(state.context_cursor + delta, items)
    context_id = items |> Enum.at(next_cursor) |> context_id()

    %{
      state
      | context_cursor: next_cursor,
        selected_context_id: context_id,
        room_workspace: with_selected_detail(state.room_workspace, context_id)
    }
  end

  @spec back_to_rooms(t()) :: t()
  def back_to_rooms(%__MODULE__{} = state) do
    %{state | screen: :rooms, overlay: nil, publication_workspace: nil}
  end

  @spec set_draft(t(), String.t()) :: t()
  def set_draft(%__MODULE__{} = state, draft) when is_binary(draft), do: %{state | draft: draft}

  @spec append_draft(t(), String.t()) :: t()
  def append_draft(%__MODULE__{} = state, text) when is_binary(text) do
    %{state | draft: state.draft <> text}
  end

  @spec draft_backspace(t()) :: t()
  def draft_backspace(%__MODULE__{} = state) do
    %{state | draft: drop_last_grapheme(state.draft)}
  end

  @spec clear_draft(t()) :: t()
  def clear_draft(%__MODULE__{} = state), do: %{state | draft: ""}

  @spec open_overlay(t(), atom(), map()) :: t()
  def open_overlay(%__MODULE__{} = state, kind, payload \\ %{})
      when is_atom(kind) and is_map(payload) do
    %{state | overlay: %{kind: kind, payload: payload}}
  end

  @spec close_overlay(t()) :: t()
  def close_overlay(%__MODULE__{} = state), do: %{state | overlay: nil}

  @spec set_publication_workspace(t(), map() | nil) :: t()
  def set_publication_workspace(%__MODULE__{} = state, workspace)
      when is_map(workspace) or is_nil(workspace) do
    %{state | publication_workspace: workspace, publish_field_cursor: 0}
  end

  @spec current_publish_value(t(), String.t(), String.t()) :: String.t()
  def current_publish_value(%__MODULE__{} = state, channel, field) do
    get_in(state.publish_bindings, [channel, field]) || ""
  end

  @spec put_publish_value(t(), String.t(), String.t(), String.t()) :: t()
  def put_publish_value(%__MODULE__{} = state, channel, field, value)
      when is_binary(channel) and is_binary(field) and is_binary(value) do
    next_bindings =
      Map.update(state.publish_bindings, channel, %{field => value}, fn bindings ->
        Map.put(bindings, field, value)
      end)

    %{state | publish_bindings: next_bindings}
  end

  @spec next_publish_field_cursor(t()) :: t()
  def next_publish_field_cursor(%__MODULE__{} = state) do
    bindings = current_required_bindings(state)

    if bindings == [] do
      state
    else
      %{state | publish_field_cursor: rem(state.publish_field_cursor + 1, length(bindings))}
    end
  end

  @spec publish_backspace(t()) :: t()
  def publish_backspace(%__MODULE__{} = state) do
    case current_binding(state) do
      nil ->
        state

      %{channel: channel, field: field} ->
        current_value = current_publish_value(state, channel, field)
        put_publish_value(state, channel, field, drop_last_grapheme(current_value))
    end
  end

  @spec append_publish_text(t(), String.t()) :: t()
  def append_publish_text(%__MODULE__{} = state, text) when is_binary(text) do
    case current_binding(state) do
      nil ->
        state

      %{channel: channel, field: field} ->
        current_value = current_publish_value(state, channel, field)
        put_publish_value(state, channel, field, current_value <> text)
    end
  end

  defp current_required_bindings(%__MODULE__{} = state) do
    case Map.get(state.publication_workspace || %{}, :selected_channel) do
      nil -> []
      channel -> Enum.map(channel.required_bindings, &Map.put(&1, :channel, channel.channel))
    end
  end

  defp current_binding(%__MODULE__{} = state) do
    Enum.at(current_required_bindings(state), state.publish_field_cursor)
  end

  defp context_items(workspace) do
    workspace
    |> Map.get(:graph_sections, Map.get(workspace, "graph_sections", []))
    |> Enum.flat_map(&Map.get(&1, :items, Map.get(&1, "items", [])))
  end

  defp context_index(workspace, selected_context_id) when is_binary(selected_context_id) do
    workspace
    |> context_items()
    |> Enum.find_index(&(context_id(&1) == selected_context_id))
    |> Kernel.||(0)
  end

  defp context_index(_workspace, _selected_context_id), do: 0

  defp with_selected_detail(workspace, context_id) when is_map(workspace) do
    detail_index = Map.get(workspace, :detail_index, Map.get(workspace, "detail_index", %{}))
    selected_detail = Map.get(detail_index, context_id)

    workspace
    |> Map.put(:selected_context_id, context_id)
    |> Map.put(:selected_detail, selected_detail)
  end

  defp context_id(nil), do: nil
  defp context_id(item), do: Map.get(item, :context_id) || Map.get(item, "context_id")

  defp drop_last_grapheme(""), do: ""

  defp drop_last_grapheme(value) when is_binary(value) do
    value
    |> String.graphemes()
    |> Enum.drop(-1)
    |> Enum.join()
  end

  defp clamp_index(_index, []), do: 0
  defp clamp_index(index, items), do: index |> max(0) |> min(length(items) - 1)
end
