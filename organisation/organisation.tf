# The organisation: four agents ("seats") and how they work together.
#
#                 representative
#                       |
#                   tech_lead
#                  /         \
#     senior_engineer ---- reviewer
#
# Every seat runs Pi (pi.dev), a coding agent, on an LLM from any
# OpenAI-compatible endpoint. The three engineers form a team that works in
# one GitHub repository.

resource "steadmesh_organization" "this" {
  key            = "example-org"
  display_name   = "Example Org"
  data_retention = "retain"
  wait_for_ready = true # apply waits until every seat is up and verified

  spec = {
    # How everyone works (instructions/culture.md).
    culture_refs = [local.instructions["culture"]]

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

    # How a seat thinks: Pi is the agent (it reads, runs tools, edits code);
    # the model behind it comes from the llm connection.
    harness_profiles = {
      pi = {
        adapter      = "pi"
        image_digest = "ghcr.io/darcys22/steadmesh/seat-pi:0.4.0"
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

    # Memory: a notebook the team shares, plus a private one per seat.
    memory_stores = {
      engineering     = {}
      tech_lead       = {}
      senior_engineer = {}
      reviewer        = {}
      representative  = {}
    }

    # The engineering team: shared instructions, shared memory, GitHub access.
    teams = {
      engineering = {
        instruction_refs = [local.instructions["team"]]
        shared_memory    = { engineering = ["read", "search", "write", "revise", "archive", "publish", "history"] }
        access_profiles  = ["github_repo"]
      }
    }

    seats = {
      tech_lead = {
        display_name      = "Tech lead"
        role_ref          = local.instructions["tech_lead"]
        teams             = ["engineering"]
        harness_profile   = "pi"
        execution_profile = "interactive"
        sandbox_profile   = "standard"
        personal_memory   = "tech_lead"
        workspace         = { persistent = true }
      }
      senior_engineer = {
        display_name      = "Senior engineer"
        role_ref          = local.instructions["senior_engineer"]
        teams             = ["engineering"]
        harness_profile   = "pi"
        execution_profile = "interactive"
        sandbox_profile   = "standard"
        personal_memory   = "senior_engineer"
        workspace         = { persistent = true }
      }
      reviewer = {
        display_name      = "Reviewer"
        role_ref          = local.instructions["reviewer"]
        teams             = ["engineering"]
        harness_profile   = "pi"
        execution_profile = "interactive"
        sandbox_profile   = "standard"
        personal_memory   = "reviewer"
        workspace         = { persistent = true }
      }
      # Your voice in the organisation. You chat with it from a terminal.
      representative = {
        display_name      = "Representative"
        role_ref          = local.instructions["representative"]
        harness_profile   = "pi"
        execution_profile = "interactive"
        sandbox_profile   = "standard"
        personal_memory   = "representative"
        workspace         = { persistent = true }
      }
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

    # The representative isn't on the team, but may read its notebook.
    grants = {
      representative_reads_engineering = {
        subject    = "seat:representative"
        resource   = "memory:engineering"
        operations = ["read", "search"]
      }
    }

    # Who may message whom. Seats can only talk along these routes.
    message_routes = {
      representative_to_lead = { from = "seat:representative", to = "seat:tech_lead", reply = true }
      lead_engineer          = { from = "seat:tech_lead", to = "seat:senior_engineer", bidirectional = true }
      lead_reviewer          = { from = "seat:tech_lead", to = "seat:reviewer", bidirectional = true }
      engineer_reviewer      = { from = "seat:senior_engineer", to = "seat:reviewer", bidirectional = true }
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
