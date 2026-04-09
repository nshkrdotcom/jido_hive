defmodule JidoHiveClient.Polling do
  @moduledoc false

  @default_interval_ms 1_000
  @minimum_interval_ms 1_000
  @max_failure_backoff_ms 10_000
  @max_idle_backoff_ms 5_000

  @spec default_interval_ms() :: pos_integer()
  def default_interval_ms, do: @default_interval_ms

  @spec normalize_interval_ms(term()) :: pos_integer()
  def normalize_interval_ms(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    max(interval_ms, @minimum_interval_ms)
  end

  def normalize_interval_ms(_interval_ms), do: @default_interval_ms

  @spec failure_backoff_delay(pos_integer(), pos_integer()) :: pos_integer()
  def failure_backoff_delay(base_interval_ms, failures)
      when is_integer(base_interval_ms) and base_interval_ms > 0 and is_integer(failures) and
             failures > 0 do
    multiplier = Integer.pow(2, min(failures - 1, 4))
    min(base_interval_ms * multiplier, @max_failure_backoff_ms)
  end

  @spec idle_backoff_delay(pos_integer(), non_neg_integer()) :: pos_integer()
  def idle_backoff_delay(base_interval_ms, quiet_polls)
      when is_integer(base_interval_ms) and base_interval_ms > 0 and is_integer(quiet_polls) and
             quiet_polls >= 0 do
    multiplier = Integer.pow(2, min(quiet_polls, 3))
    min(base_interval_ms * multiplier, @max_idle_backoff_ms)
  end
end
