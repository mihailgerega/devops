terraform {
  required_version = ">= 1.6"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6"
    }
  }
  # backend не задан, значит local: состояние в terraform/terraform.tfstate
}

# Docker на VM, подключение по SSH под пользователем deployer (не root)
provider "docker" {
  host = var.docker_host
}
