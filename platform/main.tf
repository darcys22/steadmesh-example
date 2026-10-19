# Stage 1 of 2: install Steadmesh into your cluster.
#
# This creates two namespaces, a Postgres database, and the Steadmesh Helm
# chart (the controller that runs your agents and the platform service they
# talk to). It holds no API keys: those belong to your organisation, in
# ../organisation.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}

locals {
  version  = "0.7.0"
  registry = "ghcr.io/darcys22/steadmesh"
}

# The platform runs in steadmesh-system; your agents run in steadmesh.
resource "kubernetes_namespace_v1" "system" {
  metadata {
    name   = "steadmesh-system"
    labels = { "steadmesh.io/role" = "control-plane" }
  }
}

resource "kubernetes_namespace_v1" "organisation" {
  metadata {
    name   = "steadmesh"
    labels = { "steadmesh.io/role" = "organisation" }
  }
}

resource "helm_release" "steadmesh" {
  name       = "steadmesh"
  namespace  = kubernetes_namespace_v1.system.metadata[0].name
  repository = "oci://${local.registry}/charts"
  chart      = "platform"
  version    = local.version
  wait       = true
  timeout    = 600

  values = [yamlencode({
    image = {
      controllerRepository = "${local.registry}/controller"
      platformRepository   = "${local.registry}/platform"
      consoleRepository    = "${local.registry}/console"
      tag                  = local.version
    }
    # Where the platform keeps its state: the Postgres in postgres.tf.
    database = {
      secretName = kubernetes_secret_v1.database_url.metadata[0].name
      secretKey  = "url"
    }
    # Existing Secret only: keep the stable ledger key outside Terraform and
    # Helm. Without it v0.7 refuses all sandbox credential delivery, even PATs.
    credentials = {
      ledgerSecretName = var.credential_ledger_secret_name
      ledgerSecretKey  = var.credential_ledger_secret_key
    }
    # Before starting any agent, the controller checks that the cluster
    # enforces network isolation, using this small probe image.
    controller = {
      netprobeImage = "${local.registry}/seat-fake:${local.version}"
    }
    # A read-only web UI to watch the agents.
    console = { enabled = true }
    # The proxy agents use to reach allowed hosts outside the cluster (GitHub).
    egress = { enabled = true }
  })]

  depends_on = [kubernetes_stateful_set_v1.postgres]
}
