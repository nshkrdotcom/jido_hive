defmodule JidoHiveClient.Executor.RepairPolicy do
  @moduledoc false

  alias JidoHiveClient.ExecutionContract

  @default_timeout_ms 30_000

  @spec attempt_repair?(keyword(), String.t() | nil) :: boolean()
  def attempt_repair?(opts, text) when is_list(opts) do
    repair_enabled?(opts) and is_binary(text) and String.trim(text) != ""
  end

  @spec request_opts(map(), keyword()) :: keyword()
  def request_opts(job, opts) when is_map(job) and is_list(opts) do
    [
      cwd: ExecutionContract.workspace_root(job, opts),
      model: Keyword.get(opts, :model),
      timeout_ms: min(Keyword.get(opts, :timeout_ms, @default_timeout_ms), @default_timeout_ms)
    ]
  end

  defp repair_enabled?(opts) when is_list(opts) do
    Keyword.get(opts, :repair_mode, :single_pass) != :disabled
  end
end
