# UI helpers

pause_enter() {
  read -re -p "Enter для продолжения" _
}

submenu_item() {
  local key="$1"
  if [ "$key" = "0" ]; then
    echo -e "${Fyellow}${key}.${plain} ${Fyellow}$2${plain} $3"
  else
    echo -e "${Fcyan}${key}.${plain} ${green}$2${plain} $3"
  fi
}

# Совместимость со старым кодом меню
exit_to_menu() {
  pause_enter
}
