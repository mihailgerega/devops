#!/usr/bin/env bash
# monitor.sh — состояние systemd-сервиса и количество ошибок в syslog за последний час.
#
# Использование: monitor.sh <service>        например: monitor.sh docker
# Коды выхода:   0 — сервис активен
#                1 — сервис не активен (inactive / failed / ...)
#                2 — ошибка запуска: нет аргумента, нет systemd, сервис не найден
#
# Журналы других сервисов и /var/log/syslog обычный пользователь может не видеть —
# тогда скрипт подскажет запустить его через sudo.
set -uo pipefail # без -e: ненулевые коды systemctl/grep разбираем сами

SYSLOG="${SYSLOG:-/var/log/syslog}"
ERROR_PATTERN='error|fail' # что считаем ошибкой (регистр не важен)

if [[ $# -ne 1 || -z $1 ]]; then
  echo "Использование: $(basename "$0") <service>" >&2
  exit 2
fi
service="$1"

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemctl не найден: скрипт работает только на хосте с systemd" >&2
  exit 2
fi

# systemctl is-active для несуществующего юнита просто вернёт "inactive",
# поэтому существование проверяем отдельно
if ! systemctl cat -- "$service" >/dev/null 2>&1; then
  echo "Сервис '$service' не найден" >&2
  exit 2
fi

# --- 1. Статус ---
status="$(systemctl is-active -- "$service")"
echo "Сервис:  $service"
echo "Статус:  $status"

# --- 2. Если не работает — последние 10 строк журнала ---
if [[ $status != active ]]; then
  echo "--- journalctl -u $service -n 10 ---"
  logs="$(journalctl -u "$service" -n 10 --no-pager -q 2>/dev/null)"
  if [[ -n $logs ]]; then
    echo "$logs"
  else
    echo "(журнал пуст или нет прав на чтение — попробуйте через sudo)"
  fi
fi

# --- 3. Ошибки в syslog за последний час ---
# grep отбирает строки с ошибками, awk разбирает время записи и считает те,
# что новее since. Поддержаны оба формата rsyslog:
#   Ubuntu 22.04:  "Oct  7 14:51:01 host prog: ..."           (год не пишется — берём текущий)
#   Ubuntu 24.04:  "2026-10-07T14:51:01.487193+03:00 host ..." (RFC 3339)
if [[ ! -r $SYSLOG ]]; then
  echo "Ошибок в $SYSLOG за час: n/a (файла нет или нет прав — попробуйте через sudo)"
else
  since="$(date -d '1 hour ago' +%s)"
  errors="$(grep -iE "$ERROR_PATTERN" "$SYSLOG" | awk -v since="$since" -v year="$(date +%Y)" '
    BEGIN {
      split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", names, " ")
      for (i = 1; i <= 12; i++) month[names[i]] = i
    }
    { ts = 0 }
    $1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T/ {
      ts = mktime(substr($1, 1, 4) " " substr($1, 6, 2) " " substr($1, 9, 2) " " \
                  substr($1, 12, 2) " " substr($1, 15, 2) " " substr($1, 18, 2))
    }
    $1 in month {
      split($3, t, ":")
      ts = mktime(year " " month[$1] " " $2 " " t[1] " " t[2] " " t[3])
    }
    ts >= since { n++ }
    END { print n + 0 }
  ')"
  echo "Ошибок в $SYSLOG за час: $errors"
fi

[[ $status == active ]] && exit 0 || exit 1
