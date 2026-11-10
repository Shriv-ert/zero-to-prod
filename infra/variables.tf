# infra/variables.tf
variable "region" {
  type    = string
  default = "ap-southeast-3"
}

variable "name" {
  type    = string
  default = "zero-to-prod"
}

variable "image" {
  description = "Container image to run, e.g. ghcr.io/shriv-ert/zero-to-prod:latest"
  type        = string
}

variable "grafana_password" {
  type      = string
  sensitive = true
}

variable "my_ip" {
  description = "Your public IP in CIDR form; Grafana and Prometheus are only reachable from here"
  type        = string
}
