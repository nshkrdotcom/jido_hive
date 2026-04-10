defmodule JidoHiveConsole.TextInputBridge do
  @moduledoc false

  alias JidoHiveConsole.Model
  alias JidoHiveConsole.Screens.Publish

  @spec ensure_refs(Model.t()) :: Model.t()
  def ensure_refs(%Model{} = state) do
    %{
      state
      | room_input_ref: state.room_input_ref || ExRatatui.textarea_new(),
        conflict_input_ref: state.conflict_input_ref || ExRatatui.text_input_new(),
        wizard_brief_input_ref: state.wizard_brief_input_ref || ExRatatui.text_input_new(),
        publish_input_ref: state.publish_input_ref || ExRatatui.text_input_new()
    }
  end

  @spec sync(Model.t()) :: Model.t()
  def sync(%Model{} = state) do
    state
    |> sync_room_ref(state.input_buffer)
    |> sync_ref(:conflict_input_ref, state.conflict_input_buf)
    |> sync_ref(:wizard_brief_input_ref, Map.get(state.wizard_fields, "brief", ""))
    |> sync_publish_ref()
  end

  @spec handle_room_key(Model.t(), String.t(), [String.t()]) :: Model.t()
  def handle_room_key(%Model{} = state, code, modifiers \\ [])
      when is_binary(code) and is_list(modifiers) do
    %{
      state
      | input_buffer:
          edit_room_or_fallback(state.room_input_ref, state.input_buffer, code, modifiers)
    }
  end

  @spec handle_conflict_key(Model.t(), String.t()) :: Model.t()
  def handle_conflict_key(%Model{} = state, code) when is_binary(code) do
    %{
      state
      | conflict_input_buf:
          edit_or_fallback(state.conflict_input_ref, state.conflict_input_buf, code)
    }
  end

  @spec handle_wizard_key(Model.t(), String.t()) :: Model.t()
  def handle_wizard_key(%Model{} = state, code) when is_binary(code) do
    brief =
      edit_or_fallback(
        state.wizard_brief_input_ref,
        Map.get(state.wizard_fields, "brief", ""),
        code
      )

    %{state | wizard_fields: Map.put(state.wizard_fields, "brief", brief)}
  end

  @spec handle_publish_key(Model.t(), String.t()) :: Model.t()
  def handle_publish_key(%Model{} = state, code) when is_binary(code) do
    case Publish.current_focus(state) do
      %{type: :binding, channel: channel, field: field} ->
        current = get_in(state.publish_bindings, [channel, field]) || ""
        value = edit_or_fallback(state.publish_input_ref, current, code)

        %{
          state
          | publish_bindings: put_nested_binding(state.publish_bindings, channel, field, value)
        }

      _other ->
        state
    end
  end

  defp sync_publish_ref(%Model{} = state) do
    desired =
      case Publish.current_focus(state) do
        %{type: :binding, channel: channel, field: field} ->
          get_in(state.publish_bindings, [channel, field]) || ""

        _other ->
          ""
      end

    sync_ref(state, :publish_input_ref, desired)
  end

  defp sync_room_ref(%Model{} = state, desired) when is_binary(desired) do
    case state.room_input_ref do
      ref when is_reference(ref) ->
        current = ExRatatui.textarea_get_value(ref)

        if current != desired do
          ExRatatui.textarea_set_value(ref, desired)
          move_room_cursor_to_end(ref, desired)
        end

        state

      _other ->
        state
    end
  end

  defp sync_ref(%Model{} = state, ref_field, desired) when is_binary(desired) do
    case Map.fetch!(state, ref_field) do
      ref when is_reference(ref) ->
        current = ExRatatui.text_input_get_value(ref)
        if current != desired, do: ExRatatui.text_input_set_value(ref, desired)
        state

      _other ->
        state
    end
  end

  defp edit_room_or_fallback(ref, _current_value, code, modifiers) when is_reference(ref) do
    ExRatatui.textarea_handle_key(ref, code, modifiers)
    ExRatatui.textarea_get_value(ref)
  end

  defp edit_room_or_fallback(_ref, current_value, code, _modifiers),
    do: fallback_room_edit(current_value, code)

  defp edit_or_fallback(ref, _current_value, code) when is_reference(ref) do
    ExRatatui.text_input_handle_key(ref, code)
    ExRatatui.text_input_get_value(ref)
  end

  defp edit_or_fallback(_ref, current_value, code), do: fallback_edit(current_value, code)

  defp put_nested_binding(bindings, channel, field, value) do
    Map.update(bindings, channel, %{field => value}, &Map.put(&1, field, value))
  end

  defp fallback_edit(value, "backspace"), do: drop_last_grapheme(value)

  defp fallback_edit(value, code) when code in ["delete", "left", "right", "home", "end"],
    do: value

  defp fallback_edit(value, code) when is_binary(code), do: value <> code

  defp fallback_room_edit(value, "enter"), do: value <> "\n"
  defp fallback_room_edit(value, code), do: fallback_edit(value, code)

  defp move_room_cursor_to_end(_ref, ""), do: :ok

  defp move_room_cursor_to_end(ref, desired) do
    line_count = desired |> String.split("\n") |> length()

    if line_count > 1 do
      Enum.each(2..line_count, fn _line_index ->
        ExRatatui.textarea_handle_key(ref, "down", [])
      end)
    end

    ExRatatui.textarea_handle_key(ref, "end", [])
  end

  defp drop_last_grapheme(value) do
    value |> String.graphemes() |> Enum.drop(-1) |> Enum.join()
  end
end
