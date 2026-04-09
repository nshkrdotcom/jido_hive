defmodule JidoHiveServer.Collaboration.DispatchPhaseConfig do
  @moduledoc false

  @spec normalize(term(), [map()]) :: [map()]
  def normalize(phases, default_phases)

  def normalize(nil, default_phases), do: default_phases

  def normalize(phases, default_phases) when is_list(phases) do
    phases
    |> Enum.map(&normalize_phase(&1, default_phases))
    |> Enum.reject(&(&1 == %{}))
  end

  def normalize(_phases, default_phases), do: default_phases

  defp normalize_phase(%{} = phase, default_phases) do
    phase_id = Map.get(phase, "phase") || Map.get(phase, :phase)
    default_phase = default_phase_for(phase_id, default_phases)

    default_phase
    |> Map.merge(stringify_keys(phase))
  end

  defp normalize_phase(phase_id, default_phases) when is_binary(phase_id) do
    default_phase_for(phase_id, default_phases)
  end

  defp normalize_phase(phase_id, default_phases) when is_atom(phase_id) do
    phase_id
    |> Atom.to_string()
    |> normalize_phase(default_phases)
  end

  defp normalize_phase(_phase, _default_phases), do: %{}

  defp default_phase_for(nil, _default_phases), do: %{}

  defp default_phase_for(phase_id, default_phases) do
    Enum.find(default_phases, %{}, fn phase ->
      Map.get(phase, "phase") == phase_id or Map.get(phase, :phase) == phase_id
    end)
  end

  defp stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end
end
