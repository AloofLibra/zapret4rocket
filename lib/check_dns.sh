#!/bin/sh

DOMAIN="${1:-rutracker.org}"

# Если запущено из z2r.sh — используем его цвета
[ -n "$plain" ]  || plain='\033[0m'
[ -n "$red" ]    || red='\033[0;31m'
[ -n "$green" ]  || green='\033[0;32m'
[ -n "$yellow" ] || yellow='\033[0;33m'

echo "================================================"
echo " Анализ DNS для домена: $DOMAIN"
echo "================================================"

DOH_RAW=$(curl -s --max-time 5 "https://dns.google/resolve?name=${DOMAIN}&type=A")

if [ -z "$DOH_RAW" ]; then
    echo -e "${red}[-] Ошибка: Google DoH недоступен${plain}"
    exit 1
fi

DOH_IPS=$(
    echo "$DOH_RAW" \
    | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' \
    | sort -u
)

echo -e "${yellow}-> Эталонные IP от DoH:${plain}"
for ip in $DOH_IPS; do
    echo "  $ip"
done

echo "----------------------------------------"

NS_RAW=$(nslookup "$DOMAIN" 2>/dev/null)

if [ -z "$NS_RAW" ]; then
    echo -e "${red}[-] Ошибка: nslookup не смог разрешить домен${plain}"
    exit 1
fi

NS_IPS=$(
    echo "$NS_RAW" \
    | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' \
    | grep -v '^127\.0\.0\.1$' \
    | sort -u
)

echo -e "${yellow}-> Полученные IP от nslookup:${plain}"

if [ -z "$NS_IPS" ]; then
    echo "  Пустой ответ"
else
    for ip in $NS_IPS; do
        echo "  $ip"
    done
fi

echo "================================================"

# Нет ответа вообще
if [ -z "$NS_IPS" ]; then
    echo -e "${red} ВНИМАНИЕ: DNS не вернул ни одного IPv4 адреса${plain}"
    echo "================================================"
    exit 2
fi

# Явная подмена на localhost
if echo "$NS_IPS" | grep -Eq '^(127\.0\.0\.1|0\.0\.0\.0)$'; then
    echo -e "${red} ВНИМАНИЕ: ОБНАРУЖЕНА ЯВНАЯ DNS-ПОДМЕНА${plain}"
    echo " DNS вернул адрес блокировки: $NS_IPS"
    echo "================================================"
    exit 2
fi

MATCH_IPS=""
MATCH_COUNT=0

for ip in $NS_IPS; do
    if echo "$DOH_IPS" | grep -qx "$ip"; then
        MATCH_IPS="$MATCH_IPS $ip"
        MATCH_COUNT=$((MATCH_COUNT + 1))
    fi
done

DOH_COUNT=$(echo "$DOH_IPS" | wc -w | tr -d ' ')
NS_COUNT=$(echo "$NS_IPS" | wc -w | tr -d ' ')

# Полное совпадение
if [ "$MATCH_COUNT" -eq "$DOH_COUNT" ] && [ "$DOH_COUNT" -eq "$NS_COUNT" ]; then

    echo -e "${green} ВЕРДИКТ: ВСЁ ЧИСТО${plain}"
    echo " IP из локального DNS полностью совпадают с DoH."
    echo " Явной подмены DNS не обнаружено."
    echo "================================================"
    exit 0

fi

# Частичное совпадение — НОРМАЛЬНО для CDN
if [ "$MATCH_COUNT" -gt 0 ]; then

    echo -e "${green} ВЕРДИКТ: DNS РАБОТАЕТ КОРРЕКТНО${plain}"
    echo " Найдены совпадающие IP:"
    for ip in $MATCH_IPS; do
        echo "  $ip"
    done
    echo ""
    echo " Ответы отличаются частично."
    echo " Для Cloudflare/CDN это является нормальным поведением."
    echo " Признаков DNS-подмены не обнаружено."
    echo "================================================"
    exit 0

fi

# Нет ни одного совпадения
echo -e "${red} ВНИМАНИЕ: ВОЗМОЖНА DNS-ПОДМЕНА${plain}"
echo " Совпадающих IP между DoH и локальным DNS не найдено."
echo ""
echo " Возможные причины:"
echo " - DNS фильтрация провайдера"
echo " - Подмена DNS"
echo " - Некорректная работа DNS сервера"
echo "================================================"

exit 2