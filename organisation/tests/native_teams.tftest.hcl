# Terraform 1.7+; mocked plans only. No cluster, credentials or model calls.
mock_provider "kubernetes" {}
mock_provider "random" {}
mock_provider "steadmesh" {}

variables {
  kube_context = "offline-test"
  llm_base_url = "https://model.example.invalid/v1"
  llm_model    = "offline-model"
  llm_api_key  = "not-a-real-key"
  github_token = "not-a-real-token"
  github_repo  = "example/test-repository"
}

run "four_stable_seats_fixed_prompts" {
  command = plan
  assert {
    condition     = toset(keys(steadmesh_organization.this.spec.seats)) == toset(["representative", "tech_lead", "senior_engineer", "reviewer"])
    error_message = "The four original seat identities must be preserved."
  }
  assert {
    condition     = steadmesh_organization.this.spec.teams.engineering.pool == null
    error_message = "Adding native pool capacity must be an explicit opt-in."
  }
  assert {
    condition = (
      steadmesh_organization.this.spec.teams.leadership.coordination.mode == "declared" &&
      steadmesh_organization.this.spec.teams.engineering.coordination.mode == "self_organising" &&
      steadmesh_organization.this.spec.teams.engineering.coordination.review_policy == "required" &&
      !steadmesh_organization.this.spec.teams.engineering.context.editable_instructions &&
      steadmesh_organization.this.spec.teams.engineering.context.editable_summary
    )
    error_message = "Default hybrid coordination must retain fixed prompts and independent review."
  }
  assert {
    condition = (
      toset(steadmesh_organization.this.spec.seats.representative.teams) == toset(["leadership"]) &&
      toset(steadmesh_organization.this.spec.grants.representative_reads_engineering.operations) == toset(["read", "search"]) &&
      contains(steadmesh_organization.this.spec.grants.engineering_memory.operations, "write") &&
      steadmesh_organization.this.spec.message_routes.engineering_peers.from == "team:engineering" &&
      steadmesh_organization.this.spec.message_routes.representative_to_lead.to == "seat:tech_lead"
    )
    error_message = "Memory authority and message routes must stay explicit and representative access read-only."
  }
}

run "bounded_native_pool" {
  command = plan
  variables {
    pool_enabled = true
  }
  assert {
    condition = (
      steadmesh_organization.this.spec.teams.engineering.pool.min_members == 3 &&
      steadmesh_organization.this.spec.teams.engineering.pool.max_members == 30 &&
      steadmesh_organization.this.spec.teams.engineering.pool.retention_seconds == 0 &&
      !steadmesh_organization.this.spec.teams.engineering.pool.draining &&
      steadmesh_organization.this.spec.model_budgets.organization_daily_output_tokens > 0 &&
      steadmesh_organization.this.spec.model_budgets.execution_output_tokens > 0
    )
    error_message = "Native members need bounded admission, positive shared budgets and indefinite private retention."
  }
  assert {
    condition = (
      steadmesh_organization.this.spec.teams.engineering.pool.templates.engineer.seat.personal_memory == null &&
      steadmesh_organization.this.spec.teams.engineering.pool.templates.engineer.seat.adopt_from == null &&
      steadmesh_organization.this.spec.teams.engineering.pool.templates.engineer.seat.harness_profile == "pi" &&
      steadmesh_organization.this.spec.teams.engineering.pool.templates.engineer.seat.workspace.persistent
    )
    error_message = "A pool member needs its own full seat and private identity."
  }
}
