variable "docker_host" {
  description = "Адрес Docker на VM (SSH проброшен на 127.0.0.1:2222)"
  type        = string
  default     = "ssh://deployer@127.0.0.1:2222"
}

variable "nginx_image" {
  description = "Образ nginx"
  type        = string
  default     = "nginx:1.30-alpine"
}

variable "container_name" {
  description = "Имя контейнера nginx"
  type        = string
  default     = "tf-nginx"
}

variable "network_name" {
  description = "Имя отдельной docker-сети для nginx"
  type        = string
  default     = "tf-nginx-net"
}

variable "volume_name" {
  description = "Имя docker-тома со статикой nginx"
  type        = string
  default     = "tf-nginx-html"
}

variable "external_port" {
  description = "Нестандартный порт, на котором nginx отвечает по HTTP"
  type        = number
  default     = 8081
}
