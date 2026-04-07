%{
  version: 1,
  base_url: {:env, "COOLIFY_BASE_URL"},
  token: {:env, "COOLIFY_TOKEN"},
  default_project: :server,
  projects: %{
    server: %{
      app_uuid: {:env, "COOLIFY_APP_UUID"},
      git_branch: "main",
      git_remote: "origin",
      project_path: "jido_hive_server",
      public_base_url: "https://jido-hive-server-test.app.nsai.online",
      readiness: %{
        checks: [
          %{name: "Health", url: "/healthz", expected_status: 200, expected_body_contains: "ok"}
        ]
      },
      verification: %{
        checks: [
          %{
            name: "Landing page",
            url: "/",
            expected_status: 200,
            expected_body_contains: "Jido Hive Server"
          },
          %{
            name: "Targets API",
            url: "/api/targets",
            expected_status: 200,
            expected_body_contains: "\"data\""
          }
        ]
      }
    }
  }
}
