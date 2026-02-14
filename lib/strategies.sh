# Функция определяет номер активной стратегии в указанной папке
# Использование: get_active_strat_num "/path/to/folder" MAX_COUNT
get_active_strat_num() {
    local folder="$1"
    local max="$2"
    local i
    
    # Перебираем файлы от 1 до MAX
    for ((i=1; i<=max; i++)); do
        if [ -s "${folder}/${i}.txt" ]; then
            echo "$i"
            return
        fi
    done
    
    # Если ничего не найдено - 0
    echo "0"
}

# Функция для генерации строки статуса стратегий
get_current_strategies_info() {
    local s_udp=$(get_active_strat_num "/opt/zapret2/extra_strats/UDP/YT" 8)
    local s_tcp=$(get_active_strat_num "/opt/zapret2/extra_strats/TCP/YT" 19)
    local s_gv=$(get_active_strat_num "/opt/zapret2/extra_strats/TCP/GV" 19)
    local s_rkn=$(get_active_strat_num "/opt/zapret2/extra_strats/TCP/RKN" 19)
    
    # Формируем красивую строку. Цвета можно менять.
    # Функция для окраски: 0 - серый, >0 - зеленый
    colorize_num() {
        if [ "$1" == "0" ]; then
            echo "${gray}Def${plain}"
        else
            echo "${green}$1${plain}"
        fi
    }

    echo -e "YT_UDP:$(colorize_num "$s_udp") YT_TCP:$(colorize_num "$s_tcp") YT_GV:$(colorize_num "$s_gv") RKN:$(colorize_num "$s_rkn")"
}

orch_lock_file="${orch_lock_file:-/opt/zapret2/extra_strats/cache/orchestra/locked.tsv}"

orch_locked_get() {
    local profile="$1"
    local proto="$2"
    [ ! -f "$orch_lock_file" ] && { echo "0"; return; }
    awk -v pr="$profile" -v p="$proto" 'BEGIN{FS="\t"}{
        if ($1==pr && $2==p && NF>=3) {print $3; exit}
        if ($1==pr && NF==2 && p=="tls") {print $2; exit}
    } END{if (NR==0) print 0}' "$orch_lock_file"
}

orch_locked_set() {
    local profile="$1"
    local proto="$2"
    local strat="$3"
    local tmp="${orch_lock_file}.tmp"
    mkdir -p "$(dirname "$orch_lock_file")"
    touch "$orch_lock_file"
    awk -v pr="$profile" -v p="$proto" -v s="$strat" 'BEGIN{FS=OFS="\t"}{
        if ($1==pr && (($2==p) || (NF==2 && p=="tls"))) {print pr,p,s; found=1; next}
        print
    } END{
        if (!found) print pr,p,s
    }' "$orch_lock_file" > "$tmp" && mv "$tmp" "$orch_lock_file"
}

orch_locked_clear() {
    local profile="$1"
    local proto="$2"
    local tmp="${orch_lock_file}.tmp"
    [ ! -f "$orch_lock_file" ] && return 0
    awk -v pr="$profile" -v p="$proto" 'BEGIN{FS=OFS="\t"}{
        if ($1==pr && (($2==p) || (NF==2 && p=="tls"))) next
        print
    }' "$orch_lock_file" > "$tmp" && mv "$tmp" "$orch_lock_file"
}

orch_max_strategy_for_profile() {
    local profile="$1"
    local cfg="/opt/zapret2/config"
    [ ! -f "$cfg" ] && cfg="/opt/zapret2/config.default"
    if [ "$profile" = "8" ]; then
        local fallback_max
        fallback_max="$(awk '
            BEGIN{inblk=0; max=0}
            /^[[:space:]]*#Z2R_FALLBACK_BEGIN/ {inblk=1; next}
            /^[[:space:]]*#Z2R_FALLBACK_END/ {inblk=0; exit}
            inblk {
                line=$0
                while (match(line, /strategy=[0-9]+/)) {
                    num=substr(line, RSTART+9, RLENGTH-9)+0
                    if (num>max) max=num
                    line=substr(line, RSTART+RLENGTH)
                }
            }
            END{print max}
        ' "$cfg")"
        if [ -n "$fallback_max" ] && [ "$fallback_max" -gt 0 ]; then
            echo "$fallback_max"
            return
        fi
    fi
    awk -v pid="$profile" '
        BEGIN{inopt=0; prof=1; max=0}
        /^NFQWS2_OPT="/ {inopt=1}
        inopt {
            if ($0 ~ /^--new/) {prof++}
            if (prof==pid) {
                line=$0
                while (match(line, /strategy=[0-9]+/)) {
                    num=substr(line, RSTART+9, RLENGTH-9)+0
                    if (num>max) max=num
                    line=substr(line, RSTART+RLENGTH)
                }
            }
            if ($0 ~ /^"$/) {exit}
        }
        END{print max}
    ' "$cfg"
}

orch_profile_try() {
    local profile="$1"
    local title="$2"
    local proto_list="$3"
    local test_url="$4"
    local max_strat=""
    local start_strat=""
    local current_strat=""
    local answer=""
    local first_proto="${proto_list%% *}"
    local -A prev_map

    max_strat="$(orch_max_strategy_for_profile "$profile")"
    if [ -z "$max_strat" ] || [ "$max_strat" -le 0 ]; then
        echo "Не удалось определить число стратегий для профиля $profile."
        pause_enter
        return
    fi

    current_strat="$(orch_locked_get "$profile" "$first_proto")"
    if [ -z "$current_strat" ] || [ "$current_strat" -le 0 ]; then
        current_strat=1
    fi

    echo "$title"
    read -re -p "Введите номер стратегии (Enter - текущая $current_strat): " start_strat
    if [ -z "$start_strat" ]; then
        start_strat="$current_strat"
    fi
    if ! printf "%s" "$start_strat" | grep -Eq '^[0-9]+$'; then
        echo "Неверный номер стратегии. Начинаем с 1."
        start_strat=1
    elif [ "$start_strat" -lt 1 ] || [ "$start_strat" -gt "$max_strat" ]; then
        echo "Номер стратегии вне диапазона. Начинаем с 1."
        start_strat=1
    fi

    for p in $proto_list; do
        prev_map["$p"]="$(orch_locked_get "$profile" "$p")"
    done

    for ((s=start_strat; s<=max_strat; s++)); do
        for p in $proto_list; do
            orch_locked_set "$profile" "$p" "$s"
        done
        if [ -x "$ORCH_SCRIPT" ]; then
            "$ORCH_SCRIPT" sync
        fi
        echo "Стратегия $s применена."
        if [ "$test_url" = "__RUN_CDN_TEST__" ]; then
            echo "Проверка доступа: CDN test (как в пункте 001)"
            if type run_cdn_test >/dev/null 2>&1; then
                run_cdn_test
            else
                echo "run_cdn_test недоступен, пропускаем проверку."
            fi
        elif [ -n "$test_url" ]; then
            echo "Проверка доступа: $test_url"
            check_access "$test_url"
        fi

        read -re -p "1 - сохранить, 0 - отмена, Enter - далее: " answer
        if [ "$answer" = "1" ]; then
            echo "Стратегия $s сохранена для профиля $profile."
            pause_enter
            return
        elif [ "$answer" = "0" ]; then
            break
        fi
    done

    for p in $proto_list; do
        if [ -n "${prev_map[$p]}" ] && [ "${prev_map[$p]}" -gt 0 ]; then
            orch_locked_set "$profile" "$p" "${prev_map[$p]}"
        else
            orch_locked_clear "$profile" "$p"
        fi
    done
    if [ -x "$ORCH_SCRIPT" ]; then
        "$ORCH_SCRIPT" sync
    fi
    echo "Изменения отменены."
    pause_enter
}

get_orchestra_locks_info() {
    local yt_tls="" gv_tls="" rkn_tls="" ds_tls="" yt_quic_udp="" voice_udp="" tg_tls=""
    local v=""
    yt_tls="$(orch_locked_get 1 tls)"
    gv_tls="$(orch_locked_get 2 tls)"
    rkn_tls="$(orch_locked_get 3 tls)"
    ds_tls="$(orch_locked_get 4 tls)"
    yt_quic_udp="$(orch_locked_get 5 udp)"
    voice_udp="$(orch_locked_get 6 udp)"
    tg_tls="$(orch_locked_get 7 tls)"

    fmt_status_num() {
        v="${1:-0}"
        if [ "$v" = "0" ]; then
            printf "%b" "${Fyellow}0${plain}"
        else
            printf "%b" "${Fcyan}${v}${plain}"
        fi
    }

    printf "YT_TLS=%s GV_TLS=%s RKN_TLS=%s DS_TLS=%s YT_QUIC_UDP=%s VOICE_UDP=%s TG_TLS=%s" \
        "$(fmt_status_num "$yt_tls")" \
        "$(fmt_status_num "$gv_tls")" \
        "$(fmt_status_num "$rkn_tls")" \
        "$(fmt_status_num "$ds_tls")" \
        "$(fmt_status_num "$yt_quic_udp")" \
        "$(fmt_status_num "$voice_udp")" \
        "$(fmt_status_num "$tg_tls")"
}

manage_custom_rkn_domain() {
    local user_domain="" test_url="" rkn_file="" mode="" strategy_num=""
    local max_strat="" current_strat="" prev_strat="" answer=""
    local only_add=0

    read -re -p "Введите домен для добавления в RKN-обработку (например, example.com): " user_domain
    if [ -z "$user_domain" ]; then
        echo "Ввод пустой, ничего не добавлено."
        pause_enter
        return 0
    fi

    echo "1 - только добавить домен в список RKN"
    echo "2 - добавить и подобрать стратегию для этого домена"
    echo "0 - отмена"
    read -re -p "Ваш выбор: " mode

    case "$mode" in
        "1")
            only_add=1
            ;;
        "2")
            ;;
        "0"|"")
            echo "Отменено."
            pause_enter
            return 0
            ;;
        *)
            echo "Отменено."
            pause_enter
            return 0
            ;;
    esac

    rkn_file="/opt/zapret2/extra_strats/TCP_RKN_list.txt"
    mkdir -p /opt/zapret2/extra_strats
    if ! grep -Fxq "$user_domain" "$rkn_file" 2>/dev/null; then
        echo "$user_domain" >> "$rkn_file"
        echo -e "${green}Домен $user_domain добавлен в $rkn_file${plain}"
    else
        echo -e "${yellow}Домен $user_domain уже есть в $rkn_file${plain}"
    fi

    if [ "$only_add" -eq 1 ]; then
        pause_enter
        return 0
    fi

    max_strat="$(orch_max_strategy_for_profile 3)"
    if [ -z "$max_strat" ] || [ "$max_strat" -le 0 ]; then
        max_strat=19
    fi

    current_strat="$(orch_locked_get "$user_domain" "tls")"
    if ! printf "%s" "$current_strat" | grep -Eq '^[0-9]+$' || [ "$current_strat" -le 0 ]; then
        current_strat=1
    fi
    prev_strat="$(orch_locked_get "$user_domain" "tls")"

    read -re -p "Введите номер стратегии для старта (Enter - текущая $current_strat): " strategy_num
    if [ -z "$strategy_num" ]; then
        strategy_num="$current_strat"
    fi
    if ! printf "%s" "$strategy_num" | grep -Eq '^[0-9]+$'; then
        echo "Некорректный номер стратегии. Начинаем с 1."
        strategy_num=1
    elif [ "$strategy_num" -lt 1 ] || [ "$strategy_num" -gt "$max_strat" ]; then
        echo "Номер вне диапазона. Начинаем с 1."
        strategy_num=1
    fi

    test_url="$user_domain"
    if ! printf "%s" "$test_url" | grep -Eq '^https?://'; then
        test_url="https://$test_url"
    fi

    for ((s=strategy_num; s<=max_strat; s++)); do
        orch_locked_set "$user_domain" "tls" "$s"
        if [ -x "$ORCH_SCRIPT" ]; then
            "$ORCH_SCRIPT" sync
        fi

        echo "Стратегия $s применена для домена $user_domain"
        check_access "$test_url"

        read -re -p "1 - сохранить, 0 - отмена, Enter - далее: " answer
        if [ "$answer" = "1" ]; then
            echo "Стратегия $s сохранена для $user_domain."
            pause_enter
            return 0
        elif [ "$answer" = "0" ]; then
            break
        fi
    done

    if printf "%s" "$prev_strat" | grep -Eq '^[0-9]+$' && [ "$prev_strat" -gt 0 ]; then
        orch_locked_set "$user_domain" "tls" "$prev_strat"
    else
        orch_locked_clear "$user_domain" "tls"
    fi
    if [ -x "$ORCH_SCRIPT" ]; then
        "$ORCH_SCRIPT" sync
    fi
    echo "Изменения по стратегии для домена отменены."
    pause_enter
}

#Функция для функции подбора стратегий
try_strategies() {
    local count="$1"
    local base_path="$2"
    local list_file="$3"
    local final_action="$4"
    local current_active=""
    local prev_active=""
    local prev_file=""
    local strat_num=""
    local answer_strat=""
    local active=""
    
    current_active="$(get_active_strat_num "$base_path" "$count")"
    prev_active="$current_active"
    active="$current_active"

    read -re -p "Введите номер стратегии к которой перейти (Enter - текущая): " strat_num
    if [ -z "$strat_num" ]; then
        if [ "$current_active" -ge 1 ]; then
            strat_num="$current_active"
        else
            strat_num=1
        fi
    fi
    if ! printf "%s" "$strat_num" | grep -Eq '^[0-9]+$'; then
        echo "Введено некорректное значение. Начинаем с 1 стратегии"
        strat_num=1
    elif (( strat_num < 1 || strat_num > count )); then
        echo "Введено значение не из диапазона. Начинаем с 1 стратегии"
        strat_num=1
    fi

    if [ "$prev_active" -ge 1 ] && [ -s "$base_path/${prev_active}.txt" ]; then
        prev_file="$(mktemp -p /tmp z2r_prev_strat.XXXXXX 2>/dev/null || echo "/tmp/z2r_prev_strat.$$")"
        cp "$base_path/${prev_active}.txt" "$prev_file"
    fi
    cleanup_prev_file() {
        [ -n "$prev_file" ] && rm -f "$prev_file"
    }

    # Основной цикл перебора
    for ((strat_num=strat_num; strat_num<=count; strat_num++)); do
        
        # Очищаем файл предыдущей стратегии (чтобы не было дублей)
        if [ -n "$active" ] && [ "$active" -ge 1 ] && [ "$active" -ne "$strat_num" ]; then
            echo -n > "$base_path/${active}.txt"
        fi

        # Запись в файл текущей стратегии
        if [[ "$list_file" != "/dev/null" ]]; then
            # Режим списка (копируем весь файл)
            cp "$list_file" "$base_path/${strat_num}.txt"
        else
            # Режим одного домена
            printf "%s\n" "$user_domain" > "$base_path/${strat_num}.txt"
        fi
        
        echo "Стратегия номер $strat_num активирована"
        active="$strat_num"
            
        read -re -p "Проверьте работу вручную (1 - сохранить, 0 - отмена, Enter - далее): " answer_strat
        
        if [[ "$answer_strat" == "1" ]]; then
            echo "Стратегия $strat_num сохранена."
            send_stats  # Отправка телеметрии (если включена)

            for ((clr_txt=1; clr_txt<=count; clr_txt++)); do
                if [ "$clr_txt" -ne "$strat_num" ]; then
                    echo -n > "$base_path/${clr_txt}.txt"
                fi
            done
            
            # Если передано дополнительное действие (final_action), выполняем его
            if [[ -n "$final_action" ]]; then
                eval "$final_action"
            fi
            cleanup_prev_file
            return
            
        elif [[ "$answer_strat" == "0" ]]; then
            # Сброс текущей стратегии при отмене
            echo -n > "$base_path/${strat_num}.txt"
            echo "Изменения отменены."
            if [ -n "$prev_file" ] && [ "$prev_active" -ge 1 ]; then
                cp "$prev_file" "$base_path/${prev_active}.txt"
            fi
            cleanup_prev_file
            return
        fi
    done

    # Если цикл закончился, а пользователь ничего не выбрал
    if [ -n "$active" ] && [ "$active" -ge 1 ]; then
        echo -n > "$base_path/${active}.txt"
    fi
    if [ -n "$prev_file" ] && [ "$prev_active" -ge 1 ]; then
        cp "$prev_file" "$base_path/${prev_active}.txt"
    fi
    echo "Все стратегии испробованы. Ничего не подошло."
    pause_enter
    cleanup_prev_file
    return
}

#Сама функция подбора стратегий
Strats_Tryer() {
  local mode_domain="$1"
  local answer_strat_mode=""
  local user_domain=""

  # ВАЖНО: теперь Strats_Tryer не рисует меню и не спрашивает режим сам.
  # Режим выбирается снаружи (strategies_submenu), а сюда приходит либо:
  # - "1".."4" (режим)
  # - или строка-домен (режим кастомного домена)

  case "$mode_domain" in
    "1"|"2"|"3"|"4")
      answer_strat_mode="$mode_domain"
      ;;
    *)
      # Если аргумент не похож на режим — считаем, что это домен
      answer_strat_mode="5"
      user_domain="$mode_domain"
      ;;
  esac

  case "$answer_strat_mode" in
    "1")
      echo "Подбор для хост-листа YouTube с видеопотоком (UDP QUIC - браузеры, моб. приложения). Ранее заданная стратегия этого листа сброшена в дефолт."
      #вывод подсказки
      show_hint "UDP"
      try_strategies 13 "/opt/zapret2/extra_strats/UDP/YT" "/opt/zapret2/extra_strats/UDP/YT/List.txt" ""
      ;;
    "2")
      echo "Подбор для хост-листа YouTube (TCP - сам интерфейс. Без видео-домена). Ранее заданная стратегия этого листа сброшена в дефолт."
      #вывод подсказки
      show_hint "TCP"
      try_strategies 19 "/opt/zapret2/extra_strats/TCP/YT" "/opt/zapret2/extra_strats/TCP/YT/List.txt" ""
      ;;
    "3")
      echo "Подбор для googlevideo.com (Видеопоток YouTube). Ранее заданная стратегия этого листа сброшена в дефолт."
      #на всякий случай убираем GV из листа YT
      [ -f "/opt/zapret2/extra_strats/TCP/YT/List.txt" ] && \
        sed -i '/googlevideo.com/d' "/opt/zapret2/extra_strats/TCP/YT/List.txt"
      user_domain="googlevideo.com"
      #вывод подсказки
      show_hint "GV"
      try_strategies 19 "/opt/zapret2/extra_strats/TCP/GV" "/dev/null" ""
      ;;
    "4")
      echo "Подбор для хост-листа основных доменов блока RKN. Проверка доступности задана на домен meduza.io. Ранее заданная стратегия этого листа сброшена в дефолт."
      for numRKN in {1..19}; do
        echo -n > "/opt/zapret2/extra_strats/TCP/RKN/${numRKN}.txt"
      done
      user_domain="meduza.io"
      #вывод подсказки
      show_hint "RKN"
      try_strategies 19 "/opt/zapret2/extra_strats/TCP/RKN" "/opt/zapret2/extra_strats/TCP/RKN/List.txt" ""
      ;;
    "5")
      echo "Режим ручного указания домена"
      # раньше домен спрашивался тут, но теперь ввод домена делается в сабменю
      if [ -z "$user_domain" ]; then
        echo "Домен не задан. Отмена."
        return 0
      fi
      echo "Введён домен: $user_domain"

      try_strategies 19 "/opt/zapret2/extra_strats/TCP/temp" "/dev/null" \
        "echo -n > \"/opt/zapret2/extra_strats/TCP/temp/\${strat_num}.txt\"; \
         echo \"$user_domain\" >> \"/opt/zapret2/extra_strats/TCP/User/\${strat_num}.txt\""
      ;;
    *)
      echo "Пропуск подбора альтернативной стратегии"
      return 0
      ;;
  esac
}
