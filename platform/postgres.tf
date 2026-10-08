# A single Postgres instance for the platform's durable state: agent memory,
# messages and history. Fine for trying things out; use a managed database
# for anything serious.

locals {
  pg_name   = "steadmesh-postgres"
  pg_labels = { "app.kubernetes.io/name" = local.pg_name }
}

resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "postgres" {
  metadata {
    name      = local.pg_name
    namespace = kubernetes_namespace_v1.system.metadata[0].name
  }
  data = {
    POSTGRES_USER     = "steadmesh"
    POSTGRES_PASSWORD = random_password.postgres.result
    POSTGRES_DB       = "steadmesh"
  }
}

# The connection URL the platform reads (see database in main.tf).
resource "kubernetes_secret_v1" "database_url" {
  metadata {
    name      = "steadmesh-db"
    namespace = kubernetes_namespace_v1.system.metadata[0].name
  }
  data = {
    url = "postgres://steadmesh:${random_password.postgres.result}@${local.pg_name}.steadmesh-system.svc:5432/steadmesh?sslmode=disable"
  }
}

resource "kubernetes_service_v1" "postgres" {
  metadata {
    name      = local.pg_name
    namespace = kubernetes_namespace_v1.system.metadata[0].name
  }
  spec {
    selector = local.pg_labels
    port {
      port = 5432
    }
  }
}

resource "kubernetes_stateful_set_v1" "postgres" {
  metadata {
    name      = local.pg_name
    namespace = kubernetes_namespace_v1.system.metadata[0].name
  }
  spec {
    service_name = kubernetes_service_v1.postgres.metadata[0].name
    replicas     = 1
    selector {
      match_labels = local.pg_labels
    }
    template {
      metadata {
        labels = local.pg_labels
      }
      spec {
        security_context {
          run_as_user  = 70 # the postgres user in the alpine image
          run_as_group = 70
          fs_group     = 70
        }
        container {
          name  = "postgres"
          image = "postgres:16.4-alpine"
          port {
            container_port = 5432
          }
          env_from {
            secret_ref {
              name = kubernetes_secret_v1.postgres.metadata[0].name
            }
          }
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }
          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "steadmesh"]
            }
            period_seconds = 5
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = { storage = "5Gi" }
        }
      }
    }
  }
}
