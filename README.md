# Steadmesh example org

A minimal [Steadmesh](https://github.com/darcys22/steadmesh) organisation: four
AI agents ("seats") declared in Terraform and running on Kubernetes.

```
                representative        your voice in the org
                      |
                  tech_lead           plans the work, splits it up
                 /         \
    senior_engineer ---- reviewer     writes code / reviews pull requests
```

Every seat runs [Pi](https://pi.dev), a coding agent, on an LLM of your
choice from any OpenAI-compatible endpoint. Pi itself needs no key or
account: it's the program that reads files, runs tools and edits code, and it
calls the model through the platform. The three engineers share a team that can clone, push and open pull
requests in one GitHub repository.

## What's in here

| Path | What it does |
| --- | --- |
| `platform/main.tf` | Stage 1: namespaces and the Steadmesh Helm chart (the controller that runs agents, and the platform service they talk to). |
| `platform/postgres.tf` | The database the platform keeps memory and messages in. |
| `organisation/main.tf` | Stage 2: stores your API keys and publishes `instructions/` for the agents. |
| `organisation/organisation.tf` | The organisation itself: seats, models, GitHub access, who can talk to whom. |
| `organisation/instructions/` | Plain-English instructions the agents follow, one file per role. |
| `.env.example` | The keys you need to provide. |

Everything is in this repository except the Steadmesh software itself: the
Helm chart and container images (from ghcr.io) and the Terraform provider
(from the Terraform Registry).

There are two stages because the organisation is a custom Kubernetes resource
that only exists once the platform is installed.

**Where the keys go:** both keys are stored as Secrets in the platform's
namespace, which agents can't read. When an agent calls the model, the
platform makes the call with the key, so the model key never reaches an
agent. The GitHub token is different: so the team can run `git` and `gh`
themselves, the platform hands the token to a seat when those commands need
it, and the agent can read it. The token keeps whatever access you gave it on
GitHub, which is why it should be scoped to one test repository. (These keys
are also stored in `organisation/`'s Terraform state, so keep the state files
private.)

## What you need

- **Docker** and **[kind](https://kind.sigs.k8s.io)** (or any Kubernetes
  cluster with a NetworkPolicy-enforcing CNI, a default StorageClass and
  ~4 CPUs / 8 GB free).
- **Terraform** 1.5+, **kubectl**, and **Go** 1.27+ (to install `orgctl`, the
  command you chat with).
- An **LLM endpoint** for Pi to think with: any OpenAI-compatible API (one
  that serves `/v1/chat/completions`), with its base URL, a model name and an
  API key.
- A **GitHub repository** for the team to work in, and a
  [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new)
  scoped to only that repository, with *Contents*, *Pull requests* and
  *Issues* set to read and write. Use a test repository.

## Run it

Run these commands from the root of your checkout (the directory containing
`.env.example`) in Bash or Zsh. Terraform's `-chdir` option keeps your shell
in that directory throughout the walkthrough.

**1. Create a cluster**

```bash
kind create cluster --name steadmesh
```

**2. Add your keys**

```bash
cp .env.example .env     # then fill in .env
set -a; source .env; set +a
```

Terraform reads any `TF_VAR_<name>` environment variable as the variable
`<name>`. Set `TF_VAR_kube_context` in `.env` to the context you want to use
(`kind-steadmesh` for the cluster above). Terraform, `orgctl` and the `kubectl`
commands below all use that context rather than the current one in your
kubeconfig.

In any new terminal, return to the repository root and run
`set -a; source .env; set +a` again before continuing. If you edit `.env`,
reload it in the same way before running the commands again.

If you use a custom kubeconfig, add `TF_VAR_kubeconfig_path=/absolute/path/to/config`
and `KUBECONFIG="$TF_VAR_kubeconfig_path"` (in that order) to `.env` before
loading it. Use the same single file for both so Terraform, `orgctl` and
`kubectl` read the same configuration.

**3. Install the platform**

```bash
terraform -chdir=platform init
terraform -chdir=platform apply
```

**4. Create the organisation**

```bash
terraform -chdir=organisation init
terraform -chdir=organisation apply
```

`apply` returns once all four seats pass their readiness checks. The first
time takes a few minutes while the seat images download.

**5. Talk to your representative**

```bash
go install github.com/darcys22/steadmesh/cmd/orgctl@v0.5.0
orgctl chat --context "$TF_VAR_kube_context" --user me
```

```
Chatting with me's representative over terminal. Ctrl-D or Ctrl-C to leave.
you> Add a CONTRIBUTING.md to the repo explaining how to run the tests.
```

Your representative passes the work to the tech lead, who shares it out with
the senior engineer and the reviewer. They open a pull request in your
repository, and the representative reports back in the chat. If you leave
the chat, its messages wait for you until you reconnect (they are lost if the
platform restarts).

`orgctl` connects through `kubectl port-forward` and reads your login token
from the `terminal-credentials` Secret that `organisation/main.tf` creates.

**6. Watch it**

```bash
kubectl --context "$TF_VAR_kube_context" -n steadmesh get agentseats
kubectl --context "$TF_VAR_kube_context" -n steadmesh-system port-forward deploy/steadmesh-console 8090
# open http://127.0.0.1:8090
```

The console is read-only: you can see the seats, their messages and their
work.

## Change the org

The organisation is in `organisation/organisation.tf`:

- **Add a seat:** add `organisation/instructions/<seat>.md`, copy one of the entries under
  `seats` with `role_ref = local.instructions["<seat>"]`, and add a
  `memory_stores` entry with the same key.
- **Let seats talk:** add a `message_routes` entry. Seats can only message
  along declared routes.
- **Change how agents behave:** edit `organisation/instructions/*.md`. `culture.md`
  applies to everyone, `team.md` to the engineering team, and the rest to one
  seat each.
- **Change the model:** set `TF_VAR_llm_base_url`, `TF_VAR_llm_model` and
  `TF_VAR_llm_api_key` in `.env`.

From the repository root, reload `.env` if you changed it, then preview and
apply the organisation changes:

```bash
set -a; source .env; set +a
terraform -chdir=organisation plan
terraform -chdir=organisation apply
```

Seats keep their memory and workspace across applies.

## Tear down

From the repository root, with `.env` loaded in this terminal:

```bash
terraform -chdir=organisation destroy
terraform -chdir=platform destroy
# Only if you created the kind cluster in step 1:
kind delete cluster --name steadmesh
```

