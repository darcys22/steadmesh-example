variable "kube_context" {
  description = "kubeconfig context of the cluster (the same one ../platform used)."
  type        = string
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "llm_base_url" {
  description = "Base URL of an OpenAI-compatible API, usually ending in /v1."
  type        = string
}

variable "llm_model" {
  description = "Model every seat runs on, as the endpoint names it."
  type        = string
}

variable "llm_api_key" {
  type      = string
  sensitive = true
}

variable "github_token" {
  description = "Fine-grained personal access token for github_repo only."
  type        = string
  sensitive   = true
}

variable "github_repo" {
  description = "Repository the team works in, as owner/name."
  type        = string
}
