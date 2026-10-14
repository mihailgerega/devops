# nginx в собственной сети, с подключённым томом, на нестандартном порту.

resource "docker_image" "nginx" {
  name         = var.nginx_image
  keep_locally = true # образ общий с compose, при destroy не удаляем
}

# Отдельная bridge-сеть: контейнер изолирован от default bridge и от сети compose (app-net)
resource "docker_network" "nginx" {
  name   = var.network_name
  driver = "bridge"
}

# Именованный том под статику: переживает пересоздание контейнера
resource "docker_volume" "nginx_html" {
  name = var.volume_name
}

resource "docker_container" "nginx" {
  name    = var.container_name
  image   = docker_image.nginx.image_id
  restart = "unless-stopped" # поднимется сам после перезагрузки VM

  networks_advanced {
    name = docker_network.nginx.name
  }

  # <external_port> на VM -> 80 в контейнере
  ports {
    internal = 80
    external = var.external_port
  }

  volumes {
    volume_name    = docker_volume.nginx_html.name
    container_path = "/usr/share/nginx/html"
  }

  # Страница записывается в том при создании контейнера
  upload {
    file    = "/usr/share/nginx/html/index.html"
    content = <<-EOT
      <!DOCTYPE html>
      <html>
      <head><meta charset="utf-8"><title>tf-nginx</title></head>
      <body><h1>nginx managed by Terraform</h1><p>network: ${var.network_name}, volume: ${var.volume_name}</p></body>
      </html>
    EOT
  }
}
