defmodule JidoHiveTermuiConsole.CLI do
  @moduledoc false

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    {opts, _args, _invalid} =
      OptionParser.parse(argv,
        strict: [
          api_base_url: :string,
          room_id: :string,
          participant_id: :string,
          participant_role: :string,
          poll_interval_ms: :integer
        ]
      )

    case Keyword.get(opts, :room_id) do
      nil -> raise ArgumentError, "--room-id is required"
      _room_id -> JidoHiveTermuiConsole.run(opts)
    end
  end
end
