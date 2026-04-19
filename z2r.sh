#!/bin/bash

set -e

#Переменная содержащая версию на случай невозможности получить информацию о lastest с github
DEFAULT_VER="0.8.2"

#Чтобы удобнее красить текст
plain='\033[0m'
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
pink='\033[0;35m'
cyan='\033[0;36m'
Fplain='\033[1;37m'
Fred='\033[1;31m'
Fgreen='\033[1;32m'
Fyellow='\033[1;33m'
Fblue='\033[1;34m'
Fpink='\033[1;35m'
Fcyan='\033[1;36m'
Bplain='\033[47m'
Bred='\033[41m'
Bgreen='\033[42m'
Byellow='\033[43m'
Bblue='\033[44m'
Bpink='\033[45m'
Bcyan='\033[46m'

#___Проверка на наличие необходимых библиотек___#

#Определяем путь скрипта, подгружаем функции
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# Проверяем наличие всех нужных lib-файлов, иначе запускаем внешний скрипт
missing_libs=0
LIB_DIR="$SCRIPT_DIR/zapret2/z2r_lib"
for lib in ui.sh provider.sh telemetry.sh recommendations.sh netcheck.sh premium.sh strategies.sh submenus.sh actions.sh; do
  if [ ! -f "$LIB_DIR/$lib" ]; then
    missing_libs=1
    break
  fi
done

if [ "$missing_libs" -ne 0 ]; then
  echo "Не найдены нужные файлы в $LIB_DIR. Запускаю внешний z2r..."
  if command -v curl >/dev/null 2>&1; then
    exec sh -c 'curl -fsSL "https://raw.githubusercontent.com/AloofLibra/z4r/z2r/z2r" | sh'
  elif command -v wget >/dev/null 2>&1; then
    exec sh -c 'wget -qO- "https://raw.githubusercontent.com/AloofLibra/z4r/z2r/z2r" | sh'
  else
    echo "Ошибка: нет curl или wget для загрузки внешнего z2r."
    exit 1
  fi
fi

#___Сначала идут анонсы функций____

# UI helpers (пауза/печать пунктов меню/совместимость старого кода)
# Функции: pause_enter, submenu_item, exit_to_menu
source "$SCRIPT_DIR/zapret2/z2r_lib/ui.sh" 

# Определение провайдера/города + ручная установка/сброс кэша
# Функции: provider_init_once, provider_force_redetect, provider_set_manual_menu
# (внутр.: _detect_api_simple)
source "$SCRIPT_DIR/zapret2/z2r_lib/provider.sh" 

# Телеметрия (вкл/выкл один раз + отправка статистики в Google Forms)
# Функции: init_telemetry, send_stats
source "$SCRIPT_DIR/zapret2/z2r_lib/telemetry.sh" 

# База подсказок по стратегиям (скачивание + вывод подсказки по провайдеру)
# Функции: update_recommendations, show_hint
source "$SCRIPT_DIR/zapret2/z2r_lib/recommendations.sh" 

# Проверка доступности ресурсов/сети (TLS 1.2/1.3) + получение домена кластера youtube (googlevideo)
# Функции: get_yt_cluster_domain, check_access, check_access_list
source "$SCRIPT_DIR/zapret2/z2r_lib/netcheck.sh"

# “Premium” пункты 777/999 и их вспомогательные эффекты (рандом, спиннер, титулы)
# Функции: rand_from_list, spinner_for_seconds, premium_get_or_set_title, zefeer_premium_777, zefeer_space_999
source "$SCRIPT_DIR/zapret2/z2r_lib/premium.sh" 

# Логика стратегий: определение активной стратегии, статус строкой, перебор стратегий, быстрый подбор
# Функции: get_active_strat_num, get_current_strategies_info, try_strategies, Strats_Tryer
source "$SCRIPT_DIR/zapret2/z2r_lib/strategies.sh" 

# Подменю (UI-обвязка над Strats_Tryer + доп. меню управления: FLOWOFFLOAD, TCP443, провайдер)
# Функции: strategies_submenu, flowoffload_submenu, tcp443_submenu, provider_submenu
source "$SCRIPT_DIR/zapret2/z2r_lib/submenus.sh" 

# Действия меню (бэкапы/сбросы/переключатели)
# Функции: backup_strats, menu_action_update_config_reset, menu_action_toggle_bolvan_ports,
#          menu_action_toggle_fwtype, menu_action_toggle_udp_range, menu_action_set_tls_blob
source "$SCRIPT_DIR/zapret2/z2r_lib/actions.sh" 

detect_os() {
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
  elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
  elif [[ -f /opt/etc/entware_release ]]; then
    release="entware"
  elif [[ -f /etc/entware_release ]]; then
    release="entware"
  else
    echo "Не удалось определить ОС. Прекращение работы скрипта." >&2
    exit 1
  fi

  if [[ "$release" == "entware" ]]; then
    if [ -d /jffs ] || uname -a | grep -qi "Merlin"; then
      hardware="merlin"
    elif grep -Eqi "netcraze|keenetic" /proc/version; then
      hardware="keenetic"
    else
      echo -e "${yellow}Железо не определено. Будем считать что это Keenetic. Если будут проблемы - пишите в саппорт.${plain}"
      hardware="keenetic"
    fi
  fi

  #По просьбе наших слушателей) Теперь netcraze официально детектится скриптом не как keenetic, а отдельно)
  if grep -q "netcraze" "/bin/ndmc" 2>/dev/null; then
    echo "OS: $release Netcraze"
  else
    echo "OS: $release $hardware"
  fi

  if [[ "$release" == "ubuntu" || "$release" == "debian" || "$release" == "endeavouros" || "$release" == "arch" ]]; then
    OSystem="VPS"
  elif [[ "$release" == "openwrt" || "$release" == "immortalwrt" || "$release" == "asuswrt" || "$release" == "x-wrt" || "$release" == "kwrt" || "$release" == "istoreos" ]]; then
    OSystem="WRT"
  elif [[ "$release" == "entware" || "$hardware" = "keenetic" ]]; then
    OSystem="entware"
  else
    read -re -p $'\033[31mДля этой ОС нет подходящей функции. Или ОС определение выполнено некорректно.\033[33m Рекомендуется обратиться в чат поддержки
Enter - выход
1 - Плюнуть и продолжить как OpenWRT
2 - Плюнуть и продолжить как entware
3 - Плюнуть и продолжить как VPS\033[0m\n' os_answer
    case "$os_answer" in
    "1")
      OSystem="WRT"
    ;;
    "2")
      OSystem="entware"
    ;;
    "3")
      OSystem="VPS"
    ;;
    *)
      echo "Выбран выход"
      exit 0
    ;;
    esac
  fi
}


set_zapret2_init() {
  if [ "$OSystem" = "WRT" ] && [ -f "/opt/zapret2/init.d/openwrt/zapret2" ]; then
    ZAPRET2_INIT="/opt/zapret2/init.d/openwrt/zapret2"
  else
    ZAPRET2_INIT="/opt/zapret2/init.d/sysv/zapret2"
  fi
  export ZAPRET2_INIT
}

ORCH_DIR="/opt/zapret2/extra_strats/cache/orchestra"
ORCH_SCRIPT="$ORCH_DIR/orchestrator.sh"
ORCH_ENABLED_FLAG="$ORCH_DIR/enabled"
ORCH_LUA_LOCKED="/opt/zapret2/lua/locked.lua"

orchestra_update_from_repo() {
  local url="https://raw.githubusercontent.com/AloofLibra/zapret4rocket/z2r/orchestra/orchestrator.sh"
  local locked_url="https://raw.githubusercontent.com/AloofLibra/zapret4rocket/z2r/orchestra/locked.lua"
  local tmp="${ORCH_SCRIPT}.tmp"

  mkdir -p "$ORCH_DIR"
  if command -v curl >/dev/null 2>&1; then
    if ! curl -fsSL -o "$tmp" "$url"; then
      echo -e "${red}Не удалось скачать оркестратор (curl).${plain}"
      return 1
    fi
    if ! curl -fsSL -o "$ORCH_LUA_LOCKED" "$locked_url"; then
      echo -e "${red}Не удалось скачать locked.lua (curl).${plain}"
      return 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget -qO "$tmp" "$url"; then
      echo -e "${red}Не удалось скачать оркестратор (wget).${plain}"
      return 1
    fi
    if ! wget -qO "$ORCH_LUA_LOCKED" "$locked_url"; then
      echo -e "${red}Не удалось скачать locked.lua (wget).${plain}"
      return 1
    fi
  else
    echo -e "${red}Нет curl или wget для обновления оркестратора.${plain}"
    return 1
  fi

  mv "$tmp" "$ORCH_SCRIPT"
  chmod +x "$ORCH_SCRIPT"
  echo -e "${green}Оркестратор обновлен из репозитория.${plain}"
}

# Проверяем оркестратор и locked.lua, при отсутствии пробуем скачать из репозитория
if [ -f /opt/zapret2/config ]; then
  if [ ! -s "$ORCH_SCRIPT" ] || [ ! -s "$ORCH_LUA_LOCKED" ]; then
    echo "Не найдены orchestrator.sh или locked.lua. Пытаюсь скачать из репозитория..."
    orchestra_update_from_repo || true
  fi
fi

orchestra_start() {
  touch "$ORCH_ENABLED_FLAG"
  if [ ! -x "$ORCH_SCRIPT" ]; then
    orchestra_update_from_repo || true
  fi
  if [ -x "$ORCH_SCRIPT" ]; then
    "$ORCH_SCRIPT" start
  fi
}

orchestra_stop() {
  if [ -x "$ORCH_SCRIPT" ]; then
    "$ORCH_SCRIPT" stop
  fi
  rm -f "$ORCH_ENABLED_FLAG"
}

orchestra_status_text() {
  if [ -x "$ORCH_SCRIPT" ]; then
    if command -v pgrep >/dev/null 2>&1; then
      if pgrep -f "$ORCH_SCRIPT run" >/dev/null 2>&1; then
        echo "Включен"
        return
      fi
    elif pidof sh >/dev/null 2>&1; then
      if ps w | grep -F "$ORCH_SCRIPT run" | grep -v grep >/dev/null 2>&1; then
        echo "Включен"
        return
      fi
    fi
  fi
  if [ -f "$ORCH_ENABLED_FLAG" ]; then
    echo "Включен (не запущен)"
    return
  fi
  echo "Выключен"
}

hostlist_mode_text() {
  local cfg="/opt/zapret2/config"
  if [ -f "$cfg" ]; then
    if grep -q '^MODE_FILTER=autohostlist' "$cfg"; then
      echo "авто"
      return
    fi
    if grep -q '^MODE_FILTER=hostlist' "$cfg"; then
      echo "по листам"
      return
    fi
  fi
  echo "неизвестно"
}

toggle_hostlist_mode() {
  for cfg in /opt/zapret2/config /opt/zapret2/config.default; do
    [ -f "$cfg" ] || continue
    if grep -q '^MODE_FILTER=autohostlist' "$cfg"; then
      sed -i 's/^MODE_FILTER=autohostlist/MODE_FILTER=hostlist/' "$cfg"
      # Disable <HOSTLIST> placeholder for RKN strategy only
      sed -i 's#\(--hostlist=/opt/zapret2/extra_strats/TCP_RKN_list\.txt\) <HOSTLIST>#\1#g' "$cfg"
    elif grep -q '^MODE_FILTER=hostlist' "$cfg"; then
      sed -i 's/^MODE_FILTER=hostlist/MODE_FILTER=autohostlist/' "$cfg"
      # Enable <HOSTLIST> placeholder for RKN strategy only
      sed -i 's#\(--hostlist=/opt/zapret2/extra_strats/TCP_RKN_list\.txt\)#\1 <HOSTLIST>#g' "$cfg"
    fi
  done
}

fallback_mode_text() {
  local cfg="/opt/zapret2/config"
  if [ -f "$cfg" ]; then
    if sed -n '/#Z2R_FALLBACK_BEGIN/,/#Z2R_FALLBACK_END/p' "$cfg" | grep -q '^[[:space:]]*--skip[[:space:]]'; then
      echo "выключен"
      return
    fi
    if sed -n '/#Z2R_FALLBACK_BEGIN/,/#Z2R_FALLBACK_END/p' "$cfg" | grep -q '^[[:space:]]*--filter-tcp=443 --filter-l7=tls'; then
      echo "включен"
      return
    fi
  fi
  echo "неизвестно"
}

toggle_fallback_mode() {
  for cfg in /opt/zapret2/config /opt/zapret2/config.default; do
    [ -f "$cfg" ] || continue
    if sed -n '/#Z2R_FALLBACK_BEGIN/,/#Z2R_FALLBACK_END/p' "$cfg" | grep -q '^[[:space:]]*--skip[[:space:]]'; then
      sed -i '/#Z2R_FALLBACK_BEGIN/,/#Z2R_FALLBACK_END/ s/^[[:space:]]*--skip[[:space:]]\+//' "$cfg"
    else
      sed -i '/#Z2R_FALLBACK_BEGIN/,/#Z2R_FALLBACK_END/ s/^[[:space:]]*--filter-tcp=443 --filter-l7=tls/--skip --filter-tcp=443 --filter-l7=tls/' "$cfg"
    fi
  done
}

fallback_strategy_text() {
  local file="/opt/zapret2/extra_strats/cache/orchestra/locked.manual.tsv"
  if [ -f "$file" ]; then
    local val
    val="$(awk -F '\t' '$1=="8" && $2=="tls" && $3 ~ /^[0-9]+$/ {print $3; exit}' "$file")"
    if [ -n "$val" ]; then
      echo "$val"
      return
    fi
  fi
  echo "не задана"
}

set_fallback_strategy() {
  local file="/opt/zapret2/extra_strats/cache/orchestra/locked.manual.tsv"
  local tmp="${file}.tmp"
  if type check_access >/dev/null 2>&1; then
    check_access "https://5fd8bdae.nip.io/1MB.bin"
  fi
  read -re -p "Введите номер стратегии для безразборного блока: " strategy_num
  mkdir -p /opt/zapret2/extra_strats/cache/orchestra
  if [ -z "$strategy_num" ]; then
    echo "Ввод пустой, ничего не изменено"
  elif ! echo "$strategy_num" | grep -Eq '^[0-9]+$'; then
    echo -e "${red}Некорректный номер стратегии.${plain}"
  else
    if [ -f "$file" ]; then
      awk -F '\t' '$1!="8" || $2!="tls"' "$file" > "$tmp"
    else
      : > "$tmp"
    fi
    printf "8\ttls\t%s\n" "$strategy_num" >> "$tmp"
    mv "$tmp" "$file"
    echo -e "${green}Стратегия $strategy_num закреплена для безразборного блока.${plain}"
  fi
}

fallback_profile_try() {
  local prev_lock_file="${orch_lock_file:-/opt/zapret2/extra_strats/cache/orchestra/locked.tsv}"
  orch_lock_file="/opt/zapret2/extra_strats/cache/orchestra/locked.manual.tsv"
  orch_profile_try "8" "Профиль 8: fallback (безразборный блок)" "tls" "__RUN_CDN_TEST__"
  orch_lock_file="$prev_lock_file"
}

tls_blob_menu_text() {
  local cfg="/opt/zapret2/config"
  local blob_file=""
  local has_tls_maxru=0
  local has_tls_default=0
  if [ ! -f "$cfg" ]; then
    cfg="/opt/zapret2/config.default"
  fi
  if [ ! -f "$cfg" ]; then
    echo "неизвестно"
    return
  fi

  if awk '
      /--filter-l7=tls/ || index($0, "--hostlist=/opt/zapret2/extra_strats/TCP_Discord.txt") {in_tls=1}
      in_tls && /^[[:space:]]*--new[[:space:]]*$/ {in_tls=0}
      in_tls && /--lua-desync=/ && /blob=maxru/ && $0 !~ /strategy=26/ {found=1}
      END {exit(found?0:1)}
    ' "$cfg"; then
    has_tls_maxru=1
  fi
  if awk '
      /--filter-l7=tls/ || index($0, "--hostlist=/opt/zapret2/extra_strats/TCP_Discord.txt") {in_tls=1}
      in_tls && /^[[:space:]]*--new[[:space:]]*$/ {in_tls=0}
      in_tls && /--lua-desync=/ && /blob=fake_default_tls/ && $0 !~ /strategy=26/ {found=1}
      END {exit(found?0:1)}
    ' "$cfg"; then
    has_tls_default=1
  fi

  if [ "$has_tls_default" -eq 1 ] && [ "$has_tls_maxru" -eq 0 ]; then
    echo "default"
    return
  fi
  if [ "$has_tls_default" -eq 1 ] && [ "$has_tls_maxru" -eq 1 ]; then
    echo "mixed"
    return
  fi

  blob_file="$(sed -n -E 's#.*--blob=maxru:@/opt/zapret2/files/fake/([^[:space:]]+).*#\1#p' "$cfg" | head -n1)"
  if [ -n "$blob_file" ]; then
    echo "$blob_file"
  else
    echo "неизвестно"
  fi
}


change_user() {
   if /opt/zapret2/nfq2/nfqws2 --dry-run --user="nobody" 2>&1 | grep -q "queue"; then
    echo "WS_USER=nobody"
	sed -i 's/^#\(WS_USER=nobody\)/\1/' /opt/zapret2/config.default
   elif /opt/zapret2/nfq2/nfqws2 --dry-run --user="$(head -n1 /etc/passwd | cut -d: -f1)" 2>&1 | grep -q "queue"; then
    echo "WS_USER=$(head -n1 /etc/passwd | cut -d: -f1)"
    sed -i "s/^#WS_USER=nobody$/WS_USER=$(head -n1 /etc/passwd | cut -d: -f1)/" "/opt/zapret2/config.default"
   else
    echo -e "${yellow}WS_USER не подошёл. Скорее всего будут проблемы. Если что - пишите в саппорт${plain}"
   fi
}

ensure_nfqws2_stopped() {
  "$ZAPRET2_INIT" stop
  sleep 1
  if pidof nfqws2 >/dev/null; then
    if command -v killall >/dev/null 2>&1; then
      killall -9 nfqws2
    else
      pkill -9 nfqws2
    fi
    sleep 1
  fi
}

blockcheck2_run_summary() {
  local blockcheck_path="/opt/zapret2/blockcheck2.sh"
  local log_dir="/opt/zapret2/extra_strats/cache/blockcheck2"
  local provider_file="/opt/zapret2/extra_strats/cache/provider.txt"
  local provider_label="" provider_sanitized="" ts=""
  local log_file="" summary_file="" summary_public=""
  local uuid_suffix=""
  local was_running=0 rc=0
  local pid=0 start_ts=0
  local progress_file="/tmp/blockcheck2_progress_$$"

  if [ ! -x "$blockcheck_path" ]; then
    echo -e "${red}blockcheck2.sh не найден или не исполняемый: $blockcheck_path${plain}"
    return 1
  fi

  if pidof nfqws2 >/dev/null; then
    was_running=1
    ensure_nfqws2_stopped
    echo -e "${green}Выполнена команда остановки zapret2${plain}"
  fi

  mkdir -p "$log_dir"
  ts="$(date +%Y%m%d_%H%M%S)"
  if [ -s "$provider_file" ]; then
    provider_label="$(cat "$provider_file")"
  else
    provider_label="Unknown"
  fi
  provider_sanitized="$(echo "$provider_label" | tr -cd 'a-zA-Z0-9 ._-' | tr ' ' '_' | cut -c1-60)"
  [ -z "$provider_sanitized" ] && provider_sanitized="Unknown"

  uuid_suffix="$(blockcheck2_get_uuid)"
  log_file="$log_dir/blockcheck2_${provider_sanitized}_${ts}_${uuid_suffix}.log"
  summary_file="$log_dir/blockcheck2_${provider_sanitized}_${ts}_${uuid_suffix}.summary"
  summary_public="/opt/zapret2/blockcheck2_summary.txt"

  local domains_override=""
  read -re -p "Введите домен/URL для теста blockcheck2 (Enter - по умолчанию): " domains_override

  echo -e "${yellow}Запускаю blockcheck2 (BATCH=1)...${plain}"
  start_ts="$(date +%s)"
  if [ -n "$domains_override" ]; then
    CURL_HTTPS_GET=1 BATCH=1 DOMAINS="$domains_override" BC2_PROGRESS_FILE="$progress_file" ZAPRET_BASE=/opt/zapret2 "$blockcheck_path" >"$log_file" 2>&1 &
  else
    CURL_HTTPS_GET=1 BATCH=1 BC2_PROGRESS_FILE="$progress_file" ZAPRET_BASE=/opt/zapret2 "$blockcheck_path" >"$log_file" 2>&1 &
  fi
  pid=$!
  if [ "$pid" -gt 0 ]; then
    local spin='|/-\' idx=0 pct=0 elapsed=0 elapsed_fmt="" overrun_notice=0
    local done=0 total=0 eta=0 eta_fmt=""
    while kill -0 "$pid" >/dev/null 2>&1; do
      elapsed=$(( $(date +%s) - start_ts ))
      if [ -s "$progress_file" ]; then
        read -r done total <"$progress_file"
        if [ -n "$total" ] && [ "$total" -gt 0 ]; then
          pct=$(( (done * 100) / total ))
          if [ "$done" -gt 0 ]; then
            eta=$(( (elapsed * (total - done)) / done ))
            eta_fmt="$(blockcheck2_format_elapsed "$eta")"
          else
            eta_fmt="?"
          fi
        else
          pct="$(blockcheck2_progress_percent "$elapsed")"
          eta_fmt="?"
        fi
      else
        pct="$(blockcheck2_progress_percent "$elapsed")"
        eta_fmt="?"
      fi
      elapsed_fmt="$(blockcheck2_format_elapsed "$elapsed")"
      printf "\r${yellow}blockcheck2: %3s%% %s elapsed %s ETA %s${plain}" "$pct" "${spin:$idx:1}" "$elapsed_fmt" "$eta_fmt"
      if [ "$pct" -ge 100 ] && [ "$overrun_notice" -eq 0 ]; then
        echo -e "\n${yellow}Скрипт выполняется дольше обычного. Это ожидаемо. Дождитесь завершения работы скрипта.${plain}"
        echo -e "\n${yellow}И вообще 146% - не предел${plain}"
        overrun_notice=1
      fi
      idx=$(( (idx + 1) % 4 ))
      sleep 1
    done
    wait "$pid" || rc=$?
    rm -f "$progress_file" 2>/dev/null || true
    elapsed_fmt="$(blockcheck2_format_elapsed "$(( $(date +%s) - start_ts ))")"
    printf "\r${yellow}blockcheck2: 100%% done (elapsed %s)${plain}\n" "$elapsed_fmt"
  else
    echo -e "${red}Не удалось запустить blockcheck2.${plain}"
    rc=1
  fi

  # Extract SUMMARY block only
  awk '
    /^\* SUMMARY/ {in_summary=1}
    in_summary {
      if (/^\* COMMON/ || /^Please note this SUMMARY/ || /^Understanding how strategies work/) exit
      print
    }
  ' "$log_file" > "$summary_file"

  if [ ! -s "$summary_file" ]; then
    echo -e "${red}SUMMARY не найден. Лог сохранен: $log_file${plain}"
  else
    cp "$summary_file" "$summary_public"
    echo -e "${green}SUMMARY сохранен для просмотра: $summary_public${plain}"
    echo -e "${yellow}Пожалуйста, отправьте этот файл в чат z4r: $summary_public${plain}"
    echo -e "${yellow}Нажмите Enter чтобы продолжить${plain}"
    read -r
  fi

  if [ "$was_running" -eq 1 ]; then
    "$ZAPRET2_INIT" restart
    echo -e "${green}zapret2 восстановлен (restart)${plain}"
  fi

  return $rc
}

blockcheck2_progress_percent() {
  local elapsed="$1"
  local total=$((2 * 60 * 60))
  if [ "$elapsed" -le 0 ]; then
    echo 0
    return
  fi
  echo $(( (elapsed * 100) / total ))
}

blockcheck2_format_elapsed() {
  local total="$1" hours=0 mins=0 secs=0
  if [ "$total" -ge 3600 ]; then
    hours=$(( total / 3600 ))
    mins=$(( (total % 3600) / 60 ))
    secs=$(( total % 60 ))
    printf "%dh%02dm%02ds" "$hours" "$mins" "$secs"
  elif [ "$total" -ge 60 ]; then
    mins=$(( total / 60 ))
    secs=$(( total % 60 ))
    printf "%dm%02ds" "$mins" "$secs"
  else
    printf "%ss" "$total"
  fi
}

blockcheck2_get_uuid() {
  local tel_uuid=""
  if [ -n "$TELEMETRY_CFG" ] && [ -f "$TELEMETRY_CFG" ]; then
    source "$TELEMETRY_CFG"
  fi
  if [ -z "$tel_uuid" ]; then
    if [ -f /proc/sys/kernel/random/uuid ]; then
      tel_uuid="$(cut -c1-8 /proc/sys/kernel/random/uuid)"
    else
      tel_uuid="$(date +%s%N | md5sum | head -c 8)"
    fi
    if [ -n "$TELEMETRY_CFG" ]; then
      mkdir -p "$(dirname "$TELEMETRY_CFG")"
      echo "tel_enabled=${tel_enabled:-0}" > "$TELEMETRY_CFG"
      echo "tel_uuid=$tel_uuid" >> "$TELEMETRY_CFG"
    fi
  fi
  echo "$tel_uuid"
}

run_cdn_test() {
  BIN_THR_BYTES=$((24*1024))
  PARALLEL=6

  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  NC='\033[0m'

  TESTS=(
  "US.CF-01|🇺🇸 Cloudflare|$BIN_THR_BYTES|1|https://img.wzstats.gg/cleaver/gunFullDisplay"
  "US.CF-02|🇺🇸 Cloudflare|104319|1|https://genshin.jmp.blue/characters/all#"
  "US.CF-03|🇺🇸 Cloudflare|109863|1|https://api.frankfurter.dev/v1/2000-01-01..2002-12-31"
  "US.CF-04|🇨🇦 Cloudflare|79655|1|https://www.bigcartel.com/"
  "US.DO-01|🇺🇸 DigitalOcean|195612|2|https://genderize.io/"
  "DE.HE-01|🇩🇪 Hetzner|$BIN_THR_BYTES|1|https://j.dejure.org/jcg/doctrine/doctrine_banner.webp"
  "DE.HE-02|🇩🇪 Hetzner|162646|1|https://accesorioscelular.com/tienda/css/plugins.css"
  "FI.HE-01|🇫🇮 Hetzner|$BIN_THR_BYTES|1|https://251b5cd9.nip.io/1MB.bin"
  "FI.HE-02|🇫🇮 Hetzner|$BIN_THR_BYTES|1|https://nioges.com/libs/fontawesome/webfonts/fa-solid-900.woff2"
  "FI.HE-03|🇫🇮 Hetzner|$BIN_THR_BYTES|1|https://5fd8bdae.nip.io/1MB.bin"
  "FI.HE-04|🇫🇮 Hetzner|$BIN_THR_BYTES|1|https://5fd8bca5.nip.io/1MB.bin"
  "FR.OVH-01|🇫🇷 OVH|75872|1|https://eu.api.ovh.com/console/rapidoc-min.js"
  "FR.OVH-02|🇫🇷 OVH|$BIN_THR_BYTES|1|https://ovh.sfx.ovh/10M.bin"
  "SE.OR-01|🇸🇪 Oracle|$BIN_THR_BYTES|1|https://oracle.sfx.ovh/10M.bin"
  "DE.AWS-01|🇩🇪 AWS|$BIN_THR_BYTES|1|https://www.getscope.com/assets/fonts/fa-solid-900.woff2"
  "US.AWS-01|🇺🇸 AWS|215419|1|https://corp.kaltura.com/wp-content/cache/min/1/wp-content/themes/airfleet/dist/styles/theme.css"
  "US.GC-01|🇺🇸 Google Cloud|176277|1|https://api.usercentrics.eu/gvl/v3/en.json"
  "US.FST-01|🇺🇸 Fastly|77597|1|https://www.jetblue.com/footer/footer-element-es2015.js"
  "CA.FST-01|🇨🇦 Fastly|84086|1|https://ssl.p.jwpcdn.com/player/v/8.40.5/bidding.js"
  "US.AKM-01|🇺🇸 Akamai|$BIN_THR_BYTES|1|https://www.roxio.com/static/roxio/images/products/creator/nxt9/call-action-footer-bg.jpg"
  "PL.AKM-01|🇵🇱 Akamai|$BIN_THR_BYTES|1|https://media-assets.stryker.com/is/image/stryker/gateway_1?\$max_width_1410\$"
  "US.CDN77-01|🇺🇸 CDN77|$BIN_THR_BYTES|1|https://cdn.eso.org/images/banner1920/eso2520a.jpg"
  "FR.CNTB-01|🇫🇷 Contabo|$BIN_THR_BYTES|1|https://xdmarineshop.gr/index.php?route=index"
  "NL.SW-01|🇳🇱 Scaleway|$BIN_THR_BYTES|1|https://www.velivole.fr/img/header.jpg"
  "US.CNST-01|🇺🇸 Constant|$BIN_THR_BYTES|1|https://cdn.xuansiwei.com/common/lib/font-awesome/4.7.0/fontawesome-webfont.woff2?v=4.7.0"
  )

  check_one() {
      IFS='|' read -r id provider thr times url <<< "$1"

      total=0
      code=0

      for ((i=1;i<=times;i++)); do
          read bytes code <<< $(curl -L -s \
              -H "Range: bytes=0-${thr}" \
              --connect-timeout 5 \
              --max-time 5 \
              -o /dev/null \
              -w '%{size_download} %{http_code}' \
              "$url")

          total=$((total+bytes))
      done

      avg=$((total/times))

      if (( avg >= thr )) && [[ "$code" =~ ^2|3 ]]; then
          echo -e "${GREEN}$id OK${NC} ${avg}b [$provider]"
          echo OK >> /tmp/cdn_ok
      else
          echo -e "${RED}$id FAIL${NC} ${avg}b code=$code [$provider]"
          echo FAIL >> /tmp/cdn_fail
      fi
  }

  export -f check_one
  export BIN_THR_BYTES PARALLEL GREEN RED YELLOW NC

  rm -f /tmp/cdn_ok /tmp/cdn_fail

  pids_parallels=()
  for test_parallel in "${TESTS[@]}"; do
    check_one "$test_parallel" &
    pids_parallels+=($!)

    # ограничение параллельных задач
    if [ "${#pids_parallels[@]}" -ge "$PARALLEL" ]; then
      wait "${pids_parallels[0]}"
      pids_parallels=("${pids_parallels[@]:1}")
    fi
  done

  # ждём оставшиеся
  for pid_parallel in "${pids_parallels[@]}"; do
    wait "$pid_parallel"
  done

  OK_COUNT=$(wc -l < /tmp/cdn_ok 2>/dev/null)
  FAIL_COUNT=$(wc -l < /tmp/cdn_fail 2>/dev/null)

  echo
  echo -e "${YELLOW}=== SUMMARY ===${NC}"
  echo -e "${GREEN}OK:${NC} ${OK_COUNT:-0}"
  echo -e "${RED}FAIL:${NC} ${FAIL_COUNT:-0}"
}

#Создаём папки и забираем файлы папок lists, fake, extra_strats, копируем конфиг, скрипты для войсов DS, WA, TG
get_repo() {
  mkdir -p /opt/zapret2/lists /opt/zapret2/extra_strats /opt/zapret2/extra_strats/cache
  mkdir -p /opt/zapret2/extra_strats/cache/orchestra
  chmod 777 /opt/zapret2/extra_strats/cache/orchestra 2>/dev/null || true
  orchestra_update_from_repo || true
  for listfile in cloudflare-ipset.txt cloudflare-ipset_v6.txt netrogat.txt russia-discord.txt russia-youtube-rtmps.txt russia-youtube.txt russia-youtubeQ.txt tg_cidr.txt; do
    curl -L -o /opt/zapret2/lists/$listfile https://raw.githubusercontent.com/IndeecFOX/zapret4rocket/z4r/lists/$listfile
  done
  curl -L "https://raw.githubusercontent.com/IndeecFOX/zapret4rocket/master/fake_files.tar.gz" | tar -xz -C /opt/zapret2/files/fake
  curl -L -o /opt/zapret2/extra_strats/UDP_YT_list.txt https://raw.githubusercontent.com/AloofLibra/zapret4rocket/z2r/extra_strats/UDP/YT/List.txt
  curl -L -o /opt/zapret2/extra_strats/TCP_RKN_list.txt https://raw.githubusercontent.com/AloofLibra/zapret4rocket/z2r/extra_strats/TCP/RKN/List.txt
  curl -L -o /opt/zapret2/extra_strats/TCP_YT_list.txt https://raw.githubusercontent.com/AloofLibra/zapret4rocket/z2r/extra_strats/TCP/YT/List.txt
  curl -L -o /opt/zapret2/extra_strats/TCP_GV_list.txt https://raw.githubusercontent.com/AloofLibra/zapret4rocket/z2r/extra_strats/TCP/GV/List.txt
  curl -L -o /opt/zapret2/extra_strats/TCP_Discord.txt https://raw.githubusercontent.com/AloofLibra/zapret4rocket/z2r/extra_strats/TCP/RKN/Discord.txt
  if [ ! -f /opt/zapret2/files/fake/custom_tls.bin ]; then
    mkdir -p /opt/zapret2/files/fake
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL -o /opt/zapret2/files/fake/custom_tls.bin \
        https://raw.githubusercontent.com/AloofLibra/zapret4rocket/z2r/fake/custom_tls.bin
    elif command -v wget >/dev/null 2>&1; then
      wget -qO /opt/zapret2/files/fake/custom_tls.bin \
        https://raw.githubusercontent.com/AloofLibra/zapret4rocket/z2r/fake/custom_tls.bin
    else
      echo -e "${yellow}Не удалось скачать custom_tls.bin: нет curl/wget.${plain}"
    fi
  fi
  touch /opt/zapret2/lists/autohostlist.txt
  if [ -d /opt/extra_strats ]; then
    rm -rf /opt/zapret2/extra_strats
    mv /opt/extra_strats /opt/zapret2/
    echo "Востановление настроек подбора из резерва выполнено."
  fi
  if [ -f "/opt/netrogat.txt" ]; then
    mv -f /opt/netrogat.txt /opt/zapret2/lists/netrogat.txt
    echo "Востановление листа исключений выполнено."
  fi
  #Копирование нашего конфига на замену стандартному и скриптов для войсов DS, WA, TG
  curl -L -o /opt/zapret2/config.default https://raw.githubusercontent.com/AloofLibra/zapret4rocket/z2r/config.default
  if command -v nft >/dev/null 2>&1; then
    sed -i 's/^FWTYPE=iptables$/FWTYPE=nftables/' "/opt/zapret2/config.default"
  fi
  init_dir="$(dirname "$ZAPRET2_INIT")"
  custom_dir="$init_dir/custom.d"
  mkdir -p "$custom_dir"
  curl -L -o "$custom_dir/50-stun4all" https://raw.githubusercontent.com/bol-van/zapret2/master/init.d/custom.d.examples.linux/50-stun4all
  curl -L -o "$custom_dir/50-discord-media" https://raw.githubusercontent.com/bol-van/zapret2/master/init.d/custom.d.examples.linux/50-discord-media

# cache
mkdir -p /opt/zapret2/extra_strats/cache

}

#Удаление старого запрета, если есть
remove_zapret() {
 if [ -f "$ZAPRET2_INIT" ] && [ -f "/opt/zapret2/config" ]; then
 	"$ZAPRET2_INIT" stop
 fi
 if [ -f "/opt/zapret2/config" ] && [ -f "/opt/zapret2/uninstall_easy.sh" ]; then
     echo "Выполняем zapret2/uninstall_easy.sh"
     sh /opt/zapret2/uninstall_easy.sh
     echo "Скрипт uninstall_easy.sh выполнен."
 else
     echo "zapret2 не инсталлирован в систему. Переходим к следующему шагу."
 fi
 if [ -d "/opt/zapret2" ]; then
     echo "Удаляем папку zapret2"
     webui_remove >/dev/null 2>&1 || true
     rm -rf /opt/zapret2
 else
     echo "Папка zapret2 не существует."
 fi
 if [[ "$OSystem" == "entware" ]]; then
 	rm -fv /opt/etc/init.d/S90-zapret /opt/etc/ndm/netfilter.d/000-zapret.sh /opt/etc/init.d/S00fix
 fi
 read -re -p $'\033[33mУдалить функционал доступа в меню через браузер (web-ssh)? Enter - Да, 1 - нет\033[0m\n' ttyd_answer_del
 case "$ttyd_answer_del" in
     "1")
         echo "Пропущено"
     ;;
     *)
 		apk del ttyd 2>/dev/null || true
 		opkg remove ttyd 2>/dev/null || true
 		rm -f /usr/bin/ttyd
 		echo "Процесс удаления завершён"
     ;;
  esac
}

#Запрос желаемой версии zapret2
version_select() {
   while true; do
	read -re -p $'\033[0;32mВведите желаемую версию zapret2 (Enter для новейшей версии): \033[0m' VER
    # Если пустой ввод — берем значение по умолчанию
	if [ -z "$VER" ]; then
		lastest_release="https://api.github.com/repos/bol-van/zapret2/releases/latest"
	    # проверяем результаты по порядку
		echo -e "${yellow}Поиск последней версии...${plain}"
    	VER1=$(curl -sL $lastest_release | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
		if [ ${#VER1} -ge 2 ]; then
			VER="$VER1"
			echo -e "${green}Выбрано: $VER (метод: sed -E)${plain}"
		else
			VER2=$(curl -sL $lastest_release | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4 | sed 's/^v//')
			if [ ${#VER2} -ge 2 ]; then
				VER="$VER2"
				echo -e "${green}Выбрано: $VER (метод: grep+cut)${plain}"
			else
				VER3=$(curl -sL $lastest_release | grep '"tag_name":' | sed -r 's/.*"v([^"]+)".*/\1/')
				if [ ${#VER3} -ge 2 ]; then
					VER="$VER3"
					echo -e "${green}Выбрано: $VER (метод: sed -r)${plain}"
				else
					VER4=$(curl -sL $lastest_release | grep '"tag_name":' | awk -F'"' '{print $4}' | sed 's/^v//')
					if [ ${#VER4} -ge 2 ]; then
						VER="$VER4"
						echo -e "${green}Выбрано: $VER (метод: awk)${plain}"
					else
						echo -e "${yellow}Не удалось получить информацию о последней версии с GitHub. Будет использоваться версия $DEFAULT_VER.${plain}"
						VER="$DEFAULT_VER"
					fi
				fi
			fi
    	fi
    	break
	fi
    #Считаем длину
    LEN=${#VER}
    #Проверка длины и простая валидация формата (цифры и точки)
    if [ "$LEN" -gt 5 ]; then
        echo "Некорректный ввод. Максимальная длина — 5 символов. Попробуйте снова."
        continue
    elif ! echo "$VER" | grep -Eq '^[0-9]+(\.[0-9]+)*$'; then
        echo "Некорректный формат версии. Пример: 0.8.2"
        continue
    fi
    echo "Будет использоваться версия: $VER"
    break
done
}

#Скачивание, распаковка архива zapret2, очистка от ненуных бинарей
zapret_get() {
 if [[ "$OSystem" == "WRT" ]]; then
     tarfile="zapret2-v$VER-openwrt-embedded.tar.gz"
 else
     tarfile="zapret2-v$VER.tar.gz"
 fi
 curl -L "https://github.com/bol-van/zapret2/releases/download/v$VER/$tarfile" | tar -xz
 mv "zapret2-v$VER" zapret2
 sh /tmp/zapret2/install_bin.sh
 find /tmp/zapret2/binaries/* -maxdepth 0 -type d ! -name "$(basename "$(dirname "$(readlink /tmp/zapret2/nfq2/nfqws2)")")" -exec rm -rf {} +
 mv zapret2 /opt/zapret2
}

#Запуск установочных скриптов и перезагрузка
install_zapret_reboot() {
 sh -i /opt/zapret2/install_easy.sh
 "$ZAPRET2_INIT" restart
 if pidof nfqws2 >/dev/null; then
  check_access_list
  echo -e "\033[32mzapret2 перезапущен и полностью установлен\n\033[33mЕсли требуется меню (например не работают какие-то ресурсы) - введите скрипт ещё раз или просто напишите "z2r" в терминале. Саппорт: tg: zee4r\033[0m"
 else
  echo -e "${yellow}zapret2 полностью установлен, но не обнаружен после запуска в исполняемых задачах через pidof\nСаппорт: tg: zee4r${plain}"
 fi
}

#Для Entware Keenetic + merlin
entware_fixes() {
 if [ "$hardware" = "keenetic" ]; then
  curl -L -o /opt/zapret2/init.d/sysv/zapret2 https://raw.githubusercontent.com/IndeecFOX/zapret4rocket/z2r/Entware/zapret
  chmod +x /opt/zapret2/init.d/sysv/zapret2
  echo "Права выданы /opt/zapret2/init.d/sysv/zapret2"
  curl -L -o /opt/etc/ndm/netfilter.d/000-zapret.sh https://raw.githubusercontent.com/AloofLibra/zapret4rocket/z2r/Entware/000-zapret.sh
  chmod +x /opt/etc/ndm/netfilter.d/000-zapret.sh
  echo "Права выданы /opt/etc/ndm/netfilter.d/000-zapret.sh"
  curl -L -o /opt/etc/init.d/S00fix https://raw.githubusercontent.com/IndeecFOX/zapret4rocket/z2r/Entware/S00fix
  chmod +x /opt/etc/init.d/S00fix
  echo "Права выданы /opt/etc/init.d/S00fix"
  cp -a /opt/zapret2/init.d/custom.d.examples.linux/10-keenetic-udp-fix /opt/zapret2/init.d/sysv/custom.d/10-keenetic-udp-fix
  echo "10-keenetic-udp-fix скопирован"
 elif [ "$hardware" = "merlin" ]; then
  if sed -n '167p' /opt/zapret2/install_easy.sh | grep -q '^nfqws_opt_validat'; then
	sed -i '172s/return 1/return 0/' /opt/zapret2/install_easy.sh
  fi
	grep -qxF "$ZAPRET2_INIT restart-fw" /jffs/scripts/firewall-start || echo "$ZAPRET2_INIT restart-fw" >> /jffs/scripts/firewall-start
	chmod +x /jffs/scripts/firewall-start
 fi
 
 sh /opt/zapret2/install_bin.sh
 
 # #Раскомменчивание юзера под keenetic или merlin
 change_user
 #Патчинг на некоторых merlin /opt/zapret2/common/linux_fw.sh
 if command -v sysctl >/dev/null 2>&1; then
  echo "sysctl доступен. Патч linux_fw.sh не требуется"
 else
  echo "sysctl отсутствует. MerlinWRT? Патчим /opt/zapret2/common/linux_fw.sh"
  sed -i 's|sysctl -w net.netfilter.nf_conntrack_tcp_be_liberal=\$1|echo \$1 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal|' /opt/zapret2/common/linux_fw.sh
  sed -i 's|sysctl -q -w net.ipv4.conf.\$1.route_localnet="\$enable"|echo "\$enable" > /proc/sys/net/ipv4/conf/\$1/route_localnet|' /opt/zapret2/common/linux_iphelper.sh
 fi
 #sed для пропуска запроса на прочтение readme, т.к. система entware. Дабы скрипт отрабатывал далее на Enter
 sed -i 's/if \[ -n "\$1" \] || ask_yes_no N "do you want to continue";/if true;/' /opt/zapret2/common/installer.sh
 ln -fs "$ZAPRET2_INIT" /opt/etc/init.d/S90-zapret2
 echo "Добавлено в автозагрузку: /opt/etc/init.d/S90-zapret2 > $ZAPRET2_INIT"
}

#Запрос на установку 3x-ui или аналогов
get_panel() {
 read -re -p $'\033[33mУстановить ПО для туннелирования?\033[0m \033[32m(3xui, marzban, wg, 3proxy или Enter для пропуска): \033[0m' answer_panel
 # Удаляем лишние символы и пробелы, приводим к верхнему регистру
 clean_answer=$(echo "$answer_panel" | tr '[:lower:]' '[:upper:]')
 if [[ -z "$clean_answer" ]]; then
     echo "Пропуск установки ПО туннелирования."
 elif [[ "$clean_answer" == "3XUI" ]]; then
     echo "Установка 3x-ui панели."
     bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
 elif [[ "$clean_answer" == "WG" ]]; then
     echo "Установка WG (by angristan)"
     bash <(curl -Ls https://raw.githubusercontent.com/angristan/wireguard-install/refs/heads/master/wireguard-install.sh)
 elif [[ "$clean_answer" == "3PROXY" ]]; then
     echo "Установка 3proxy (by SnoyIatk). Доустановка с apt build-essential для сборки (debian/ubuntu)"
	 apt update && apt install build-essential
     bash <(curl -Ls https://raw.githubusercontent.com/SnoyIatk/3proxy/master/3proxyinstall.sh)
     curl -L -o /etc/3proxy/.proxyauth https://raw.githubusercontent.com/IndeecFOX/zapret4rocket/refs/heads/z2r/del.proxyauth
     curl -L -o /etc/3proxy/3proxy.cfg https://raw.githubusercontent.com/IndeecFOX/zapret4rocket/refs/heads/z2r/3proxy.cfg
 elif [[ "$clean_answer" == "MARZBAN" ]]; then
     echo "Установка Marzban"
     bash -c "$(curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban.sh)" @ install
 else
     echo "Пропуск установки ПО туннелирования."
 fi
}

#webssh ttyd
ttyd_webssh() {
 echo -e $'\033[33mВведите логин для доступа к zeefeer через браузер (0 - отказ от логина через web в z2r и переход на логин в ssh (может помочь в safari). Enter - пустой логин, \033[31mно не рекомендуется, панель может быть доступна из интернета!)\033[0m'
 read -re -p '' ttyd_login
 echo -e "${yellow}Если вы открыли пункт через браузер - вас выкинет. Используйте SSH для установки${plain}"
 
 ttyd_login_have="-c "${ttyd_login}": bash z2r"
 if [[ "$ttyd_login" == "0" ]]; then
	echo "Отключение логина в веб. Перевод с z2r на CLI логин."
    ttyd_login_have="login"
 fi
 
 if [[ "$OSystem" == "VPS" ]]; then
	echo -e "${yellow}Установка ttyd for VPS${plain}"
	systemctl stop ttyd 2>/dev/null || true
	curl -L -o /usr/bin/ttyd https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64
	chmod +x /usr/bin/ttyd
	
	cat > /etc/systemd/system/ttyd.service <<EOF
[Unit]
Description=ttyd WebSSH Service
After=network.target

[Service]
ExecStart=/usr/bin/ttyd -p 17681 -W -a ${ttyd_login_have}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

	systemctl daemon-reload
	systemctl enable ttyd
	systemctl start ttyd
 elif [[ "$OSystem" == "WRT" ]]; then
	echo -e "${yellow}Установка ttyd for WRT${plain}"
	/etc/init.d/ttyd stop 2>/dev/null || true
	opkg install ttyd 2>/dev/null || apk add ttyd 2>/dev/null
    uci set ttyd.@ttyd[0].interface=''
    uci set ttyd.@ttyd[0].command="-p 17681 -W -a ${ttyd_login_have}"
	uci commit ttyd
	/etc/init.d/ttyd enable
	/etc/init.d/ttyd start
 elif [[ "$OSystem" == "entware" ]]; then
	echo -e "${yellow}Установка ttyd for Entware${plain}"
	/opt/etc/init.d/S99ttyd stop 2>/dev/null || true
	opkg install ttyd 2>/dev/null || apk add ttyd 2>/dev/null
	
	cat > /opt/etc/init.d/S99ttyd <<EOF
#!/bin/sh

START=99

case "\$1" in
  start)
    echo "Starting ttyd..."
    ttyd -p 17681 -W -a ${ttyd_login_have} &
    ;;
  stop)
    echo "Stopping ttyd..."
    killall ttyd
    ;;
  restart)
    \$0 stop
    sleep 1
    \$0 start
    ;;
  *)
    echo "Usage: \$0 {start|stop|restart}"
    exit 1
    ;;
esac
EOF

  chmod +x /opt/etc/init.d/S99ttyd
  /opt/etc/init.d/S99ttyd start
  sleep 1
  if netstat -tuln | grep -q ':17681'; then
	echo -e "${green}Порт 17681 для службы ttyd слушается${plain}"
  else
	echo -e "${red}Порт 17681 для службы ttyd не прослушивается${plain}"
  fi
 fi

 if pidof ttyd >/dev/null; then
	echo -e "Проверка...${green}Служба ttyd запущена.${plain}"
 else
	echo -e "Проверка...${red}Служба ttyd не запущена! Если у вас Entware, то после перезагрузки роутера служба скорее всего заработает!${plain}"
 fi
 echo -e "${plain}Выполнение установки завершено. ${green}Доступ по ip вашего роутера/VPS в формате ip:17681, например 192.168.1.1:17681 или mydomain.com:17681 ${yellow}логин: ${ttyd_login} пароль - не испольузется.${plain} Был выполнен выход из скрипта для сохранения состояния."
}

#Меню, проверка состояний и вывод с чтением ответа
WEBUI_PORT="17682"
WEBUI_ROOT="/opt/zapret2/webui"
WEBUI_WWW="$WEBUI_ROOT/www"
WEBUI_CGI="$WEBUI_ROOT/cgi-bin"
WEBUI_RUNNER="$WEBUI_ROOT/run-webui.sh"
WEBUI_STATUS_CACHE="/opt/zapret2/extra_strats/cache/webui"
WEBUI_PATH="/opt/bin:/opt/sbin:/usr/sbin:/usr/bin:/sbin:/bin"

webui_repo_fetch() {
  local rel="$1"
  local dest="$2"
  local local_src="$SCRIPT_DIR/webui/$rel"
  local remote_url="https://raw.githubusercontent.com/AloofLibra/zapret4rocket/z2r/webui/$rel"

  mkdir -p "$(dirname "$dest")"
  if [ -f "$local_src" ]; then
    cp -f "$local_src" "$dest"
    return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$dest" "$remote_url"
    return $?
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$remote_url"
    return $?
  fi
  echo -e "${red}Нет curl или wget для загрузки web UI.${plain}"
  return 1
}

webui_has_busybox_httpd() {
  PATH="$WEBUI_PATH" command -v busybox >/dev/null 2>&1 || return 1
  if ! PATH="$WEBUI_PATH" busybox --list 2>/dev/null | grep -qx 'httpd'; then
    return 1
  fi
}

webui_server_type() {
  if PATH="$WEBUI_PATH" command -v uhttpd >/dev/null 2>&1; then
    echo "uhttpd"
    return
  fi
  if PATH="$WEBUI_PATH" command -v uhttpd_kn >/dev/null 2>&1; then
    echo "uhttpd_kn"
    return
  fi
  if PATH="$WEBUI_PATH" command -v httpd >/dev/null 2>&1; then
    echo "httpd"
    return
  fi
  if webui_has_busybox_httpd; then
    echo "busybox"
    return
  fi
  echo "none"
}

webui_ensure_server_binary() {
  if [ "$(webui_server_type)" != "none" ]; then
    return 0
  fi

  if command -v opkg >/dev/null 2>&1; then
    PATH="$WEBUI_PATH" opkg install uhttpd 2>/dev/null || true
    [ "$(webui_server_type)" != "none" ] || PATH="$WEBUI_PATH" opkg install uhttpd_kn 2>/dev/null || true
    [ "$(webui_server_type)" != "none" ] || PATH="$WEBUI_PATH" opkg install uhttpd-kn 2>/dev/null || true
    [ "$(webui_server_type)" != "none" ] || PATH="$WEBUI_PATH" opkg install busybox-httpd 2>/dev/null || true
    [ "$(webui_server_type)" != "none" ] || PATH="$WEBUI_PATH" opkg install busybox 2>/dev/null || true
  elif command -v apk >/dev/null 2>&1; then
    apk add uhttpd busybox 2>/dev/null || apk add busybox 2>/dev/null || true
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update 2>/dev/null || true
    apt-get install -y busybox-static 2>/dev/null || apt-get install -y busybox 2>/dev/null || true
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm busybox 2>/dev/null || true
  fi

  if [ "$(webui_server_type)" = "none" ]; then
    echo -e "${red}Не удалось найти или установить uhttpd/busybox httpd для web UI.${plain}"
    return 1
  fi
  return 0
}

webui_install_files() {
  mkdir -p "$WEBUI_ROOT" "$WEBUI_WWW" "$WEBUI_CGI" "$WEBUI_STATUS_CACHE"

  webui_repo_fetch "index.html" "$WEBUI_WWW/index.html" || return 1
  webui_repo_fetch "styles.css" "$WEBUI_WWW/styles.css" || return 1
  webui_repo_fetch "app.js" "$WEBUI_WWW/app.js" || return 1
  webui_repo_fetch "run-webui.sh" "$WEBUI_RUNNER" || return 1
  webui_repo_fetch "cgi-bin/_lib.sh" "$WEBUI_CGI/_lib.sh" || return 1
  webui_repo_fetch "cgi-bin/status.cgi" "$WEBUI_CGI/status.cgi" || return 1
  webui_repo_fetch "cgi-bin/locks.cgi" "$WEBUI_CGI/locks.cgi" || return 1
  webui_repo_fetch "cgi-bin/set-lock.cgi" "$WEBUI_CGI/set-lock.cgi" || return 1
  webui_repo_fetch "cgi-bin/clear-lock.cgi" "$WEBUI_CGI/clear-lock.cgi" || return 1
  webui_repo_fetch "cgi-bin/restart.cgi" "$WEBUI_CGI/restart.cgi" || return 1
  webui_repo_fetch "cgi-bin/check.cgi" "$WEBUI_CGI/check.cgi" || return 1
  webui_repo_fetch "cgi-bin/meta.cgi" "$WEBUI_CGI/meta.cgi" || return 1

  chmod +x "$WEBUI_RUNNER" "$WEBUI_CGI"/*.sh "$WEBUI_CGI"/*.cgi
  ln -sfn ../cgi-bin "$WEBUI_WWW/cgi-bin"
}

webui_install_service() {
  mkdir -p "$WEBUI_STATUS_CACHE"

  case "$OSystem" in
    "WRT")
      cat > /etc/init.d/z2r-webui <<'EOF'
#!/bin/sh /etc/rc.common
START=95
STOP=10
USE_PROCD=1
PATH=/opt/bin:/opt/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

start_service() {
  procd_open_instance
  procd_set_param command bash /opt/zapret2/webui/run-webui.sh run
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}

stop_service() {
  bash /opt/zapret2/webui/run-webui.sh stop >/dev/null 2>&1 || true
}
EOF
      chmod +x /etc/init.d/z2r-webui
      /etc/init.d/z2r-webui enable 2>/dev/null || true
      ;;
    "entware")
      cat > /opt/etc/init.d/S92z2r-webui <<'EOF'
#!/bin/sh
PATH=/opt/bin:/opt/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
case "$1" in
  start) bash /opt/zapret2/webui/run-webui.sh start ;;
  stop) bash /opt/zapret2/webui/run-webui.sh stop ;;
  restart) bash /opt/zapret2/webui/run-webui.sh restart ;;
  status) bash /opt/zapret2/webui/run-webui.sh status ;;
  *) echo "usage: $0 {start|stop|restart|status}"; exit 1 ;;
esac
EOF
      chmod +x /opt/etc/init.d/S92z2r-webui
      ;;
    *)
      if command -v systemctl >/dev/null 2>&1 && [ -d /etc/systemd/system ]; then
        cat > /etc/systemd/system/z2r-webui.service <<'EOF'
[Unit]
Description=z2r Web UI
After=network.target

[Service]
Type=simple
Environment=PATH=/opt/bin:/opt/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=bash /opt/zapret2/webui/run-webui.sh run
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable z2r-webui.service 2>/dev/null || true
      else
        cat > "$WEBUI_ROOT/run.sh" <<'EOF'
#!/bin/sh
PATH=/opt/bin:/opt/sbin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
bash /opt/zapret2/webui/run-webui.sh start
EOF
        chmod +x "$WEBUI_ROOT/run.sh"
      fi
      ;;
  esac
}

webui_start_service() {
  case "$OSystem" in
    "WRT")
      /etc/init.d/z2r-webui start
      ;;
    "entware")
      /opt/etc/init.d/S92z2r-webui start
      ;;
    *)
      if command -v systemctl >/dev/null 2>&1 && [ -f /etc/systemd/system/z2r-webui.service ]; then
        systemctl restart z2r-webui.service
      else
        bash "$WEBUI_RUNNER" restart >/dev/null 2>&1 || bash "$WEBUI_RUNNER" start >/dev/null 2>&1
      fi
      ;;
  esac
}

webui_stop_service() {
  case "$OSystem" in
    "WRT")
      [ -f /etc/init.d/z2r-webui ] && /etc/init.d/z2r-webui stop >/dev/null 2>&1 || true
      ;;
    "entware")
      [ -f /opt/etc/init.d/S92z2r-webui ] && /opt/etc/init.d/S92z2r-webui stop >/dev/null 2>&1 || true
      ;;
    *)
      if command -v systemctl >/dev/null 2>&1 && [ -f /etc/systemd/system/z2r-webui.service ]; then
        systemctl stop z2r-webui.service >/dev/null 2>&1 || true
      fi
      [ -x "$WEBUI_RUNNER" ] && "$WEBUI_RUNNER" stop >/dev/null 2>&1 || true
      ;;
  esac
}

webui_status_text() {
  if [ -x "$WEBUI_RUNNER" ]; then
    "$WEBUI_RUNNER" status 2>/dev/null || echo "stopped:none:${WEBUI_PORT}"
  else
    echo "stopped:none:${WEBUI_PORT}"
  fi
}

webui_print_urls() {
  if [ -x "$WEBUI_RUNNER" ]; then
    "$WEBUI_RUNNER" urls 2>/dev/null || true
  else
    echo "http://127.0.0.1:${WEBUI_PORT}"
  fi
}

webui_show_status() {
  local status_line
  status_line="$(webui_status_text)"
  echo -e "${yellow}Web UI: ${plain}${status_line}"
  echo -e "${yellow}URL примеры:${plain}"
  webui_print_urls
}

webui_install() {
  webui_ensure_server_binary || return 1
  webui_install_files || return 1
  webui_install_service || return 1
  webui_start_service || return 1
  echo -e "${green}Web UI установлен.${plain}"
  webui_show_status
}

webui_remove() {
  webui_stop_service
  case "$OSystem" in
    "WRT")
      [ -f /etc/init.d/z2r-webui ] && rm -f /etc/init.d/z2r-webui
      ;;
    "entware")
      [ -f /opt/etc/init.d/S92z2r-webui ] && rm -f /opt/etc/init.d/S92z2r-webui
      ;;
    *)
      if command -v systemctl >/dev/null 2>&1 && [ -f /etc/systemd/system/z2r-webui.service ]; then
        systemctl disable z2r-webui.service >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/z2r-webui.service
        systemctl daemon-reload >/dev/null 2>&1 || true
      fi
      ;;
  esac
  rm -rf "$WEBUI_ROOT"
  echo -e "${green}Web UI удалён.${plain}"
}

webui_submenu() {
  while true; do
    clear
    echo -e "${cyan}--- Web UI ---${plain}"
    echo -e "${yellow}Состояние: ${plain}$(webui_status_text)"
    echo ""
    submenu_item "1" "Установить/обновить Web UI"
    submenu_item "2" "Показать статус и URL"
    submenu_item "3" "Удалить Web UI"
    submenu_item "0" "Назад"
    echo ""
    read -re -p "Ваш выбор: " webui_answer
    case "$webui_answer" in
      "1")
        webui_install
        pause_enter
        ;;
      "2")
        webui_show_status
        pause_enter
        ;;
      "3")
        webui_remove
        pause_enter
        ;;
      "0"|"")
        return
        ;;
      *)
        echo -e "${yellow}Неверный ввод.${plain}"
        sleep 1
        ;;
    esac
  done
}

get_menu() {
    TITLE_MENU_LINE=""
    if [[ -s "$PREMIUM_TITLE_FILE" ]]; then
      TITLE_MENU_LINE="\n${pink}Титул:${plain} $(cat "$PREMIUM_TITLE_FILE")${yellow}\n"
    fi
    provider_init_once
    init_telemetry
    update_recommendations  
  while true; do
  	local strategies_status
    strategies_status=$(get_orchestra_locks_info)
	TITLE_MENU_LINE=""
    if [[ -s "$PREMIUM_TITLE_FILE" ]]; then
      TITLE_MENU_LINE="\n${pink}Титул:${plain} $(cat "$PREMIUM_TITLE_FILE")${yellow}\n"
    fi
    clear
    echo -e "${cyan}========================================${plain}"
    echo -e "${Fcyan}            zeefeer4rocket             ${plain}"
    echo -e "${Fgreen}         z2r - zapret2 Manager          ${plain}"
    echo -e "${cyan}========================================${plain}"
    echo ""
    
    echo -e '
'"${Fcyan}"'      +-----------------------------------------------------------------+
'"${Fyellow}"'           _____     ____ │  '"${Fgreen}"'1 MB / 10 GB'"${Fyellow}"'        '"${Fpink}"'⏳'"${Fyellow}"'  ETA: КТТС         │
'"${Fyellow}"'          /      \  |  o |│  [====>          ]                         │
'"${Fyellow}"'         |        |/ ___\|│     '"${Fpink}"'(_o_)'"${Fyellow}"' ---->  '"${Fcyan}"'z a t o r'"${Fyellow}"'  <---- '"${Fpink}"'(_o_)'"${Fyellow}"'    │
'"${Fyellow}"'         |_________/      │                                            │
'"${Fyellow}"'         |_|_| |_|_|      │  '"${Fgreen}"'speed: 0.0001 Mb/s'"${Fyellow}"'   stability: возможно  │
'"${Fcyan}"'      +-----------------------------------------------------------------+
'"${plain}"'

'"Город/провайдер: ${plain}${PROVIDER_MENU}${yellow}"'
'"${TITLE_MENU_LINE}"'
\033[32mВыберите необходимое действие:\033[33m
Enter (без цифр) - переустановка/обновление zapret2
'"${Fyellow}"'0.'"${yellow}"' Выход
'"${Fcyan}"'001.'"${yellow}"' CDN тест (test.sh)
'"${Fcyan}"'01.'"${yellow}"' Проверить доступность сервисов (Тест не точен)
'"${Fcyan}"'1.'"${yellow}"' Фиксация стратегии профиля/безразборного блока. Текущие: '"${plain}"'[ '"${strategies_status}"' ]'"${yellow}"' (fallback: '"${plain}"'['"$(fallback_strategy_text)"']'"${yellow}"')
'"${Fcyan}"'2.'"${yellow}"' Стоп/пере(запуск) zapret2 (сейчас: '"$(pidof nfqws2 >/dev/null && echo "${green}Запущен${yellow}" || echo "${red}Остановлен${yellow}")"' | оркестратор: '"${plain}"'['"$(orchestra_status_text)"']'"${yellow}"')
'"${Fcyan}"'3.'"${yellow}"' Запуск blockcheck2 и сохранение SUMMARY
'"${Fcyan}"'4.'"${yellow}"' Удалить zapret2
'"${Fcyan}"'5.'"${yellow}"' Обновить стратегии, сбросить листы подбора стратегий и исключений (есть бэкап)
'"${Fcyan}"'6.'"${yellow}"' Добавить домен в исключения
'"${Fcyan}"'7.'"${yellow}"' Открыть в редакторе config (Установит nano редактор ~250kb)
'"${Fcyan}"'8.'"${yellow}"' Преключатель скриптов bol-van обхода войсов DS,WA,TG на стандартные страты или возврат к скриптам. Сейчас: '"${plain}"'['"$(grep -Eq '^NFQWS_PORTS_UDP=.*443$' /opt/zapret2/config && echo "Скрипты" || (grep -Eq '443,1400,3478-3481,5349,50000-50099,19294-19344$' /opt/zapret2/config && echo "Классические стратегии" || echo "Незвестно"))"']'"${yellow}"'
'"${Fcyan}"'9.'"${yellow}"' Переключатель zapret2 на nftables/iptables (На всё жать Enter). Актуально для OpenWRT 21+. Может помочь с войсами. Сейчас: '"${plain}"'['"$(grep -q '^FWTYPE=iptables$' /opt/zapret2/config && echo "iptables" || (grep -q '^FWTYPE=nftables$' /opt/zapret2/config && echo "nftables" || echo "Неизвестно"))"']'"${yellow}"'
'"${Fcyan}"'10.'"${yellow}"' (Де)активировать обход UDP на 1026-65531 портах (BF6, Fifa и т.п.). Сейчас: '"${plain}"'['"$(grep -q '^NFQWS_PORTS_UDP=443' /opt/zapret2/config && echo "Выключен" || (grep -q '^NFQWS_PORTS_UDP=1026-65531,443' /opt/zapret2/config && echo "Включен" || echo "Неизвестно"))"']'"${yellow}"'
'"${Fcyan}"'11.'"${yellow}"' Управление аппаратным ускорением zapret2. Может увеличить скорость на роутере. Сейчас: '"${plain}"'['"$(grep '^FLOWOFFLOAD=' /opt/zapret2/config)"']'"${yellow}"'
'"${Fcyan}"'12.'"${yellow}"' Режим фильтра hostlist/autohostlist. Сейчас: '"${plain}"'['"$(hostlist_mode_text)"']'"${yellow}"'
'"${Fcyan}"'13.'"${yellow}"' Безразборный режим (fallback). Сейчас: '"${plain}"'['"$(fallback_mode_text)"']'"${yellow}"'
'"${Fcyan}"'14.'"${yellow}"' Активировать доступ в меню через браузер (~3мб места)
'"${Fcyan}"'15.'"${yellow}"' Провайдер
'"${Fcyan}"'16.'"${yellow}"' Сменить TLS blob (--blob=maxru). Сейчас: '"${plain}"'['"$(tls_blob_menu_text)"']'"${yellow}"'
'"${Fcyan}"'777.'"${yellow}"' Активировать zeefeer premium (Нажимать только Valery ProD, avg97, Xoz, GeGunT, blagodarenya, mikhyan, Xoz, andric62, Whoze, Necronicle, Andrei_5288515371, Nomand, Dina_turat, Nergalss, Александру, АлександруП, vecheromholodno, ЕвгениюГ, Dyadyabo, skuwakin, izzzgoy, Grigaraz, Reconnaissance, comandante1928, umad, rudnev2028, rutakote, railwayfx, vtokarev1604, Grigaraz, a40letbezurojaya и subzeero452 и остальным поддержавшим проект. Но если очень хочется - можно нажать и другим)\033[0m'
    if [[ -f "$PREMIUM_FLAG" ]]; then
      echo -e "${red}999. Секретный пункт. Нажимать на свой страх и риск${plain}"
    fi
  read -re -p "" answer_menu
    case "$answer_menu" in
  "")
    echo -e "${yellow}Вы уверены, что хотите переустановить/обновить zapret2?${plain}"
    echo -e "${yellow}5 - Да, Enter/0 - Нет (вернуться в меню)${plain}"
    read -r ans
    if [ "$ans" = "5" ] || [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
      # подтверждение: выходим из get_menu и уходим в “тело” (переустановка/обновление)
      return 0
    else
      # отмена: остаёмся в меню, цикл while true продолжится
      :
    fi
    ;;

  "0")
    echo "Выход выполнен"
    exit 0
    ;;

  "01")
    check_access_list
    pause_enter
    ;;

  "001")
    run_cdn_test
    pause_enter
    ;;

  "1")
    strategies_submenu
    ;;

  "2")
    if pidof nfqws2 >/dev/null; then
      ensure_nfqws2_stopped
      orchestra_stop
      echo -e "${green}Выполнена команда остановки zapret2${plain}"
    else
      "$ZAPRET2_INIT" restart
      orchestra_start
      echo -e "${green}Выполнена команда перезапуска zapret2${plain}"
    fi
    pause_enter
    ;;

  "3")
    blockcheck2_run_summary
    pause_enter
    ;;

  "4")
    remove_zapret
    echo -e "${yellow}zapret2 удалён${plain}"
    pause_enter
    ;;

  "5")
    orchestra_update_from_repo
    mkdir -p /opt/zapret2/extra_strats/cache/orchestra
    chmod 777 /opt/zapret2/extra_strats/cache/orchestra 2>/dev/null || true
    if [ -x "$ORCH_SCRIPT" ]; then
      if ps w | grep -F "$ORCH_SCRIPT run" | grep -v grep >/dev/null 2>&1; then
        orchestra_stop
        orchestra_start
      fi
    fi
    menu_action_update_config_reset
    pause_enter
    ;;

  "6")
    read -re -p "Введите домен, который добавить в исключения (например, mydomain.com): " user_domain
    if [ -n "$user_domain" ]; then
      exclude_file="/opt/zapret2/lists/exclude-domains.txt"
      mkdir -p /opt/zapret2/lists
      if ! grep -Fxq "$user_domain" "$exclude_file" 2>/dev/null; then
        echo "$user_domain" >> "$exclude_file"
      fi
      echo -e "Домен ${yellow}$user_domain${plain} добавлен в исключения (exclude-domains.txt)."
    else
      echo "Ввод пустой, ничего не добавлено"
    fi
    pause_enter
    ;;

  "7")
    if [[ "$OSystem" == "VPS" ]]; then
      apt install nano
    else
      opkg remove nano 2>/dev/null || apk del nano 2>/dev/null
      opkg install nano-full 2>/dev/null || apk add nano-full 2>/dev/null
    fi
    nano /opt/zapret2/config
    # после выхода из nano
    ;;

  "8")
    echo -e "${yellow}Временно не работает${plain}"
    # menu_action_toggle_bolvan_ports
    pause_enter
    ;;

  "9")
    menu_action_toggle_fwtype
    pause_enter
    ;;

  "10")
    echo -e "${yellow}Временно не работает${plain}"
    # pause_entermenu_action_toggle_udp_range
    
    pause_enter
    ;;

  "11")
    flowoffload_submenu   # сабменю само в цикле и выходит через return
    ;;

  "12")
    toggle_hostlist_mode
    if pidof nfqws2 >/dev/null; then
      "$ZAPRET2_INIT" restart
      orchestra_start
      echo -e "${green}zapret2 перезапущен для применения режима${plain}"
    fi
    pause_enter
    ;;

  "13")
    toggle_fallback_mode
    if pidof nfqws2 >/dev/null; then
      "$ZAPRET2_INIT" restart
      orchestra_start
      echo -e "${green}zapret2 перезапущен для применения режима${plain}"
    fi
    pause_enter
    ;;

  "14")
    webui_submenu
    ;;

  "15")
    provider_submenu      # сабменю само в цикле и выходит через return
    ;;

  "16")
    menu_action_set_tls_blob
    ;;


  "777")
   echo -e "${green}Специальный zeefeer premium для Valery ProD, avg97, Xoz, GeGunT, blagodarenya, mikhyan, andric62, Whoze, Necronicle, Andrei_5288515371, Nomand, Dina_turat, Nergalss, Александра, АлександраП, vecheromholodno, ЕвгенияГ, Dyadyabo, skuwakin, izzzgoy, Grigaraz, Reconnaissance, comandante1928, rudnev2028, umad, rutakote, railwayfx, vtokarev1604, Grigaraz, a40letbezurojaya и subzeero452 активирован. Наверное. Так же благодарю поддержавших проект hey_enote, VssA, vladdrazz, Alexey_Tob, Bor1sBr1tva, Azamatstd, iMLT, Qu3Bee, SasayKudasay1, alexander_novikoff, MarsKVV, porfenon123, bobrishe_dazzle, kotov38, Levonkas, DA00001, trin4ik, geodomin, I_ZNA_I, CMyTHblN PacKoJlbHNK и анонимов${plain}"
   zefeer_premium_777
   exit_to_menu
   ;;
  "999")
    zefeer_space_999
    pause_enter
    ;;

  *)
    echo -e "${yellow}Неверный ввод.${plain}"
    sleep 1
    ;;
esac

  done
}

#___Само выполнение скрипта начинается тут____


detect_os
set_zapret2_init

#Инфа о времени обновления скрпта
commit_date=$(curl -s --max-time 30 "https://api.github.com/repos/IndeecFOX/zapret4rocket/commits?path=z4r.sh&per_page=1" | grep '"date"' | head -n1 | cut -d'"' -f4)
if [[ -z "$commit_date" ]]; then
    echo -e "${red}Не был получен доступ к api.github.com (таймаут 30 сек). Возможны проблемы при установке.${plain}"
	if [ "$hardware" = "keenetic" ]; then
		echo "Добавляем ip с от DNS 1.1.1.1 к api.github.com и пытаемся снова"
		ndmc -c "ip host api.github.com $(nslookup api.github.com 1.1.1.1 | sed -n 's/^Address [0-9]*: \([0-9.]*\).*/\1/p' | tail -n1)"
		echo -e "${yellow}zeefeer обновлен (UTC +0): $(curl -s --max-time 10 "https://api.github.com/repos/IndeecFOX/zapret4rocket/commits?path=z4r.sh&per_page=1" | grep '"date"' | head -n1 | cut -d'"' -f4) ${plain}"
	fi
else
    echo -e "${yellow}zeefeer обновлен (UTC +0): $commit_date ${plain}"
fi

#Проверка доступности raw.githubusercontent.com
if [[ -z "$(curl -s --max-time 10 "https://raw.githubusercontent.com/test")" ]]; then
    echo -e "${red}Не был получен доступ к raw.githubusercontent.com (таймаут 10 сек). Возможны проблемы при установке.${plain}"
	if [ "$hardware" = "keenetic" ]; then
		echo "Добавляем ip с от DNS 1.1.1.1 к raw.githubusercontent.com и пытаемся снова"
		raw_ip="$(nslookup raw.githubusercontent.com 1.1.1.1 | awk '
			/^Name: / {found=1; next}
			found && /^Address [0-9]+: / {print $3}
		' | tail -n1)"
		if [ -n "$raw_ip" ]; then
			ndmc -c "ip host raw.githubusercontent.com $raw_ip"
		else
			echo "Не удалось получить IP для raw.githubusercontent.com (nslookup пуст/ошибка). Пропуск ip host."
		fi
	fi
fi

#Выполнение общего для всех ОС кода с ответвлениями под ОС
#Запрос на установку 3x-ui или аналогов для VPS
if [[ "$OSystem" == "VPS" ]] && [ ! $1 ]; then
 get_panel
fi

#Меню и быстрый запуск подбора стратегии
 if [ -d /opt/zapret2/extra_strats ] && [ -f "/opt/zapret2/config" ]; then
	if [ $1 ]; then
		Strats_Tryer $1
	fi
    get_menu
 fi
 
#entware keenetic and merlin preinstal env.
if [ "$hardware" = "keenetic" ]; then
 opkg install coreutils-sort grep gzip ipset iptables xtables-addons_legacy 2>/dev/null || apk add coreutils-sort grep gzip ipset iptables xtables-addons_legacy 2>/dev/null
 opkg install kmod_ndms 2>/dev/null || apk add kmod_ndms 2>/dev/null || echo -e "\033[31mНе удалось установить kmod_ndms. Если у вас не keenetic - игнорируйте.\033[0m"
elif [ "$hardware" = "merlin" ]; then
 opkg install coreutils-sort grep gzip ipset iptables xtables-addons_legacy 2>/dev/null || apk add coreutils-sort grep gzip ipset iptables xtables-addons_legacy 2>/dev/null
fi

#Проверка наличия каталога opt и его создание при необходиомости (для некоторых роутеров), переход в tmp
mkdir -p /opt
cd /tmp

#Запрос на резервирование стратегий, если есть что резервировать
backup_strats

#Удаление старого запрета, если есть
remove_zapret

#Запрос желаемой версии zapret2
echo -e "${yellow}Конфиг обновлен (UTC +0): $(curl -s "https://api.github.com/repos/IndeecFOX/zapret4rocket/commits?path=config.default&per_page=1" | grep '"date"' | head -n1 | cut -d'"' -f4) ${plain}"
version_select

#Запрос на установку web-ssh
read -re -p $'\033[33mАктивировать доступ в меню через браузер (~3мб места)? 1 - Да, Enter - нет\033[0m\n' ttyd_answer
case "$ttyd_answer" in
	"1")
		webui_install
	;;
	*)
		echo "Пропуск (пере)установки web-терминала"
	;;
esac 
 
#Скачивание, распаковка архива zapret2 и его удаление
zapret_get

#Создаём папки и забираем файлы папок lists, fake, extra_strats, копируем конфиг, скрипты для войсов DS, WA, TG
get_repo
if [ ! -s "$ORCH_SCRIPT" ] || [ ! -s "$ORCH_LUA_LOCKED" ]; then
  echo "Повторная попытка загрузки orchestrator.sh и locked.lua..."
  if orchestra_update_from_repo; then
    echo -e "${green}Повторная загрузка orchestrator.sh и locked.lua успешна.${plain}"
  else
    echo -e "${red}Повторная загрузка orchestrator.sh и locked.lua не удалась.${plain}"
  fi
fi

#Для Keenetic и merlin
if [[ "$OSystem" == "entware" ]]; then
 entware_fixes
fi

#Для x-wrt
if [[ "$release" == "x-wrt" ]]; then
	sed -i 's/kmod-nft-nat kmod-nft-offload/kmod-nft-nat/' /opt/zapret2/common/installer.sh
fi

#Запуск установочных скриптов и перезагрузка
install_zapret_reboot
