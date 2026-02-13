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
      rm -rf /opt/extra_strats 2>/dev/null || true
      cp -rf /opt/zapret2/extra_strats /opt/ || true
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

  # Раскомменчивание юзера под keenetic или merlin
  change_user

  cp -f /opt/zapret2/config.default /opt/zapret2/config

  "$ZAPRET2_INIT" start

  # ВАЖНО: check_access_list — это по сути интерактивный тест (он сам печатает и может ждать Enter),
  # поэтому лучше вызывать его из get_menu отдельным пунктом ("01"), а не тут.
  # check_access_list

  echo -e "${green}Config файл обновлён. Листы подбора стратегий и исключений сброшены в дефолт, если не просили сохранить. Фейк файлы обновлены.${plain}"
  return 0
}

menu_action_toggle_bolvan_ports() {
  if grep -Eq '^NFQWS_PORTS_UDP=.*443$' "/opt/zapret2/config"; then
    sed -i '76s/443$/443,1400,3478-3481,5349,50000-50099,19294-19344/' /opt/zapret2/config
    sed -i 's/^--skip --filter-udp=50000/--filter-udp=50000/' "/opt/zapret2/config"

    init_dir="$(dirname "$ZAPRET2_INIT")"
    custom_dir="$init_dir/custom.d"
    rm -f "$custom_dir/50-discord-media" \
          "$custom_dir/50-stun4all"

    echo -e "${green}Уход от скриптов bol-van. Выделены порты 50000-50099,1400,3478-3481,5349 и раскомментированы стратегии DS, WA, TG${plain}"

  elif grep -q '443,1400,3478-3481,5349,50000-50099,19294-19344$' "/opt/zapret2/config"; then
    sed -i 's/443,1400,3478-3481,5349,50000-50099,19294-19344$/443/' /opt/zapret2/config
    sed -i 's/^--filter-udp=50000/--skip --filter-udp=50000/' "/opt/zapret2/config"

    init_dir="$(dirname "$ZAPRET2_INIT")"
    custom_dir="$init_dir/custom.d"
    mkdir -p "$custom_dir"
    curl -L -o "$custom_dir/50-stun4all" \
      https://raw.githubusercontent.com/bol-van/zapret2/master/init.d/custom.d.examples.linux/50-stun4all
    curl -L -o "$custom_dir/50-discord-media" \
      https://raw.githubusercontent.com/bol-van/zapret2/master/init.d/custom.d.examples.linux/50-discord-media

    echo -e "${green}Работа от скриптов bol-van. Вернули строку к виду NFQWS_PORTS_UDP=443 и добавили \"--skip \" в начале строк стратегии войса${plain}"
  else
    echo -e "${yellow}Неизвестное состояние строки NFQWS_PORTS_UDP. Проверь конфиг вручную.${plain}"
    return 0
  fi

  "$ZAPRET2_INIT" restart
  echo -e "${green}Выполнение переключений завершено.${plain}"
  return 0
}

menu_action_toggle_fwtype() {
  if grep -q '^FWTYPE=iptables$' "/opt/zapret2/config"; then
    sed -i 's/^FWTYPE=iptables$/FWTYPE=nftables/' "/opt/zapret2/config"
    /opt/zapret2/install_prereq.sh
    "$ZAPRET2_INIT" restart
    echo -e "${green}Zapret moode: nftables.${plain}"

  elif grep -q '^FWTYPE=nftables$' "/opt/zapret2/config"; then
    sed -i 's/^FWTYPE=nftables$/FWTYPE=iptables/' "/opt/zapret2/config"
    /opt/zapret2/install_prereq.sh
    "$ZAPRET2_INIT" restart
    echo -e "${green}Zapret moode: iptables.${plain}"

  else
    echo -e "${yellow}Неизвестное состояние строки FWTYPE. Проверь конфиг вручную.${plain}"
  fi

  return 0
}

menu_action_toggle_udp_range() {
  if grep -q '^NFQWS_PORTS_UDP=443' "/opt/zapret2/config"; then
    sed -i 's/^NFQWS_PORTS_UDP=443/NFQWS_PORTS_UDP=1026-65531,443/' "/opt/zapret2/config"
    sed -i 's/^--skip --filter-udp=1026/--filter-udp=1026/' "/opt/zapret2/config"
    echo -e "${green}Стратегия UDP обхода активирована. Выделены порты 1026-65531${plain}"

  elif grep -q '^NFQWS_PORTS_UDP=1026-65531,443' "/opt/zapret2/config"; then
    sed -i 's/^NFQWS_PORTS_UDP=1026-65531,443/NFQWS_PORTS_UDP=443/' "/opt/zapret2/config"
    sed -i 's/^--filter-udp=1026/--skip --filter-udp=1026/' "/opt/zapret2/config"
    echo -e "${green}Стратегия UDP обхода ДЕактивирована. Выделенные порты 1026-65531 убраны${plain}"

  else
    echo -e "${yellow}Неизвестное состояние строки NFQWS_PORTS_UDP. Проверь конфиг вручную.${plain}"
    return 0
  fi

  "$ZAPRET2_INIT" restart
  echo -e "${green}Выполнение переключений завершено.${plain}"
  return 0
}

menu_action_set_tls_blob() {
  local cfg="/opt/zapret2/config"
  local fake_dir="/opt/zapret2/files/fake"
  local prefix="--blob=maxru:@/opt/zapret2/files/fake/"
  local sed_ereg="-E"
  local current_blob=""
  local current_mode=""
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
  if grep -q -- "--lua-desync=fake:blob=fake_default_tls" "$cfg"; then
    current_mode="fake_default_tls (встроенный)"
  elif grep -q -- "--lua-desync=fake:blob=maxru" "$cfg"; then
    current_mode="maxru (внешний файл)"
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
      sed -i -E '/--filter-l7=tls/,/^[[:space:]]*--new[[:space:]]*$/ s#(--lua-desync=[^[:space:]]*fake:blob=)maxru#\1fake_default_tls#g' "$cfg"
    else
      sed -i -r '/--filter-l7=tls/,/^[[:space:]]*--new[[:space:]]*$/ s#(--lua-desync=[^[:space:]]*fake:blob=)maxru#\1fake_default_tls#g' "$cfg"
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
    sed -i -E '/--filter-l7=tls/,/^[[:space:]]*--new[[:space:]]*$/ s#(--lua-desync=[^[:space:]]*fake:blob=)fake_default_tls#\1maxru#g' "$cfg"
    sed -i -E "s#(${prefix})[^[:space:]]+#\\1${selected_blob}#g" "$cfg"
  else
    sed -i -r '/--filter-l7=tls/,/^[[:space:]]*--new[[:space:]]*$/ s#(--lua-desync=[^[:space:]]*fake:blob=)fake_default_tls#\1maxru#g' "$cfg"
    sed -i -r "s#(${prefix})[^[:space:]]+#\\1${selected_blob}#g" "$cfg"
  fi
  echo -e "${green}Обновлено: --blob=maxru -> ${selected_blob}${plain}"
  echo -e "${yellow}Перезапустите zapret2 (пункт 2 меню), чтобы применить изменения.${plain}"
  pause_enter
  return 0
}
