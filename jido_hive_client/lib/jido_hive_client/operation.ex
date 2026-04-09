defmodule JidoHiveClient.Operation do
  @moduledoc """
  Generates stable, human-readable operation ids for CLI and runtime logs.
  """

  @spec new_id(String.t()) :: String.t()
  def new_id(prefix \\ "op") when is_binary(prefix) do
    suffix =
      6
      |> :crypto.strong_rand_bytes()
      |> Base.encode16(case: :lower)

    "#{prefix}-#{suffix}"
  end
end
