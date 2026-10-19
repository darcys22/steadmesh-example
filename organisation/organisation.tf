# Start here: four stable seats, one engineering team and an optional 3–30
# member pool. Role/team prompts live in instructions/. Secrets and instruction
# publishing are plumbing in main.tf; this file is the whole organisation.
#
# representative -> tech_lead -> senior_engineer + reviewer + optional pool
#       declared leadership    |       self-organising engineering

variable "pool_enabled" {
  description = "Add 3–30 native engineering peers using the same model and repository access."
  type        = bool
  default     = false
}

locals {
  # Shared runtime settings, never shared identity or private memory.
  participant = {
    harness_profile   = "pi"
    execution_profile = "interactive"
    sandbox_profile   = "standard"
    workspace         = { persistent = true }
  }
}

resource "steadmesh_organization" "this" {
  key            = "example-org"
  display_name   = "Example Org"
  data_retention = "retain"
  wait_for_ready = true # waits for declared seats; inspect runtime pool members separately

  spec = {
    # How everyone works (instructions/culture.md).
    culture_refs = [local.instructions["culture"]]

    seats = {
      tech_lead = merge(local.participant, {
        display_name    = "Tech lead"
        role_ref        = local.instructions["tech_lead"]
        teams           = ["leadership", "engineering"]
        personal_memory = "tech_lead"
      })
      senior_engineer = merge(local.participant, {
        display_name    = "Senior engineer"
        role_ref        = local.instructions["senior_engineer"]
        teams           = ["engineering"]
        personal_memory = "senior_engineer"
      })
      reviewer = merge(local.participant, {
        display_name    = "Reviewer"
        role_ref        = local.instructions["reviewer"]
        teams           = ["engineering"]
        personal_memory = "reviewer"
      })
      # Your voice in the organisation. You chat with it from a terminal.
      representative = merge(local.participant, {
        display_name    = "Representative"
        role_ref        = local.instructions["representative"]
        teams           = ["leadership"]
        personal_memory = "representative"
      })
    }

    # Coordination, editable context, pool capacity and authority are separate.
    teams = {
      leadership = {
        coordination = { mode = "declared" }
      }
      engineering = {
        instruction_refs = [local.instructions["team"]]
        access_profiles  = ["github_repo"]
        coordination = {
          mode                       = "self_organising"
          mission                    = "Deliver small, tested and independently reviewed changes to the configured GitHub repository."
          work_store                 = "engineering"
          mission_editors            = ["seat:tech_lead"]
          review_policy              = "required"
          max_messages_per_execution = 20
        }
        context = {
          editable_instructions = false # Fixed prompts; memory stays writable.
          editable_summary      = true
        }
        # Explicit opt-in: upgrading does not automatically add pool members.
        # Bounds count pool members only, in addition to the four fixed seats.
        pool = var.pool_enabled ? {
          min_members           = 3
          max_members           = 30
          idle_timeout_seconds  = 900
          drain_timeout_seconds = 300
          retention_seconds     = 0     # Retain retired private data indefinitely.
          draining              = false # Set true to stop admission and drain safely.
          templates = {
            engineer = {
              instructions = "Collaborate as an independent engineer. Claim work on the engineering board, preserve evidence, and obtain another member's review before completion."
              seat = merge(local.participant, {
                display_name = "Pool engineer"
                role_ref     = local.instructions["senior_engineer"]
                # Runtime adds engineering membership and unique private memory.
              })
            }
          }
        } : null
      }
    }

    # Memory: a notebook the team shares, plus a private one per seat.
    memory_stores = {
      engineering     = {}
      tech_lead       = {}
      senior_engineer = {}
      reviewer        = {}
      representative  = {}
    }

    # Memory authority is explicit and independent of prompts/context flags.
    # The representative has read-only engineering memory, no GitHub access.
    grants = {
      engineering_memory = {
        subject    = "team:engineering"
        resource   = "memory:engineering"
        operations = ["read", "search", "write", "revise", "archive", "publish", "history"]
      }
      representative_reads_engineering = {
        subject    = "seat:representative"
        resource   = "memory:engineering"
        operations = ["read", "search"]
      }
    }

    # Who may message whom. Seats can only talk along these routes.
    message_routes = {
      representative_to_lead = { from = "seat:representative", to = "seat:tech_lead", reply = true }
      engineering_peers      = { from = "team:engineering", to = "team:engineering", bidirectional = true }
    }

    # You ("me" on the terminal connection) reach the representative here.
    channel_bindings = {
      me = {
        connection       = "terminal"
        external_user_id = "me"
        seat             = "representative"
        mode             = "direct_message"
      }
    }

    # Output-token ceilings, not money, input-token or concurrency limits.
    model_budgets = {
      organization_daily_output_tokens = 100000
      seat_daily_output_tokens         = 20000
      execution_output_tokens          = 4000
    }

    # External services, pointing at the key Secrets in main.tf.
    connections = {
      # Your LLM endpoint, spoken to with the OpenAI Chat Completions API.
      llm = {
        adapter      = "model" # any OpenAI-compatible endpoint
        endpoint_ref = var.llm_base_url
        secret_ref   = "k8s:${kubernetes_secret_v1.llm.metadata[0].name}"
        model        = { apis = ["openai_chat"], models = [{ id = var.llm_model }] }
      }
      github = { adapter = "github", secret_ref = "k8s:${kubernetes_secret_v1.github.metadata[0].name}" }
      # How you talk to your representative: `orgctl chat` from a terminal.
      terminal = { adapter = "terminal", secret_ref = "k8s:${kubernetes_secret_v1.terminal.metadata[0].name}" }
    }

    # All seats use Pi and the configured model.
    harness_profiles = {
      pi = {
        adapter      = "pi"
        image_digest = "ghcr.io/darcys22/steadmesh/seat-pi:0.7.0"
        model        = { connection = "llm", id = var.llm_model }
      }
    }

    # Where a seat runs: its own Pod, stopped when idle and woken by messages.
    execution_profiles = {
      interactive = {
        backend       = "kubernetes"
        service_class = "interactive"
        idle_policy   = "warm_then_stop"
        idle_timeout  = "15m"
      }
    }
    sandbox_profiles = { standard = {} }

    # What a seat can reach from its sandbox: git and gh on one repository.
    access_profiles = {
      github_repo = {
        tools = { binaries = ["git", "gh"] }
        github = {
          connection  = "github"
          repos       = [var.github_repo]
          permissions = { contents = "write", pull_requests = "write", issues = "write" }
          delivery    = "sandbox"
        }
      }
    }
  }

  timeouts {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

output "conditions" {
  value = steadmesh_organization.this.conditions
}
