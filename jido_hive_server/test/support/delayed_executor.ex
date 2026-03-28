defmodule JidoHiveServer.TestSupport.DelayedExecutor do
  @moduledoc false

  @behaviour JidoHiveClient.Executor

  alias JidoHiveClient.Executor.Session

  @impl true
  def run(job, opts) when is_map(job) and is_list(opts) do
    delay_ms = Keyword.get(opts, :delay_ms, 0)

    if is_integer(delay_ms) and delay_ms > 0 do
      Process.sleep(delay_ms)
    end

    job
    |> Session.run(Keyword.delete(opts, :delay_ms))
  end
end
