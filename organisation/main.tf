# Stage 2 of 2: your organisation. Apply after ../platform.
#
# This file stores your API keys and publishes the instruction files the
# agents read. The organisation itself is in organisation.tf.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    steadmesh = {
      source  = "darcys22/steadmesh"
      version = "~> 0.5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Namespaces created by ../platform.
locals {
  system_namespace = "steadmesh-system" # the platform
  namespace        = "steadmesh"        # your agents
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

provider "steadmesh" {
  kubeconfig_path = var.kubeconfig_path
  kube_context    = var.kube_context
  namespace       = local.namespace
}

# ---------------------------------------------------------------- API keys
#
# Keys are stored next to the platform, not the agents. The model key never
# reaches a seat: the platform makes model calls on its behalf. The GitHub
# token is different: with delivery = "sandbox" (organisation.tf), git and gh
# in a seat fetch it when they need it, so the agent can read it. That is why
# it should be a fine-grained token for one test repository.

resource "kubernetes_secret_v1" "llm" {
  metadata {
    name      = "llm-credentials"
    namespace = local.system_namespace
  }
  data = {
    api_key = var.llm_api_key
  }
}

resource "kubernetes_secret_v1" "github" {
  metadata {
    name      = "github-credentials"
    namespace = local.system_namespace
  }
  data = {
    token = var.github_token
  }
}

# Your login for `orgctl chat`: a generated token, keyed by your user ID
# ("me"). orgctl reads it from this Secret, so you never type it.
resource "random_password" "terminal_token" {
  length  = 40
  special = false
}

resource "kubernetes_secret_v1" "terminal" {
  metadata {
    name      = "terminal-credentials"
    namespace = local.system_namespace
  }
  data = {
    me = random_password.terminal_token.result
  }
}

# ---------------------------------------------------------------- instructions
#
# Every file in instructions/ goes into one ConfigMap. An agent's instructions
# are referenced as configmap:<name>/<file>#sha256:<hash of the file>, so a
# change to a file is a change Terraform can see.

resource "kubernetes_config_map_v1" "instructions" {
  metadata {
    name      = "instructions"
    namespace = local.namespace
  }
  data = {
    for f in fileset("${path.module}/instructions", "*.md") :
    f => file("${path.module}/instructions/${f}")
  }
}

locals {
  # e.g. local.instructions["reviewer"] = "configmap:instructions/reviewer.md#sha256:..."
  instructions = {
    for f, text in kubernetes_config_map_v1.instructions.data :
    trimsuffix(f, ".md") => "configmap:instructions/${f}#sha256:${sha256(text)}"
  }
}
