defmodule JidoHive.SkillConformanceContracts do
  @moduledoc """
  ExUnit helpers for external skill authors.
  """

  use ExUnit.CaseTemplate

  import ExUnit.Assertions

  alias JidoHive.SkillContracts

  using do
    quote do
      import JidoHive.SkillConformanceContracts
    end
  end

  @spec assert_safe_skill_manifest(map() | keyword() | SkillContracts.SkillManifest.t()) ::
          SkillContracts.SkillManifest.t()
  def assert_safe_skill_manifest(attrs) do
    assert {:ok, manifest} = SkillContracts.manifest(attrs)
    manifest
  end

  @spec refute_safe_skill_manifest(map() | keyword(), term() | nil) :: term()
  def refute_safe_skill_manifest(attrs, expected_reason \\ nil) do
    assert {:error, reason} = SkillContracts.manifest(attrs)

    if expected_reason != nil do
      assert reason == expected_reason
    end

    reason
  end
end
