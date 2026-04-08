defmodule JidoHiveTermuiConsole.InputKey do
  @moduledoc false

  alias ExRatatui.Event

  @editing_keys ["backspace", "delete", "left", "right", "home", "end"]
  @non_printable_keys ["up", "down", "enter", "esc", "tab"]

  @spec text_input_key(Event.t()) :: {:ok, String.t()} | :error
  def text_input_key(%Event.Key{code: code, modifiers: modifiers})
      when is_binary(code) and is_list(modifiers) do
    cond do
      code in @editing_keys and modifiers == [] ->
        {:ok, code}

      printable_key?(code, modifiers) ->
        {:ok, normalize_printable(code, modifiers)}

      true ->
        :error
    end
  end

  def text_input_key(_event), do: :error

  defp printable_key?(code, modifiers) do
    byte_size(code) > 0 and
      code not in @non_printable_keys and
      modifiers in [[], ["shift"]]
  end

  defp normalize_printable(code, ["shift"])
       when byte_size(code) == 1 and code >= "a" and code <= "z" do
    String.upcase(code)
  end

  defp normalize_printable(code, _modifiers), do: code
end
