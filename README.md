# Steadmesh example org

A [Steadmesh](https://github.com/darcys22/steadmesh) organisation with four
persistent AI agents ("seats"), native self-organising engineering coordination,
and an opt-in pool of 3–30 additional independent engineers. Terraform declares
the policy; Kubernetes runs the seats.

**Start with [organisation/organisation.tf](organisation/organisation.tf).**
That one file shows the seats, prompt references, team, pool, memory, model
and permissions. The other Terraform files install the platform and wire secrets.

This example pins the provider, chart, images and `orgctl` to **v0.7.0**.
Confirm that its [release](https://github.com/darcys22/steadmesh/releases) has
finished publishing all artifacts before installing. For development without
live models, use the upstream [source examples](https://github.com/darcys22/steadmesh/tree/main/examples/native-hybrid).

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

The representative and tech lead form a declared leadership team. Engineering
uses a shared work board and independent review; only the tech lead may refine
its mission by default. The representative remains outside engineering with
read-only access to its notebook. The four original seat keys, private stores
and workspace settings are unchanged. Pool membership, context editing,
memory permissions and message routes are configured independently.

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

Do not enable the pool merely to validate the configuration. Applying this
example uses your configured model and may incur charges, including readiness
probes. The pool starts disabled. Review output-token limits and capacity before
opting in; 30 pool members is not a promise that a 4-CPU / 8-GB cluster can run
them all at once.

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

For an existing installation, read [Upgrading](#upgrading) first. Provider,
chart, controller, platform, seat images and `orgctl` must match at 0.7.0.

```bash
terraform -chdir=platform init
terraform -chdir=platform apply
```

**Before creating the organisation, configure the credential ledger.** The
first platform apply can run with `TF_VAR_credential_ledger_secret_name` empty
so Terraform creates `steadmesh-system`. In v0.7.0, sandbox credential delivery
is refused until the ledger is configured, including this example's GitHub PAT.

Provision a stable, cryptographically random 32-byte key outside Terraform,
using your secret manager or a protected local file. The Secret entry must
contain its base64-encoded value. With a protected file that contains that
value, you can create the Secret yourself:

```bash
kubectl --context "$TF_VAR_kube_context" -n steadmesh-system create secret generic steadmesh-credential-ledger \
  --from-file=key=/absolute/path/to/protected-ledger-key
```

Do not print the key, put it in command arguments, `.env`, chart values or
source control. Back it up separately from Postgres and preserve it across
restarts/restores; all platform replicas must share it. Do not overwrite an
existing key during an upgrade. See the
[credential-ledger setup](https://steadmesh.com/operations.html#credential-ledger)
for encoding, storage and rotation constraints.

Set `TF_VAR_credential_ledger_secret_name=steadmesh-credential-ledger` in
`.env`, then configure the platform with that **reference only**:

```bash
set -a; source .env; set +a
terraform -chdir=platform plan
terraform -chdir=platform apply
```

**4. Create the organisation**

```bash
terraform -chdir=organisation init
terraform -chdir=organisation apply
```

`apply` returns once the four declared seats pass their readiness checks. The first
time takes a few minutes while the seat images download.

**5. Talk to your representative**

```bash
go install github.com/darcys22/steadmesh/cmd/orgctl@v0.7.0
orgctl verify --context "$TF_VAR_kube_context" --namespace steadmesh --name example-org
orgctl chat --context "$TF_VAR_kube_context" --namespace steadmesh --name example-org --user me
```

```
Chatting with me's representative over terminal. Ctrl-D or Ctrl-C to leave.
you> Add a CONTRIBUTING.md to the repo explaining how to run the tests.
```

Your representative passes the work to the tech lead. Engineering peers claim
work on the shared board, implement it and obtain independent review. They open a pull request in your
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

## Enable the pool

Uncomment `TF_VAR_pool_enabled=true` in `.env`, reload it, then plan and apply
`organisation/`. That is the only extra toggle. The inline policy in
[organisation/organisation.tf](organisation/organisation.tf) shows the rest:

- Four fixed seats remain; the pool adds 3–30 independent peers with their own
  inboxes, private memory, handoffs and workspaces. Available members are not
  continuously generating, and the bound is not a simultaneous-execution cap
- Engineering peers share the declared GitHub access, memory grant and message
  route. Every pool engineer can read the same sandbox GitHub token. The
  representative stays read-only on engineering memory and has no GitHub access
- Working prompts are fixed, private summaries can change, and normal memory
  is writable. Only the tech lead can refine the mission
- Another member must review evidence with `work.review` before board work is
  completed. GitHub PR review is separate; neither means permission to merge
- Output-token ceilings are 100,000 per organisation/day, 20,000 per seat/day
  and 4,000 per execution, plus 20 outgoing messages per execution. These do
  not bound input tokens, currency cost, infrastructure or concurrency

Peers discover each other with `teams.discover`, inspect `teams.pool`, and
request useful capacity with `teams.grow`. Native pool members cannot start
separate disposable task/branch/elastic workers. Declared seats retain their
separate worker limits.

To retire the pool, keep it enabled and change `pool.draining` to true in the
same file before planning/applying. Retired private data is kept indefinitely
(`retention_seconds = 0`); draining neither erases it nor proves work is done.

For advanced changes, edit the visible policy directly: `coordination.mode`
controls peer versus declared pool management; `mission_editors` controls
mission changes; `context` flags control self-context separately from memory
`grants`. Reviewed prompt edits additionally require explicit approvers and a
different reviewer. See the [native-team guide](https://steadmesh.com/native-teams.html)
for the combinations and approval/lifecycle rules.

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

## Upgrading

Keep the 0.7.0 pins in `platform/main.tf`, `organisation/main.tf`, the Pi image
in `organisation/organisation.tf` and the `orgctl` command together. Do not
mix a new provider with old platform or seat binaries.

Back up Postgres, Terraform state and workspace volumes first. Follow the
upstream [upgrade and permission-hardening guide](https://steadmesh.com/operations.html#v070-upgrade),
including worker/controller quiescence and the credential-ledger key. Existing
CRDs must be updated from a verified v0.7.0 source checkout before applying new
organisation policies: Helm does not upgrade existing `crds/` entries. Use
your explicit Kubernetes context, never delete/recreate the CRDs, and confirm
they are established. Schema migrations run automatically and have no supported
automatic rollback; a Helm rollback does not reverse them.

After those prerequisites, initialize with `terraform init -upgrade` in each
stage, review plans, apply `platform` before `organisation`, resync all affected
organisations and run the explicit `orgctl verify` command above. The original
resource and seat identities remain the same. Readiness of the declared seats
does not verify every runtime pool member or autonomous engineering outcome.

## Check without deploying

After v0.7.0 is published, schema validation needs provider downloads but no
cluster or live credentials:

```bash
terraform fmt -check -recursive
terraform -chdir=platform init -backend=false
terraform -chdir=platform validate
terraform -chdir=organisation init -backend=false
terraform -chdir=organisation validate
```

Terraform 1.7+ can also run the mocked configuration tests:

```bash
terraform -chdir=organisation test
```

These use placeholder values and mock providers to check the four-seat
baseline, pool opt-in, bounds, identity separation and explicit permissions.
They do not contact Kubernetes, apply resources, generate real credentials or
call a model. Mocked tests do not establish live runtime behavior.

## Tear down

From the repository root, with `.env` loaded in this terminal:

```bash
terraform -chdir=organisation destroy
terraform -chdir=platform destroy
# Only if you created the kind cluster in step 1:
kind delete cluster --name steadmesh
```

