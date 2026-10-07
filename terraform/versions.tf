terraform {
  required_version = ">= 1.6"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6"
    }
  }
  # Backend не задан => local: состояние хранится в terraform/terraform.tfstate
}

# Docker Engine на VM. Подключение по SSH под deployer (не root):
# провайдер запускает на VM `docker system dial-stdio` через ssh.
provider "docker" {
  host = var.docker_host
}
