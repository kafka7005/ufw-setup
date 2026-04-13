#!/bin/bash

set -e

LOG_FILE="/var/log/ufw-setup.log"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
  echo -e "$1"
  echo "$(date '+%F %T') | $(echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g')" >> $LOG_FILE
}

error() {
  log "${RED}❌ $1${NC}"
  exit 1
}

success() {
  log "${GREEN}✔ $1${NC}"
}

warn() {
  log "${YELLOW}⚠ $1${NC}"
}

info() {
  log "${CYAN}➜ $1${NC}"
}

header() {
  echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

# Проверка root
[ "$EUID" -ne 0 ] && error "Запусти через sudo"

validate_ip() {
  local ip=$1
  [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
}

validate_port() {
  local port=$1
  [[ "$port" -ge 1 && "$port" -le 65535 ]]
}

backup_rules() {
  header "Бэкап"
  ufw status numbered > /root/ufw-backup-$(date +%F-%H%M).txt
  success "Бэкап сохранён"
}

reset_firewall() {
  header "Сброс UFW"
  warn "Удаляем все правила..."
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  success "UFW сброшен"
}

enable_firewall() {
  header "Запуск UFW"
  ufw --force enable
  success "UFW включён"
}

open_standard_ports() {
  header "Стандартные порты"
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
  success "Открыты: 22, 80, 443"
}

setup_node_port() {
  header "Настройка порта ноды"

  read -p "IP для ноды: " NODE_IP
  validate_ip "$NODE_IP" || error "Неверный IP"

  read -p "Порт ноды: " NODE_PORT
  validate_port "$NODE_PORT" || error "Неверный порт"

  read -p "Протокол (tcp/udp, по умолчанию tcp): " PROTO
  PROTO=${PROTO:-tcp}

  ufw allow from "$NODE_IP" to any port "$NODE_PORT" proto "$PROTO"
  success "Порт $NODE_PORT доступен только для $NODE_IP"
}

extra_ports() {
  header "Дополнительные порты"

  read -p "Порты (через пробел): " PORTS

  for PORT in $PORTS; do
    validate_port "$PORT" || error "Плохой порт: $PORT"
    ufw allow "$PORT"/tcp
    info "Открыт порт $PORT"
  done

  success "Дополнительные порты добавлены"
}

limit_ssh() {
  header "Ограничение SSH"

  read -p "Ограничить SSH по IP? (y/N): " ANSWER
  if [[ "$ANSWER" == "y" ]]; then
    read -p "IP для SSH: " SSH_IP
    validate_ip "$SSH_IP" || error "Неверный IP"

    ufw delete allow 22/tcp || true
    ufw allow from "$SSH_IP" to any port 22 proto tcp

    success "SSH только для $SSH_IP"
  else
    info "SSH оставлен открытым"
  fi
}

delete_port() {
  header "Удаление правила"
  ufw status numbered
  read -p "Номер правила: " NUM
  ufw delete "$NUM"
  success "Удалено"
}

show_status() {
  header "Статус UFW"
  ufw status verbose
}

main_menu() {
  header "UFW Manager"

  echo -e "${CYAN}1) Полная настройка${NC}"
  echo -e "${CYAN}2) Добавить порты${NC}"
  echo -e "${CYAN}3) Удалить правило${NC}"
  echo -e "${CYAN}4) Сбросить UFW${NC}"
  echo -e "${CYAN}5) Статус${NC}"
  echo -e "${CYAN}0) Выход${NC}"
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
