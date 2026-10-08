variable "kube_context" {
  description = "kubeconfig context of the cluster to install into."
  type        = string
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}
