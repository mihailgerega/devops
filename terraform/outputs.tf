output "container_name" {
  value = docker_container.nginx.name
}

output "network_name" {
  value = docker_network.nginx.name
}

output "volume_name" {
  value = docker_volume.nginx_html.name
}

output "check_command" {
  description = "Проверка с хоста (QEMU пробрасывает этот порт с 127.0.0.1 на VM)"
  value       = "curl -i http://127.0.0.1:${var.external_port}"
}
