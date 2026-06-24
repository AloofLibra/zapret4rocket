backup_strats() {
  # Бэкап папки стратегий
  if [ -d /opt/zapret2/extra_strats ]; then
    echo -e "${yellow}Сделать бэкап /opt/zapret2/extra_strats ?${plain}"
    echo -e "${yellow}5 - Да, Enter - Нет, 0 - отмена${plain}"
    read -r ans
    if [ "$ans" = "0" ]; then
        get_menu # сигнал “отмена/в меню”
    fi
    if [ "$ans" = "5" ] || [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
      touch /opt/zapret2/extra_strats/TCP_Custom.txt 2>/dev/null || true
      rm -rf /opt/extra_strats 2>/dev/null || true
      cp -rf /opt/zapret2/extra_strats /opt/ || true
      if [ -f /opt/zapret2/extra_strats/TCP_Custom.txt ] && [ ! -f /opt/extra_strats/TCP_Custom.txt ]; then
        cp -f /opt/zapret2/extra_strats/TCP_Custom.txt /opt/extra_strats/TCP_Custom.txt 2>/dev/null || true
      fi
      echo -e "${green}Бэкап extra_strats сохранён в /opt/extra_strats${plain}"
    fi
  fi

  # Бэкап листа исключений
  if [ -f /opt/zapret2/lists/netrogat.txt ]; then
    echo -e "${yellow}Сделать бэкап /opt/zapret2/lists/netrogat.txt ?${plain}"
    echo -e "${yellow}5 - Да, Enter - Нет, 0 - отмена и выход в меню${plain}"
    read -r ans2
    if [ "$ans2" = "0" ]; then
      get_menu
    fi
    if [ "$ans2" = "5" ] || [ "$ans2" = "y" ] || [ "$ans2" = "Y" ]; then
      cp -f /opt/zapret2/lists/netrogat.txt /opt/netrogat.txt || true
      echo -e "${green}Бэкап netrogat.txt сохранён в /opt/netrogat.txt${plain}"
    fi
  fi

  return 0
}


menu_action_update_config_reset() {
  echo -e "${yellow}Конфиг обновлен (UTC +0): $(curl -s "https://api.github.com/repos/IndeecFOX/zapret4rocket/commits?path=config.default&per_page=1" | grep '"date"' | head -n1 | cut -d'"' -f4) ${plain}"

  backup_strats

  "$ZAPRET2_INIT" stop

  rm -rf /opt/zapret2/lists /opt/zapret2/extra_strats

  rm -f /opt/zapret2/files/fake/http_fake_MS.bin \
        /opt/zapret2/files/fake/quic_{1..7}.bin \
        /opt/zapret2/files/fake/syn_packet.bin \
        /opt/zapret2/files/fake/tls_clienthello_{1..18}.bin \
        /opt/zapret2/files/fake/tls_clienthello_2n.bin \
        /opt/zapret2/files/fake/tls_clienthello_6a.bin \
        /opt/zapret2/files/fake/tls_clienthello_4pda_to.bin

  get_repo

  if [ ! -f /opt/zapret2/files/fake/custom_tls.bin ]; then
    mkdir -p /opt/zapret2/files/fake
    if ! z2r_download_project_file /opt/zapret2/files/fake/custom_tls.bin "fake/custom_tls.bin"; then
      echo -e "${yellow}Не удалось скачать custom_tls.bin: нет curl/wget.${plain}"
    fi
  fi

  # Раскомменчивание юзера под keenetic или merlin
  change_user
  # На Keenetic автоматически подставляем WAN интерфейс в свежий шаблон конфига.
  if [ "$hardware" = "keenetic" ]; then
    config_keenetic_set_wan_iface /opt/zapret2/config.default
  fi

  cp -f /opt/zapret2/config.default /opt/zapret2/config
  # После копирования синхронизируем рабочий конфиг, чтобы reset не терял IFACE_WAN.
  if [ "$hardware" = "keenetic" ]; then
    config_keenetic_set_wan_iface /opt/zapret2/config
  fi

  "$ZAPRET2_INIT" start

  # ВАЖНО: check_access_list — это по сути интерактивный тест (он сам печатает и может ждать Enter),
  # поэтому лучше вызывать его из get_menu отдельным пунктом ("01"), а не тут.
  # check_access_list

  echo -e "${green}Config файл обновлён. Листы подбора стратегий и исключений сброшены в дефолт, если не просили сохранить. Фейк файлы обновлены.${plain}"
  return 0
}

menu_action_toggle_bolvan_ports() {
  local cfg="/opt/zapret2/config"
  local voice_ports_csv="50000-50099,1400,3478-3481,5349,19294-19344"
  local voice_port current_ports new_ports p
  local init_dir custom_dir

  if [ ! -f "$cfg" ]; then
    echo -e "${red}Не найден $cfg.${plain}"
    return 1
  fi

  init_dir="$(dirname "$ZAPRET2_INIT")"
  custom_dir="$init_dir/custom.d"
  current_ports="$(sed -n 's/^NFQWS2_PORTS_UDP=//p' "$cfg" | head -n1)"

  if ! printf "%s" "$current_ports" | grep -Eq '(^|,)50000-50099(,|$)'; then
    if [ -n "$current_ports" ]; then
      new_ports="$current_ports,$voice_ports_csv"
    else
      new_ports="443,$voice_ports_csv"
    fi
    sed -i "s/^NFQWS2_PORTS_UDP=.*/NFQWS2_PORTS_UDP=$new_ports/" "$cfg"
    sed -i '/#Стратегии для голосовой связи/,/^[[:space:]]*--new[[:space:]]*$/ s/^--skip[[:space:]]\+--filter-udp=/--filter-udp=/' "$cfg"

    rm -f "$custom_dir/50-discord-media" \
          "$custom_dir/50-stun4all"

    echo -e "${green}Включён 6 блок конфига для голосовой связи. Скрипты bol-van отключены.${plain}"

  elif printf "%s" "$current_ports" | grep -Eq '(^|,)50000-50099(,|$)'; then
    new_ports=",$current_ports,"
    for voice_port in 50000-50099 1400 3478-3481 5349 19294-19344; do
      new_ports="$(printf "%s" "$new_ports" | sed "s/,$voice_port,/,/g")"
    done
    new_ports="$(printf "%s" "$new_ports" | sed 's/,,*/,/g; s/^,//; s/,$//')"
    [ -n "$new_ports" ] || new_ports="443"
    sed -i "s/^NFQWS2_PORTS_UDP=.*/NFQWS2_PORTS_UDP=$new_ports/" "$cfg"
    sed -i '/#Стратегии для голосовой связи/,/^[[:space:]]*--new[[:space:]]*$/ s/^--filter-udp=/--skip --filter-udp=/' "$cfg"

    z2r_install_bolvan_voice_scripts "$custom_dir" || return 1

    echo -e "${green}Включены скрипты bol-van 50-discord-media/50-stun4all. 6 блок конфига отключён через --skip.${plain}"
  else
    echo -e "${yellow}Неизвестное состояние строки NFQWS2_PORTS_UDP. Проверь конфиг вручную.${plain}"
    return 0
  fi

  "$ZAPRET2_INIT" restart
  echo -e "${green}Выполнение переключений завершено.${plain}"
  return 0
}

menu_action_toggle_fwtype() {
  local cfg
  cfg="$(get_config_file)"
  if [ "$(config_get_var "$cfg" FWTYPE)" = "iptables" ]; then
    config_set_var "$cfg" FWTYPE nftables
    /opt/zapret2/install_prereq.sh
    "$ZAPRET2_INIT" restart
    echo -e "${green}Zapret moode: nftables.${plain}"

  elif [ "$(config_get_var "$cfg" FWTYPE)" = "nftables" ]; then
    config_set_var "$cfg" FWTYPE iptables
    /opt/zapret2/install_prereq.sh
    "$ZAPRET2_INIT" restart
    echo -e "${green}Zapret moode: iptables.${plain}"

  else
    echo -e "${yellow}Неизвестное состояние строки FWTYPE. Проверь конфиг вручную.${plain}"
  fi

  return 0
}

menu_action_toggle_udp_range() {
  local cfg current_ports new_ports
  cfg="$(get_config_file)"
  current_ports="$(config_get_var "$cfg" NFQWS2_PORTS_UDP)"

  if ! printf "%s" "$current_ports" | grep -Eq '(^|,)1026-65531(,|$)'; then
    if [ -n "$current_ports" ]; then
      new_ports="1026-65531,$current_ports"
    else
      new_ports="1026-65531,443"
    fi
    config_set_var "$cfg" NFQWS2_PORTS_UDP "$new_ports"
    sed -i '/#Стратегии для игрового UDP/,/^[[:space:]]*--new[[:space:]]*$/ s/^--skip[[:space:]]\+--filter-udp=1026/--filter-udp=1026/' "$cfg"
    echo -e "${green}Стратегия UDP обхода активирована. Выделены порты 1026-65531${plain}"

  elif printf "%s" "$current_ports" | grep -Eq '(^|,)1026-65531(,|$)'; then
    new_ports=",$current_ports,"
    new_ports="$(printf "%s" "$new_ports" | sed 's/,1026-65531,/,/g; s/,,*/,/g; s/^,//; s/,$//')"
    [ -n "$new_ports" ] || new_ports="443"
    config_set_var "$cfg" NFQWS2_PORTS_UDP "$new_ports"
    sed -i '/#Стратегии для игрового UDP/,/^[[:space:]]*--new[[:space:]]*$/ s/^--filter-udp=1026/--skip --filter-udp=1026/' "$cfg"
    echo -e "${green}Стратегия UDP обхода ДЕактивирована. Выделенные порты 1026-65531 убраны${plain}"

  else
    echo -e "${yellow}Неизвестное состояние строки NFQWS2_PORTS_UDP. Проверь конфиг вручную.${plain}"
    return 0
  fi

  "$ZAPRET2_INIT" restart
  echo -e "${green}Выполнение переключений завершено.${plain}"
  return 0
}

menu_action_toggle_reasm_disable() {
  local cfg="/opt/zapret2/config"
  local state

  if [ ! -f "$cfg" ]; then
    echo -e "${red}Файл конфигурации не найден: $cfg${plain}"
    echo -e "${yellow}Пожалуйста, убедитесь, что zapret2 установлен и настроен.${plain}"
    return 1
  fi

  state="$(config_mode_text reasm_disable "$cfg")"

  if [ "$state" = "включено" ]; then
    sed -i '/^[[:space:]]*--reasm-disable[[:space:]]*$/d' "$cfg" || return 1
    echo -e "Параметр --reasm-disable: ${green}деактивирован${plain}."
  else
    if ! grep -q '^NFQWS2_OPT="' "$cfg"; then
      echo -e "${red}Не найден блок NFQWS2_OPT в $cfg.${plain}"
      return 1
    fi
    sed -i '/^NFQWS2_OPT="/a --reasm-disable' "$cfg" || return 1
    echo -e "Параметр --reasm-disable: ${red}активирован${plain}."
  fi

  return 0
}

menu_action_set_tls_blob() {
  local cfg="/opt/zapret2/config"
  local fake_dir="/opt/zapret2/files/fake"
  local prefix="--blob=maxru:@/opt/zapret2/files/fake/"
  local sed_ereg="-E"
  local current_blob=""
  local current_mode=""
  local has_tls_maxru=0
  local has_tls_default=0
  local blobs=()
  local i=0
  local choice=""
  local selected_blob=""

  if [ ! -f "$cfg" ]; then
    cfg="/opt/zapret2/config.default"
  fi
  if [ ! -f "$cfg" ]; then
    echo -e "${red}Не найден config/config.default.${plain}"
    pause_enter
    return 1
  fi

  if [ ! -d "$fake_dir" ]; then
    echo -e "${red}Каталог $fake_dir не найден.${plain}"
    pause_enter
    return 1
  fi

  if ! printf "x" | sed -E 's/x/x/' >/dev/null 2>&1; then
    sed_ereg="-r"
  fi

  if sort -z </dev/null >/dev/null 2>&1; then
    while IFS= read -r -d '' f; do
      blobs+=("$(basename "$f")")
    done < <(find "$fake_dir" -maxdepth 1 -type f -name '*.bin' -print0 | sort -z)
  else
    while IFS= read -r f; do
      blobs+=("$(basename "$f")")
    done < <(find "$fake_dir" -maxdepth 1 -type f -name '*.bin' | sort)
  fi

  if [ "${#blobs[@]}" -eq 0 ]; then
    echo -e "${red}В $fake_dir нет .bin файлов.${plain}"
    pause_enter
    return 1
  fi

  current_blob="$(sed -n -E 's#.*--blob=maxru:@/opt/zapret2/files/fake/([^[:space:]]+).*#\1#p' "$cfg" | head -n1)"
  [ -z "$current_blob" ] && current_blob="не найден в конфиге"
  if awk '
      /--lua-desync=/ && /blob=maxru/ && $0 !~ /strategy=26/ {found=1}
      END {exit(found?0:1)}
    ' "$cfg"; then
    has_tls_maxru=1
  fi
  if awk '
      /--lua-desync=/ && /blob=fake_default_tls/ && $0 !~ /strategy=26/ {found=1}
      END {exit(found?0:1)}
    ' "$cfg"; then
    has_tls_default=1
  fi

  if [ "$has_tls_maxru" -eq 1 ] && [ "$has_tls_default" -eq 0 ]; then
    current_mode="maxru (внешний файл)"
  elif [ "$has_tls_default" -eq 1 ] && [ "$has_tls_maxru" -eq 0 ]; then
    current_mode="fake_default_tls (встроенный)"
  elif [ "$has_tls_default" -eq 1 ] && [ "$has_tls_maxru" -eq 1 ]; then
    current_mode="mixed"
  else
    current_mode="не определён"
  fi

  echo -e "${yellow}Текущий режим blob: ${plain}${current_mode}"
  echo -e "${yellow}Текущий файл для maxru: ${plain}${current_blob}"
  echo -e "${yellow}Выберите blob для TLS-стратегий:${plain}"
  echo "1. fake_default_tls (встроенный)"
  i=1
  for b in "${blobs[@]}"; do
    i=$((i+1))
    echo "$i. $b"
  done
  echo "0. Отмена"
  read -re -p "Ваш выбор: " choice

  if [ "$choice" = "0" ] || [ -z "$choice" ]; then
    echo "Отменено."
    pause_enter
    return 0
  fi
  if ! printf "%s" "$choice" | grep -Eq '^[0-9]+$'; then
    echo -e "${red}Некорректный выбор.${plain}"
    pause_enter
    return 1
  fi
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "$(( ${#blobs[@]} + 1 ))" ]; then
    echo -e "${red}Номер вне диапазона.${plain}"
    pause_enter
    return 1
  fi

  if [ "$choice" -eq 1 ]; then
    if [ "$sed_ereg" = "-E" ]; then
      sed -i -E '/--lua-desync=/ { /strategy=26/! s#(--lua-desync=[^[:space:]]*blob=)maxru#\1fake_default_tls#g; }' "$cfg"
    else
      sed -i -r '/--lua-desync=/ { /strategy=26/! s#(--lua-desync=[^[:space:]]*blob=)maxru#\1fake_default_tls#g; }' "$cfg"
    fi
    echo -e "${green}В TLS-стратегиях выбран встроенный blob: fake_default_tls${plain}"
    echo -e "${yellow}Строка --blob=maxru:@... сохранена без изменений для обратного переключения.${plain}"
    pause_enter
    return 0
  fi

  selected_blob="${blobs[$((choice-2))]}"

  if ! grep -q -- "--blob=maxru:@/opt/zapret2/files/fake/" "$cfg"; then
    echo -e "${red}Строка --blob=maxru:@/opt/zapret2/files/fake/... не найдена в $cfg${plain}"
    pause_enter
    return 1
  fi

  if [ "$sed_ereg" = "-E" ]; then
    sed -i -E '/--lua-desync=/ { /strategy=26/! s#(--lua-desync=[^[:space:]]*blob=)fake_default_tls#\1maxru#g; }' "$cfg"
    sed -i -E "s#(${prefix})[^[:space:]]+#\\1${selected_blob}#g" "$cfg"
  else
    sed -i -r '/--lua-desync=/ { /strategy=26/! s#(--lua-desync=[^[:space:]]*blob=)fake_default_tls#\1maxru#g; }' "$cfg"
    sed -i -r "s#(${prefix})[^[:space:]]+#\\1${selected_blob}#g" "$cfg"
  fi
  echo -e "${green}Обновлено: --blob=maxru -> ${selected_blob}${plain}"
  echo -e "${yellow}Перезапустите zapret2 (пункт 2 меню), чтобы применить изменения.${plain}"
  pause_enter
  return 0
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

toggle_fallback_mode() {
  for cfg in /opt/zapret2/config /opt/zapret2/config.default; do
    [ -f "$cfg" ] || continue
    if { sed -n '/#Z2R_FALLBACK_BEGIN/,/#Z2R_FALLBACK_END/p' "$cfg"; sed -n '/#Z2R_FALLBACK_HTTP_BEGIN/,/#Z2R_FALLBACK_HTTP_END/p' "$cfg"; } | grep -q '^[[:space:]]*--skip[[:space:]]'; then
      sed -i '/#Z2R_FALLBACK_BEGIN/,/#Z2R_FALLBACK_END/ s/^[[:space:]]*--skip[[:space:]]\+//' "$cfg"
      sed -i '/#Z2R_FALLBACK_HTTP_BEGIN/,/#Z2R_FALLBACK_HTTP_END/ s/^[[:space:]]*--skip[[:space:]]\+//' "$cfg"
    else
      sed -i '/#Z2R_FALLBACK_BEGIN/,/#Z2R_FALLBACK_END/ s/^[[:space:]]*--filter-tcp=443 --filter-l7=tls/--skip --filter-tcp=443 --filter-l7=tls/' "$cfg"
      sed -i '/#Z2R_FALLBACK_BEGIN/,/#Z2R_FALLBACK_END/ s/^[[:space:]]*--filter-tcp=443$/--skip --filter-tcp=443/' "$cfg"
      sed -i '/#Z2R_FALLBACK_HTTP_BEGIN/,/#Z2R_FALLBACK_HTTP_END/ s/^[[:space:]]*--filter-tcp=80 --filter-l7=http/--skip --filter-tcp=80 --filter-l7=http/' "$cfg"
    fi
  done
}

toggle_rst_guard_mode() {
  local cfg="/opt/zapret2/config"
  local enable=1
  local key

  if type rst_guard_lua_update_from_repo >/dev/null 2>&1 && [ ! -s /opt/zapret2/lua/rst-guard.lua ]; then
    rst_guard_lua_update_from_repo || true
  fi

  if [ ! -f "$cfg" ]; then
    echo -e "${red}Не найден $cfg.${plain}"
    return 1
  fi

  if grep -q -- '--lua-desync=rst_guard_locked:key=' "$cfg"; then
    enable=0
  fi

  if [ "$enable" -eq 1 ]; then
    sed -i '/#Z2R_FALLBACK_BEGIN/,/#Z2R_FALLBACK_END/ s/^--filter-tcp=443 --filter-l7=tls$/--filter-tcp=443/' "$cfg"
    sed -i '/#Z2R_FALLBACK_BEGIN/,/#Z2R_FALLBACK_END/ s/^--skip --filter-tcp=443 --filter-l7=tls$/--skip --filter-tcp=443/' "$cfg"
    sed -i '/#Z2R_FALLBACK_BEGIN/,/#Z2R_FALLBACK_END/ s/^--payload=tls_client_hello,http_req,http_reply,unknown,tls_server_hello$/--payload=tls_client_hello,http_req,http_reply,unknown,tls_server_hello,empty/' "$cfg"
    for key in 1 2 3 4 8 9; do
      sed -i "s/--lua-desync=circular_locked:key=$key/--lua-desync=rst_guard_locked:key=$key/g" "$cfg"
    done
  else
    sed -i '/#Z2R_FALLBACK_BEGIN/,/#Z2R_FALLBACK_END/ s/^--filter-tcp=443$/--filter-tcp=443 --filter-l7=tls/' "$cfg"
    sed -i '/#Z2R_FALLBACK_BEGIN/,/#Z2R_FALLBACK_END/ s/^--skip --filter-tcp=443$/--skip --filter-tcp=443 --filter-l7=tls/' "$cfg"
    sed -i '/#Z2R_FALLBACK_BEGIN/,/#Z2R_FALLBACK_END/ s/^--payload=tls_client_hello,http_req,http_reply,unknown,tls_server_hello,empty$/--payload=tls_client_hello,http_req,http_reply,unknown,tls_server_hello/' "$cfg"
    for key in 1 2 3 4 8 9; do
      sed -i "s/--lua-desync=rst_guard_locked:key=$key/--lua-desync=circular_locked:key=$key/g" "$cfg"
    done
  fi
}
