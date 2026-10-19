variable "kube_context" {
  description = "kubeconfig context of the cluster to install into."
  type        = string
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "credential_ledger_secret_name" {
  description = "Existing Secret in steadmesh-system containing the stable ledger encryption key. Empty permits broker-only bootstrap; configure it before applying the organisation."
  type        = string
  default     = ""
}

variable "credential_ledger_secret_key" {
  description = "Entry in the existing ledger Secret containing a base64-encoded 32-byte key; never put the key material in Terraform."
  type        = string
  default     = "key"
}
