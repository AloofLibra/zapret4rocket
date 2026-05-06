# submenus.sh
# Единый стиль: loop + return на 0/Enter

#функция меню "1. Сменить стратегии"
strategies_submenu() {
  while true; do
    local strategies_status
    strategies_status=$(get_orchestra_locks_info)
    local p1_max p2_max p3_max p4_max p5_max p6_max
    p1_max="$(orch_max_strategy_for_profile 1)"
    p2_max="$(orch_max_strategy_for_profile 2)"
    p3_max="$(orch_max_strategy_for_profile 3)"
    p4_max="$(orch_max_strategy_for_profile 4)"
    p5_max="$(orch_max_strategy_for_profile 5)"
    p6_max="$(orch_max_strategy_for_profile 6)"
    clear

    echo -e "${cyan}--- Управление стратегиями ---${plain}"
    echo -e "${yellow}Выбор стратегии профиля (0 или Enter для выхода)${plain}"
    echo -e "  Текущие стратегии [${strategies_status}]"
    echo -e 

    submenu_item "	1" "Профиль 1: TCP 80/443 (YouTube) [${p1_max:-0}]" "tls"
    submenu_item "	2" "Профиль 2: TCP 80/443 (Googlevideo) [${p2_max:-0}]" "tls"
    submenu_item "	3" "Профиль 3: TCP 80/443 (RKN) [${p3_max:-0}]" "tls"
    submenu_item "	4" "Профиль 4: TCP 80/443 (Discord) [${p4_max:-0}]" "tls"
    submenu_item "	5" "Профиль 5: UDP 443 (YouTube QUIC) [${p5_max:-0}]" "udp"
    submenu_item "	6" "Профиль 6: UDP Voice (Discord/STUN) [${p6_max:-0}]" "udp"
    submenu_item "	8" "Fallback (безразборный блок)"
    submenu_item "	9" "Добавить домен в RKN список (с/без подбора стратегии)"
    submenu_item "	0" "Назад"
    echo ""

    read -re -p "Ваш выбор: " ans

    case "$ans" in
      "1")
        orch_profile_try "1" "Профиль 1: TCP 80/443 (YouTube)" "tls http" "https://www.youtube.com/"
        ;;
      "2")
        orch_profile_try "2" "Профиль 2: TCP 80/443 (Googlevideo)" "tls" "https://$(get_yt_cluster_domain)"
        ;;
      "3")
        orch_profile_try "3" "Профиль 3: TCP 80/443 (RKN)" "tls" "https://meduza.io"
        ;;
      "4")
        orch_profile_try "4" "Профиль 4: TCP 80/443 (Discord)" "tls" "https://discord.com/"
        ;;
      "5")
        echo -e "${yellow}Проверьте работоспособность в браузере.${plain}"
        orch_profile_try "5" "Профиль 5: UDP 443 (YouTube QUIC)" "udp" ""
        ;;
      "6")
        echo -e "${yellow}Проверьте работоспособность в приложении.${plain}"
        orch_profile_try "6" "Профиль 6: UDP Voice (Discord/STUN)" "udp" ""
        ;;
      "8")
        fallback_profile_try
        ;;
      "9")
        manage_custom_rkn_domain
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

flowoffload_submenu() {
  while true; do
    clear
    echo -e "${cyan}--- FLOWOFFLOAD ---${plain}"
    echo "Текущее состояние: $(grep '^FLOWOFFLOAD=' /opt/zapret2/config 2>/dev/null)"
    echo ""

    submenu_item "1" "software (программное ускорение)"
    submenu_item "2" "hardware (аппаратное NAT)"
    submenu_item "3" "none (отключено)"
    submenu_item "4" "donttouch (дефолт)"
    submenu_item "0" "Назад"
    echo ""

    read -re -p "Ваш выбор: " ans

    case "$ans" in
      "1")
        sed -i 's/^FLOWOFFLOAD=.*/FLOWOFFLOAD=software/' "/opt/zapret2/config"
        /opt/zapret2/install_prereq.sh
        "$ZAPRET2_INIT" restart
        echo -e "${green}FLOWOFFLOAD=software применён.${plain}"
        pause_enter
        ;;
      "2")
        sed -i 's/^FLOWOFFLOAD=.*/FLOWOFFLOAD=hardware/' "/opt/zapret2/config"
        /opt/zapret2/install_prereq.sh
        "$ZAPRET2_INIT" restart
        echo -e "${green}FLOWOFFLOAD=hardware применён.${plain}"
        pause_enter
        ;;
      "3")
        sed -i 's/^FLOWOFFLOAD=.*/FLOWOFFLOAD=none/' "/opt/zapret2/config"
        /opt/zapret2/install_prereq.sh
        "$ZAPRET2_INIT" restart
        echo -e "${green}FLOWOFFLOAD=none применён.${plain}"
        pause_enter
        ;;
      "4")
        sed -i 's/^FLOWOFFLOAD=.*/FLOWOFFLOAD=donttouch/' "/opt/zapret2/config"
        /opt/zapret2/install_prereq.sh
        "$ZAPRET2_INIT" restart
        echo -e "${green}FLOWOFFLOAD=donttouch применён.${plain}"
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

tcp443_submenu() {
  while true; do
  clear
  num=$(sed -n '112,130p' /opt/zapret2/config | grep -n '^--filter-tcp=443 --hostlist-domains= --' | head -n1 | cut -d: -f1)
  echo -e "${yellow}Безразборный режим по стратегии: ${plain}$((num ? num : 0))"
  echo -e "\033[33mС каким номером применить стратегию? (1-19, 0 - отключение безразборного режима, Enter - выход) \033[31mПри активации кастомно подобранные домены будут очищены:${plain}"
  read -re -p " " answer_bezr
  
  case "$answer_bezr" in
    "" )
      return
      ;;
    *)
      if echo "$answer_bezr" | grep -Eq '^[0-9]+$' && [ "$answer_bezr" -ge 0 ] && [ "$answer_bezr" -le 19 ]; then
        #Отключение
        for i in $(seq 112 130); do
          if sed -n "${i}p" /opt/zapret2/config | grep -Fq -- '--filter-tcp=443 --hostlist-domains= --h'; then
            sed -i "${i}s#--filter-tcp=443 --hostlist-domains= --h#--filter-tcp=443 --hostlist-domains=none.dom --h#" /opt/zapret2/config
            "$ZAPRET2_INIT" restart
            echo -e "${green}Выполнена команда перезапуска zapret${plain}"
            echo "Безразборный режим отключен"
            break
          fi
        done
        if [ "$answer_bezr" -ge 1 ] && [ "$answer_bezr" -le 19 ]; then
          for f_clear in $(seq 1 19); do
            echo -n > "/opt/zapret2/extra_strats/TCP/User/$f_clear.txt"
            echo -n > "/opt/zapret2/extra_strats/TCP/temp/$f_clear.txt"
          done
          sed -i "$((111 + answer_bezr))s/--hostlist-domains=none\.dom/--hostlist-domains=/" /opt/zapret2/config
          "$ZAPRET2_INIT" restart
          echo -e "${green}Выполнена команда перезапуска zapret. ${yellow}Безразборный режим активирован на $answer_bezr стратегии для TCP-443. Проверка доступа к meduza.io${plain}"
          check_access_list
        fi
        read -n 1 -s -r -p "Нажмите любую клавишу для продолжения..."
      else
        echo -e "${yellow}Неверный ввод.${plain}"
        sleep 1
        pause_enter
      fi
      ;;
  esac
done
}

provider_submenu() {
  provider_init_once

  while true; do
    clear
    echo -e "${cyan}--- Провайдер / подсказки ---${plain}"
    echo -e "Текущий провайдер: ${green}${PROVIDER_MENU}${plain}"
    echo ""

    submenu_item "1" "Указать провайдера вручную"
    submenu_item "2" "Определить провайдера заново (сбросить кэш)"
    submenu_item "3" "Обновить базу рекомендаций (подсказки)"
    submenu_item "0" "Назад"
    echo ""

    read -re -p "Ваш выбор: " ans

    case "$ans" in
      "1")
        provider_set_manual_menu
        sleep 1
        pause_enter
        ;;
      "2")
        provider_force_redetect
        sleep 1
        pause_enter
        ;;
      "3")
        echo "Обновляем базу рекомендаций..."
        rm -f "$RECS_FILE"
        update_recommendations
        if [ -s "$RECS_FILE" ]; then
          echo -e "${green}База успешно обновлена!${plain}"
        else
          echo -e "${red}Ошибка обновления базы.${plain}"
        fi
        sleep 1
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

beginner_guide_menu() {
  clear
  echo -e "${Bblue}${Fplain} Не знаешь, с чего начать? Есть проблемы? ${plain}"
  echo ""
  echo -e "${Fcyan}Что делает проект${plain}"
  echo -e "z2r устанавливает и настраивает zapret2 в ${yellow}/opt/zapret2${plain}, кладет туда конфиг,"
  echo -e "списки доменов, fake payload'ы и набор стратегий обхода. Дальше меню помогает"
  echo -e "перезапускать zapret2, переключать режимы и подбирать рабочие стратегии под"
  echo -e "конкретного провайдера и устройство."
  echo ""

  echo -e "${Fcyan}Обязательные шаги перед подбором${plain}"
  echo -e "${Fyellow}1.${plain} Настрой DoH/DoT на роутере или устройствах."
  echo -e "   РКН подменяет адреса при использовании незащищённых DNS. После смены DNS перезапусти"
  echo -e "   браузер или устройство, чтобы старый DNS-кэш не мешал проверкам."
  echo -e "${Fyellow}2.${plain} На Windows включи TCP timestamps в командной строке (CMD) от имени администратора:"
  echo -e "   ${green}netsh interface tcp set global timestamps=enabled${plain}"
  echo -e "   После команды лучше перезагрузиться."
  echo -e "${Fyellow}3.${plain} Проверь, что время и дата на роутере и клиенте выставлены правильно."
  echo -e "   Неверное время ломает TLS и делает диагностику бессмысленной."
  echo -e "${Fyellow}4.${plain} Не смешивай много изменений сразу: поменял стратегию - проверь сервис вручную."
  echo ""

  echo -e "${Fcyan}Где подбирать стратегии${plain}"
  echo -e "Подбор спрятан в ${Fyellow}пункте 1${plain} главного меню:"
  echo -e "${green}Фиксация стратегии профиля/безразборного блока${plain}."
  echo -e "Внутри профили уже разделены по сервисам и протоколам."
  echo -e "Выбери тот который нужно настроить и запустится перебор стратегий."
  echo ""

  echo -e "${Fcyan}Порядок для YouTube${plain}"
  echo -e "${Fyellow}1.${plain} Сначала подбери профиль 1: ${green}TCP 80/443 (YouTube)${plain}."
  echo -e "Он отвечает за загрузку самого сайта Youtube.com."
  echo -e "${Fyellow}2.${plain} Потом профиль 2: ${green}TCP 80/443 (Googlevideo)${plain}."
  echo -e "Он отвечает за загрузку видео на большинстве устройств"
  echo -e "${Fyellow}3.${plain} Потом опционально профиль 5: ${green}UDP 443 (YouTube QUIC)${plain}."
  echo -e "   QUIC обычно нужен для мобильных устройств, но и браузер также будет его использовать, если он работает"
  echo -e "   Но если YouTube уже стабильно работает, то QUIC можно не трогать."
  echo ""

  echo -e "${Fcyan}Порядок для Discord${plain}"
  echo -e "${Fyellow}1.${plain} Сначала настрой профиль 4: ${green}TCP 80/443 (Discord)${plain}."
  echo -e "   Добейся, чтобы сайт или приложение открывались и логинились."
  echo -e "Как правило, этого достаточно для полноценной работоспособности Discord"
  echo -e "${Fyellow}2.${plain} Если не работает голосовая связь, то тебе поможет профиль 6: ${green}UDP Voice (Discord/STUN)${plain}."
  echo -e "   Это отдельная настройка для голосовой связи."
  echo -e "   Важно: Для кастомных UDP-стратегий Discord сначала переключи пункт 8 главного меню"
  echo -e "   со стандартных скриптов bol-van на кастомные стратегии для голосовой связи."
  echo ""

  echo -e "${Fcyan}Полезные ориентиры${plain}"
  echo -e "- Пункт 16 меняет TLS blob; пробуй поиграться с ними, если TLS-профили работают нестабильно или не работают вовсе."
  echo -e "- Fallback/безразборный режим помогает в случаях когда нужно получить доступ ко множеству сайтов которых нет в списке RKN"
  echo -e "  Начни с 26 стратегии для безразборного режима. Она самая универсальная."
  echo -e "- После обновления стратегий пунктом 5 старые списки подбора могут сброситься;"
  echo -e "  если есть рабочая схема, перед обновлением соглашайся на бэкап."
  echo ""
  pause_enter
}
