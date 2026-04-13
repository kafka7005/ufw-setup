#!/bin/bash

set -e

LOG_FILE="/var/log/ufw-setup.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
  echo -e "$1"
  echo "$(date '+%F %T') | $1" >> $LOG_FILE
}

error() {
  log "${RED}[ERROR] $1${NC}"
  exit 1
}

success() {
  log "${GREEN}[OK] $1${NC}"
}

warn() {
  log "${YELLOW}[WARN] $1${NC}"
}

# Проверка root
[ "$EUID" -ne 0 ] && error "Запусти через sudo"

# Проверка IP
validate_ip() {
  local ip=$1
  [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
}

# Проверка порта
validate_port() {
  local port=$1
  [[ "$port" -ge 1 && "$port" -le 65535 ]]
}

backup_rules() {
  ufw status numbered > /root/ufw-backup-$(date +%F-%H%M).txt
  success "Бэкап правил создан"
}

reset_firewall() {
  warn "Сбрасываем UFW..."
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
}

enable_firewall() {
  ufw --force enable
  success "UFW включен"
}

open_standard_ports() {
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
  success "Открыты 22, 80, 443"
}

setup_node_port() {
  read -p "IP для ноды: " NODE_IP
  validate_ip "$NODE_IP" || error "Неверный IP"

  read -p "Порт ноды: " NODE_PORT
  validate_port "$NODE_PORT" || error "Неверный порт"

  read -p "Протокол (tcp/udp, по умолчанию tcp): " PROTO
  PROTO=${PROTO:-tcp}

  ufw allow from "$NODE_IP" to any port "$NODE_PORT" proto "$PROTO"
  success "Порт $NODE_PORT открыт только для $NODE_IP"
}

extra_ports() {
  read -p "Дополнительные порты (через пробел): " PORTS

  for PORT in $PORTS; do
    validate_port "$PORT" || error "Плохой порт: $PORT"
    ufw allow "$PORT"/tcp
  done

  success "Дополнительные порты добавлены"
}

limit_ssh() {
  read -p "Ограничить SSH по IP? (y/N): " ANSWER
  if [[ "$ANSWER" == "y" ]]; then
    read -p "IP для SSH: " SSH_IP
    validate_ip "$SSH_IP" || error "Неверный IP"

    ufw delete allow 22/tcp || true
    ufw allow from "$SSH_IP" to any port 22 proto tcp

    success "SSH ограничен для $SSH_IP"
  fi
}

delete_port() {
  ufw status numbered
  read -p "Номер правила для удаления: " NUM
  ufw delete "$NUM"
  success "Правило удалено"
}

show_status() {
  ufw status verbose
}

main_menu() {
  echo ""
  echo "1) Полная настройка"
  echo "2) Добавить порты"
  echo "3) Удалить правило"
  echo "4) Сбросить UFW"
  echo "5) Статус"
  echo "0) Выход"
  echo ""

  read -p "Выбор: " CHOICE

  case $CHOICE in
    1)
      backup_rules
      reset_firewall
      open_standard_ports
      setup_node_port
      extra_ports
      limit_ssh
      enable_firewall
      show_status
      ;;
    2)
      extra_ports
      ;;
    3)
      delete_port
      ;;
    4)
      reset_firewall
      ;;
    5)
      show_status
      ;;
    0)
      exit 0
      ;;
    *)
      error "Неизвестный выбор"
      ;;
  esac
}

main_menu
