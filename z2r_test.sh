#!/bin/sh

set -eu

REPO_OWNER="AloofLibra"
REPO_NAME="zapret4rocket"
REPO_BRANCH="${REPO_BRANCH:-z2r_test}"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}"

ZROOT="/opt/zapret2"
LIB_DIR="$ZROOT/z2r_lib"
WEBUI_ROOT="$ZROOT/webui"
WEBUI_WWW="$WEBUI_ROOT/www"
WEBUI_CGI="$WEBUI_ROOT/cgi-bin"
BACKUP_ROOT="/opt/z2r_test_backup_$(date +%Y%m%d_%H%M%S)"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Не найдено: $1"
    exit 1
  }
}

fetch_file() {
  src="$1"
  dst="$2"
  mkdir -p "$(dirname "$dst")"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$dst" "${RAW_BASE}/${src}"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dst" "${RAW_BASE}/${src}"
  else
    echo "Нужен curl или wget"
    exit 1
  fi
}

backup_if_exists() {
  src="$1"
  if [ -e "$src" ]; then
    dst="$BACKUP_ROOT$src"
    mkdir -p "$(dirname "$dst")"
    cp -fpR "$src" "$dst"
  fi
}

install_one() {
  repo_path="$1"
  target_path="$2"
  tmp="/tmp/$(basename "$target_path").z2r_test.$$"
  backup_if_exists "$target_path"
  echo "Скачиваю ${repo_path}"
  fetch_file "$repo_path" "$tmp"
  chmod 0644 "$tmp"
  case "$target_path" in
    *.sh|*.cgi) chmod 0755 "$tmp" ;;
  esac
  mv "$tmp" "$target_path"
}

restart_webui_if_present() {
  if [ -x "$WEBUI_ROOT/run-webui.sh" ]; then
    echo "Перезапускаю web UI"
    "$WEBUI_ROOT/run-webui.sh" restart >/dev/null 2>&1 || "$WEBUI_ROOT/run-webui.sh" start >/dev/null 2>&1 || true
  fi
}

print_check_urls() {
  if [ -x "$WEBUI_ROOT/run-webui.sh" ]; then
    "$WEBUI_ROOT/run-webui.sh" status 2>/dev/null || true
    echo "Проверка CGI endpoints:"
    echo "  http://127.0.0.1:17682/cgi-bin/blockcheck-meta.cgi"
    echo "  http://127.0.0.1:17682/cgi-bin/blockcheck-last.cgi"
  fi
}

main() {
  need_cmd date
  [ -d "$ZROOT" ] || {
    echo "Папка $ZROOT не найдена. Сначала установите z2r/zapret2."
    exit 1
  }

  mkdir -p "$LIB_DIR" "$WEBUI_WWW" "$WEBUI_CGI" "$BACKUP_ROOT"

  echo "Бэкап будет сохранён в: $BACKUP_ROOT"

  install_one "z2r.sh" "$ZROOT/z2r.sh"
  install_one "lib/submenus.sh" "$LIB_DIR/submenus.sh"
  install_one "lib/blockcheck.sh" "$LIB_DIR/blockcheck.sh"

  install_one "webui/index.html" "$WEBUI_WWW/index.html"
  install_one "webui/app.js" "$WEBUI_WWW/app.js"
  install_one "webui/styles.css" "$WEBUI_WWW/styles.css"
  install_one "webui/run-webui.sh" "$WEBUI_ROOT/run-webui.sh"

  install_one "webui/cgi-bin/_lib.sh" "$WEBUI_CGI/_lib.sh"
  install_one "webui/cgi-bin/status.cgi" "$WEBUI_CGI/status.cgi"
  install_one "webui/cgi-bin/locks.cgi" "$WEBUI_CGI/locks.cgi"
  install_one "webui/cgi-bin/set-lock.cgi" "$WEBUI_CGI/set-lock.cgi"
  install_one "webui/cgi-bin/clear-lock.cgi" "$WEBUI_CGI/clear-lock.cgi"
  install_one "webui/cgi-bin/restart.cgi" "$WEBUI_CGI/restart.cgi"
  install_one "webui/cgi-bin/check.cgi" "$WEBUI_CGI/check.cgi"
  install_one "webui/cgi-bin/meta.cgi" "$WEBUI_CGI/meta.cgi"
  install_one "webui/cgi-bin/blockcheck-meta.cgi" "$WEBUI_CGI/blockcheck-meta.cgi"
  install_one "webui/cgi-bin/blockcheck-profile.cgi" "$WEBUI_CGI/blockcheck-profile.cgi"
  install_one "webui/cgi-bin/blockcheck-custom.cgi" "$WEBUI_CGI/blockcheck-custom.cgi"
  install_one "webui/cgi-bin/blockcheck-last.cgi" "$WEBUI_CGI/blockcheck-last.cgi"
  install_one "webui/cgi-bin/blockcheck-apply.cgi" "$WEBUI_CGI/blockcheck-apply.cgi"
  install_one "webui/cgi-bin/blockcheck-worker.sh" "$WEBUI_CGI/blockcheck-worker.sh"
  install_one "webui/cgi-bin/blockcheck-profile-start.cgi" "$WEBUI_CGI/blockcheck-profile-start.cgi"
  install_one "webui/cgi-bin/blockcheck-custom-start.cgi" "$WEBUI_CGI/blockcheck-custom-start.cgi"
  install_one "webui/cgi-bin/blockcheck-job.cgi" "$WEBUI_CGI/blockcheck-job.cgi"

  mkdir -p "$ZROOT/extra_strats/cache/blockcheck2/history"

  restart_webui_if_present

  echo ""
  echo "Готово."
  echo "Обновлены test-файлы из ветки: $REPO_BRANCH"
  echo "Для CLI запустите: sh $ZROOT/z2r.sh"
  print_check_urls
}

main "$@"
