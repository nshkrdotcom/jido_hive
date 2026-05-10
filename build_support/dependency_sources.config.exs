%{
  deps: %{
    jido_ai: %{
      path: "../jido_ai",
      github: %{repo: "agentjido/jido_ai", branch: "main"},
      default_order: [:path, :github],
      publish_order: [:github]
    },
    jido_signal: %{
      path: "../jido_signal",
      github: %{repo: "nshkrdotcom/jido_signal", branch: "main"},
      default_order: [:path, :github],
      publish_order: [:github]
    },
    jido_harness: %{
      path: "../jido_harness",
      github: %{repo: "nshkrdotcom/jido_harness", branch: "main"},
      default_order: [:path, :github],
      publish_order: [:github]
    },
    jido_shell: %{
      path: "../jido_shell",
      github: %{repo: "nshkrdotcom/jido_shell", branch: "main"},
      default_order: [:path, :github],
      publish_order: [:github]
    },
    jido_vfs: %{
      path: "../jido_vfs",
      github: %{repo: "nshkrdotcom/jido_vfs", branch: "main"},
      default_order: [:path, :github],
      publish_order: [:github]
    },
    sprites: %{
      github: %{repo: "mikehostetler/sprites-ex", branch: "main"},
      default_order: [:github],
      publish_order: [:github]
    },
    pristine: %{
      path: "../pristine/apps/pristine_runtime",
      github: %{repo: "nshkrdotcom/pristine", branch: "main", subdir: "apps/pristine_runtime"},
      default_order: [:path, :github],
      publish_order: [:github]
    },
    execution_plane: %{
      path: "../execution_plane/core/execution_plane",
      github: %{
        repo: "nshkrdotcom/execution_plane",
        branch: "main",
        subdir: "core/execution_plane"
      },
      opts: [override: true],
      default_order: [:path, :github],
      publish_order: [:github]
    },
    ground_plane_persistence_policy: %{
      path: "../ground_plane/core/persistence_policy",
      github: %{
        repo: "nshkrdotcom/ground_plane",
        branch: "main",
        subdir: "core/persistence_policy"
      },
      opts: [override: true],
      default_order: [:path, :github],
      publish_order: [:github]
    },
    jido_integration_v2: %{
      path: "../jido_integration/core/platform",
      github: %{repo: "agentjido/jido_integration", branch: "main", subdir: "core/platform"},
      default_order: [:path, :github],
      publish_order: [:github]
    },
    jido_integration_contracts: %{
      path: "../jido_integration/core/contracts",
      github: %{repo: "agentjido/jido_integration", branch: "main", subdir: "core/contracts"},
      default_order: [:path, :github],
      publish_order: [:github]
    },
    jido_integration_v2_asm_runtime_bridge: %{
      path: "../jido_integration/core/asm_runtime_bridge",
      github: %{
        repo: "agentjido/jido_integration",
        branch: "main",
        subdir: "core/asm_runtime_bridge"
      },
      default_order: [:path, :github],
      publish_order: [:github]
    },
    jido_integration_v2_github: %{
      path: "../jido_integration/connectors/github",
      github: %{repo: "agentjido/jido_integration", branch: "main", subdir: "connectors/github"},
      default_order: [:path, :github],
      publish_order: [:github]
    },
    jido_integration_v2_notion: %{
      path: "../jido_integration/connectors/notion",
      github: %{repo: "agentjido/jido_integration", branch: "main", subdir: "connectors/notion"},
      default_order: [:path, :github],
      publish_order: [:github]
    },
    switchyard_contracts: %{
      path: "../switchyard/core/workbench_contracts",
      github: %{
        repo: "nshkrdotcom/switchyard",
        branch: "main",
        subdir: "core/workbench_contracts"
      },
      default_order: [:path, :github],
      publish_order: [:github]
    },
    switchyard_site_local: %{
      path: "../switchyard/sites/site_local",
      github: %{repo: "nshkrdotcom/switchyard", branch: "main", subdir: "sites/site_local"},
      default_order: [:path, :github],
      publish_order: [:github]
    },
    switchyard_tui: %{
      path: "../switchyard/apps/terminal_workbench_tui",
      github: %{
        repo: "nshkrdotcom/switchyard",
        branch: "main",
        subdir: "apps/terminal_workbench_tui"
      },
      default_order: [:path, :github],
      publish_order: [:github]
    },
    workbench_tui_framework: %{
      path: "../switchyard/core/workbench_tui_framework",
      github: %{
        repo: "nshkrdotcom/switchyard",
        branch: "main",
        subdir: "core/workbench_tui_framework"
      },
      default_order: [:path, :github],
      publish_order: [:github]
    },
    workbench_widgets: %{
      path: "../switchyard/core/workbench_widgets",
      github: %{repo: "nshkrdotcom/switchyard", branch: "main", subdir: "core/workbench_widgets"},
      default_order: [:path, :github],
      publish_order: [:github]
    },
    jido_hive_skill_contracts: %{
      path: "core/skill_contracts",
      github: %{repo: "nshkrdotcom/jido_hive", branch: "main", subdir: "core/skill_contracts"},
      default_order: [:path, :github],
      publish_order: [:github]
    },
    jido_hive_skill_engine: %{
      path: "core/skill_engine",
      github: %{repo: "nshkrdotcom/jido_hive", branch: "main", subdir: "core/skill_engine"},
      default_order: [:path, :github],
      publish_order: [:github]
    },
    jido_hive_skill_conformance_contracts: %{
      path: "conformance_contracts/skill_conformance_contracts",
      github: %{
        repo: "nshkrdotcom/jido_hive",
        branch: "main",
        subdir: "conformance_contracts/skill_conformance_contracts"
      },
      default_order: [:path, :github],
      publish_order: [:github]
    },
    jido_hive_agent_coordinator: %{
      path: "core/agent_coordinator",
      github: %{repo: "nshkrdotcom/jido_hive", branch: "main", subdir: "core/agent_coordinator"},
      default_order: [:path, :github],
      publish_order: [:github]
    },
    jido_hive_inter_agent_messaging: %{
      path: "core/inter_agent_messaging",
      github: %{
        repo: "nshkrdotcom/jido_hive",
        branch: "main",
        subdir: "core/inter_agent_messaging"
      },
      default_order: [:path, :github],
      publish_order: [:github]
    },
    jido_hive_shared_memory_facade: %{
      path: "core/shared_memory_facade",
      github: %{
        repo: "nshkrdotcom/jido_hive",
        branch: "main",
        subdir: "core/shared_memory_facade"
      },
      default_order: [:path, :github],
      publish_order: [:github]
    },
    jido_hive_coordination_patterns: %{
      path: "core/coordination_patterns",
      github: %{
        repo: "nshkrdotcom/jido_hive",
        branch: "main",
        subdir: "core/coordination_patterns"
      },
      default_order: [:path, :github],
      publish_order: [:github]
    }
  }
}
