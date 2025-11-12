variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "identity_name" {
  type = string
}

variable "subscription_id" {
  type = string
}

variable "federated_credential_name" {
  type    = string
  default = "ado-federated-credential"
}

variable "oidc_issuer" {
  type = string
}

variable "oidc_subject" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
