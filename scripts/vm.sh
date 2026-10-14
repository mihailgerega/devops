#!/usr/bin/env bash
# Локальная VM для ДЗ: Ubuntu 22.04 (cloud image) на QEMU/KVM, root не нужен.
#
#   scripts/vm.sh up       — скачать образ (один раз), создать диск и запустить VM
#   scripts/vm.sh down     — штатно выключить VM
#   scripts/vm.sh destroy  — выключить VM и удалить её диск (следующий up — с нуля)
#
# Сеть QEMU user-mode: VM не видна снаружи, доступны только проброшенные порты,
# и они слушают только 127.0.0.1 хоста:
#   127.0.0.1:2222 -> VM:22    SSH
#   127.0.0.1:8080 -> VM:80    nginx из docker compose (/opt/app)
#   127.0.0.1:8081 -> VM:8081  nginx, созданный Terraform
set -euo pipefail

VM_DIR="$(cd "$(dirname "$0")/.." && pwd)/.vm"
IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
BASE_IMG="$VM_DIR/jammy-server-cloudimg-amd64.img"
DISK="$VM_DIR/disk.qcow2"
SEED="$VM_DIR/seed.iso"
PIDFILE="$VM_DIR/qemu.pid"
SSH_PORT=2222
SSH_PUBKEY="${SSH_PUBKEY:-$HOME/.ssh/id_ed25519.pub}"

is_running() {
  [[ -f $PIDFILE ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

up() {
  if is_running; then
    echo "VM уже запущена (pid $(cat "$PIDFILE"))"
    return
  fi
  [[ -r $SSH_PUBKEY ]] || { echo "Нет публичного ключа $SSH_PUBKEY (задайте SSH_PUBKEY=...)" >&2; exit 1; }
  mkdir -p "$VM_DIR"

  [[ -f $BASE_IMG ]] || wget -O "$BASE_IMG" "$IMAGE_URL"
  # Диск VM — copy-on-write поверх базового образа, базовый образ не меняется
  [[ -f $DISK ]] || qemu-img create -q -f qcow2 -F qcow2 -b "$BASE_IMG" "$DISK" 20G

  # cloud-init (NoCloud): кладём наш ключ пользователю ubuntu.
  # Дальше хост настраивает уже Ansible.
  cat > "$VM_DIR/user-data" <<EOF
#cloud-config
hostname: devops-vm
ssh_authorized_keys:
  - $(cat "$SSH_PUBKEY")
EOF
  echo "instance-id: devops-vm" > "$VM_DIR/meta-data"
  xorriso -as mkisofs -quiet -output "$SEED" -volid cidata -joliet -rock \
    "$VM_DIR/user-data" "$VM_DIR/meta-data" 2>/dev/null

  qemu-system-x86_64 \
    -name devops-vm -machine accel=kvm -cpu host -smp 2 -m 2048 \
    -drive file="$DISK",if=virtio \
    -drive file="$SEED",if=virtio,format=raw,readonly=on \
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22,hostfwd=tcp:127.0.0.1:8080-:80,hostfwd=tcp:127.0.0.1:8081-:8081 \
    -device virtio-net-pci,netdev=net0 \
    -display none -serial file:"$VM_DIR/console.log" \
    -daemonize -pidfile "$PIDFILE"

  # Ключ хоста новой VM: убираем старую запись и ждём SSH (accept-new запишет новый ключ)
  ssh-keygen -R "[127.0.0.1]:${SSH_PORT}" >/dev/null 2>&1 || true
  echo -n "Ждём SSH"
  for _ in $(seq 1 60); do
    if ssh -q -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new \
        -p "$SSH_PORT" ubuntu@127.0.0.1 true 2>/dev/null; then
      echo; echo "VM готова: ssh -p ${SSH_PORT} ubuntu@127.0.0.1"
      return
    fi
    echo -n "."; sleep 5
  done
  echo; echo "SSH не поднялся за 5 минут, см. $VM_DIR/console.log" >&2
  exit 1
}

down() {
  is_running || { echo "VM не запущена"; return; }
  local pid; pid="$(cat "$PIDFILE")"
  # Штатное выключение гостя; если за минуту не выключилась — гасим процесс QEMU
  ssh -q -o BatchMode=yes -p "$SSH_PORT" ubuntu@127.0.0.1 sudo poweroff 2>/dev/null || true
  for _ in $(seq 1 60); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  kill "$pid" 2>/dev/null || true
  rm -f "$PIDFILE"
  echo "VM остановлена"
}

destroy() {
  down
  rm -f "$DISK" "$SEED" "$VM_DIR/user-data" "$VM_DIR/meta-data" "$VM_DIR/console.log"
  ssh-keygen -R "[127.0.0.1]:${SSH_PORT}" >/dev/null 2>&1 || true
  echo "Диск VM удалён (базовый образ оставлен в $VM_DIR)"
}

case "${1:-}" in
  up | down | destroy) "$1" ;;
  *) echo "Использование: $0 {up|down|destroy}" >&2; exit 2 ;;
esac
