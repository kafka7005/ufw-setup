#!/bin/bash

# ============================================================
#   🔥 Remnawave Firewall Setup Script
#   GitHub: https://github.com/your-username/remnawave-firewall
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

STANDARD_PORTS=(22 80 443)

# ─── Helpers ────────────────────────────────────────────────

print_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║       🔥  Remnawave Firewall Manager  🔥         ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_ok()   { echo -e "${GREEN}  [✓]${NC} $1"; }
print_err()  { echo -e "${RED}  [✗]${NC} $1"; }
print_info() { echo -e "${BLUE}  [i]${NC} $1"; }
print_warn() { echo -e "${YELLOW}  [!]${NC} $1"; }
print_sep()  { echo -e "${CYAN}──────────────────────────────────────────────────${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_err "Скрипт должен запускаться от root (sudo)"
        exit 1
    fi
}

validate_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
        return 0
    else
        return 1
    fi
}

validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
        return 0
    else
        return 1
    fi
}

install_ufw() {
    if ! command -v ufw &>/dev/null; then
        print_warn "UFW не установлен. Устанавливаю..."
        apt-get update -qq && apt-get install -y ufw -qq
        print_ok "UFW установлен"
    else
        print_ok "UFW уже установлен"
    fi
}

# ─── UFW Apply ──────────────────────────────────────────────

allow_port_any() {
    local port=$1 proto=${2:-tcp}
    ufw allow "$port/$proto" &>/dev/null
    print_ok "Порт $port/$proto → разрешён (все IP)"
}

allow_port_from_ip() {
    local port=$1 ip=$2 proto=${3:-tcp}
    ufw allow from "$ip" to any port "$port" proto "$proto" &>/dev/null
    print_ok "Порт $port/$proto → разрешён только с $ip"
}

deny_port() {
    local port=$1 proto=${2:-tcp}
    ufw deny "$port/$proto" &>/dev/null
    print_ok "Порт $port/$proto → заблокирован"
}

delete_rule_port() {
    local port=$1 proto=${2:-tcp}
    ufw delete allow "$port/$proto" &>/dev/null
    ufw delete deny  "$port/$proto" &>/dev/null
    print_ok "Правила для порта $port/$proto удалены"
}

# ─── Modes ──────────────────────────────────────────────────

mode_full_setup() {
    print_sep
    echo -e "${BOLD}  ⚙️  Полная настройка фаервола${NC}"
    print_sep

    # 1. Node port
    echo ""
    echo -e "${YELLOW}  Введите порт ноды Remnawave:${NC}"
    read -rp "  Порт ноды: " NODE_PORT
    while ! validate_port "$NODE_PORT"; do
        print_err "Некорректный порт. Введите число от 1 до 65535"
        read -rp "  Порт ноды: " NODE_PORT
    done

    # 2. Panel IP
    echo ""
    echo -e "${YELLOW}  Введите IP-адрес панели Remnawave (для доступа к ноде):${NC}"
    read -rp "  IP панели: " PANEL_IP
    while ! validate_ip "$PANEL_IP"; do
        print_err "Некорректный IP-адрес (допустим формат: 1.2.3.4 или 1.2.3.4/32)"
        read -rp "  IP панели: " PANEL_IP
    done

    # 3. Extra ports
    echo ""
    echo -e "${YELLOW}  Введите дополнительные порты через пробел (или Enter чтобы пропустить):${NC}"
    print_info "Пример: 8080 3000 5432"
    read -rp "  Порты: " -a EXTRA_PORTS

    # Validate extra ports
    VALID_EXTRA=()
    for p in "${EXTRA_PORTS[@]}"; do
        if validate_port "$p"; then
            VALID_EXTRA+=("$p")
        else
            print_warn "Порт '$p' некорректен — пропускаю"
        fi
    done

    # 4. Summary
    echo ""
    print_sep
    echo -e "${BOLD}  📋 Конфигурация:${NC}"
    print_sep
    echo -e "  Стандартные порты : ${GREEN}22, 80, 443${NC} (все IP)"
    echo -e "  Порт ноды         : ${GREEN}$NODE_PORT${NC} → только с ${CYAN}$PANEL_IP${NC}"
    if [[ ${#VALID_EXTRA[@]} -gt 0 ]]; then
        echo -e "  Доп. порты        : ${GREEN}${VALID_EXTRA[*]}${NC} (все IP)"
    fi
    print_sep
    echo ""
    read -rp "  Применить настройки? [y/N]: " CONFIRM
    [[ $CONFIRM =~ ^[Yy]$ ]] || { print_warn "Отменено."; return; }

    echo ""
    print_info "Применяю правила UFW..."

    # Reset & configure
    ufw --force reset &>/dev/null
    ufw default deny incoming &>/dev/null
    ufw default allow outgoing &>/dev/null

    # Standard ports
    for port in "${STANDARD_PORTS[@]}"; do
        allow_port_any "$port"
    done

    # Node port — only from panel IP
    allow_port_from_ip "$NODE_PORT" "$PANEL_IP"

    # Extra ports
    for port in "${VALID_EXTRA[@]}"; do
        allow_port_any "$port"
    done

    # Enable
    ufw --force enable &>/dev/null
    print_ok "UFW включён"

    echo ""
    print_sep
    ufw status numbered
    print_sep
    print_ok "Настройка завершена!"
}

mode_open_port() {
    print_sep
    echo -e "${BOLD}  ➕  Открыть порт${NC}"
    print_sep

    read -rp "  Порт: " PORT
    while ! validate_port "$PORT"; do
        print_err "Некорректный порт"
        read -rp "  Порт: " PORT
    done

    echo -e "${YELLOW}  Протокол [tcp/udp/both] (Enter = tcp):${NC}"
    read -rp "  Протокол: " PROTO
    PROTO=${PROTO:-tcp}
    [[ $PROTO == "both" ]] && PROTO_LIST=(tcp udp) || PROTO_LIST=("$PROTO")

    echo -e "${YELLOW}  Ограничить по IP? Введите IP или Enter для всех:${NC}"
    read -rp "  IP (или Enter): " RESTRICT_IP

    for proto in "${PROTO_LIST[@]}"; do
        if [[ -n "$RESTRICT_IP" ]]; then
            if validate_ip "$RESTRICT_IP"; then
                allow_port_from_ip "$PORT" "$RESTRICT_IP" "$proto"
            else
                print_err "Некорректный IP. Открываю для всех."
                allow_port_any "$PORT" "$proto"
            fi
        else
            allow_port_any "$PORT" "$proto"
        fi
    done
}

mode_close_port() {
    print_sep
    echo -e "${BOLD}  ➖  Закрыть / заблокировать порт${NC}"
    print_sep

    read -rp "  Порт: " PORT
    while ! validate_port "$PORT"; do
        print_err "Некорректный порт"
        read -rp "  Порт: " PORT
    done

    echo -e "${YELLOW}  Протокол [tcp/udp/both] (Enter = tcp):${NC}"
    read -rp "  Протокол: " PROTO
    PROTO=${PROTO:-tcp}
    [[ $PROTO == "both" ]] && PROTO_LIST=(tcp udp) || PROTO_LIST=("$PROTO")

    echo -e "${YELLOW}  Действие: [1] Удалить правило  [2] Явно заблокировать (deny)${NC}"
    read -rp "  Выбор [1/2]: " ACTION

    for proto in "${PROTO_LIST[@]}"; do
        if [[ $ACTION == "2" ]]; then
            deny_port "$PORT" "$proto"
        else
            delete_rule_port "$PORT" "$proto"
        fi
    done
}

mode_block_ip() {
    print_sep
    echo -e "${BOLD}  🚫  Заблокировать IP${NC}"
    print_sep

    read -rp "  IP-адрес (или CIDR, напр. 1.2.3.0/24): " BAN_IP
    if validate_ip "$BAN_IP"; then
        ufw deny from "$BAN_IP" to any &>/dev/null
        print_ok "IP $BAN_IP заблокирован"
    else
        print_err "Некорректный IP"
    fi
}

mode_unblock_ip() {
    print_sep
    echo -e "${BOLD}  ✅  Разблокировать IP${NC}"
    print_sep

    read -rp "  IP-адрес: " UNBAN_IP
    if validate_ip "$UNBAN_IP"; then
        ufw delete deny from "$UNBAN_IP" to any &>/dev/null
        print_ok "Блокировка $UNBAN_IP снята"
    else
        print_err "Некорректный IP"
    fi
}

mode_status() {
    print_sep
    echo -e "${BOLD}  📊  Статус UFW${NC}"
    print_sep
    ufw status verbose
}

mode_reset() {
    print_sep
    echo -e "${BOLD}  ♻️  Полный сброс UFW${NC}"
    print_sep
    print_warn "Это удалит ВСЕ правила фаервола!"
    read -rp "  Вы уверены? Введите 'RESET' для подтверждения: " CONFIRM
    if [[ $CONFIRM == "RESET" ]]; then
        ufw --force reset &>/dev/null
        ufw default deny incoming &>/dev/null
        ufw default allow outgoing &>/dev/null
        allow_port_any 22   # Keep SSH open!
        ufw --force enable &>/dev/null
        print_ok "UFW сброшен. SSH (22) оставлен открытым."
    else
        print_warn "Сброс отменён."
    fi
}

mode_delete_numbered() {
    print_sep
    echo -e "${BOLD}  🗑️  Удалить правило по номеру${NC}"
    print_sep
    ufw status numbered
    echo ""
    read -rp "  Номер правила: " RULE_NUM
    if [[ $RULE_NUM =~ ^[0-9]+$ ]]; then
        ufw --force delete "$RULE_NUM" &>/dev/null
        print_ok "Правило #$RULE_NUM удалено"
    else
        print_err "Некорректный номер"
    fi
}

# ─── Main Menu ──────────────────────────────────────────────

main_menu() {
    while true; do
        echo ""
        print_sep
        echo -e "${BOLD}  📌  Главное меню${NC}"
        print_sep
        echo -e "  ${GREEN}1${NC}) ⚙️  Полная настройка (первый запуск / сброс + новая конфигурация)"
        echo -e "  ${GREEN}2${NC}) ➕  Открыть порт"
        echo -e "  ${GREEN}3${NC}) ➖  Закрыть / заблокировать порт"
        echo -e "  ${GREEN}4${NC}) 🚫  Заблокировать IP"
        echo -e "  ${GREEN}5${NC}) ✅  Разблокировать IP"
        echo -e "  ${GREEN}6${NC}) 🗑️  Удалить правило по номеру"
        echo -e "  ${GREEN}7${NC}) 📊  Статус фаервола"
        echo -e "  ${GREEN}8${NC}) ♻️  Полный сброс UFW"
        echo -e "  ${RED}0${NC}) 🚪  Выход"
        print_sep
        read -rp "  Выбор: " CHOICE

        case $CHOICE in
            1) mode_full_setup ;;
            2) mode_open_port ;;
            3) mode_close_port ;;
            4) mode_block_ip ;;
            5) mode_unblock_ip ;;
            6) mode_delete_numbered ;;
            7) mode_status ;;
            8) mode_reset ;;
            0) echo -e "${GREEN}  До свидания!${NC}"; exit 0 ;;
            *) print_err "Неверный выбор. Попробуйте снова." ;;
        esac
    done
}

# ─── Entry Point ────────────────────────────────────────────

check_root
install_ufw
print_banner

# CLI mode: pass argument to skip menu
case "${1:-}" in
    --setup)   mode_full_setup; exit 0 ;;
    --open)    mode_open_port;  exit 0 ;;
    --close)   mode_close_port; exit 0 ;;
    --status)  mode_status;     exit 0 ;;
    --reset)   mode_reset;      exit 0 ;;
    --help|-h)
        echo ""
        echo -e "${BOLD}  Использование:${NC}"
        echo "  sudo bash firewall-setup.sh           # интерактивное меню"
        echo "  sudo bash firewall-setup.sh --setup   # сразу полная настройка"
        echo "  sudo bash firewall-setup.sh --open    # открыть порт"
        echo "  sudo bash firewall-setup.sh --close   # закрыть порт"
        echo "  sudo bash firewall-setup.sh --status  # статус"
        echo "  sudo bash firewall-setup.sh --reset   # сброс"
        echo ""
        exit 0 ;;
    "") main_menu ;;
    *)  print_err "Неизвестный флаг: $1. Используйте --help"; exit 1 ;;
esac
