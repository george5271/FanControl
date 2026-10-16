#!/bin/bash
# Устанавливает FanControl.app в /Applications и root-помощник как LaunchDaemon.
# Запрашивает пароль администратора (sudo) один раз.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/FanControl.app
LABEL=com.george527.fancontrol.helper
HELPER=/Library/PrivilegedHelperTools/$LABEL
DAEMON=/Library/LaunchDaemons/$LABEL.plist

if [ ! -d "$APP" ]; then
    echo "Нет $APP — сначала выполните scripts/build.sh" >&2
    exit 1
fi

if pgrep -xq "Macs Fan Control"; then
    echo "ВНИМАНИЕ: запущен Macs Fan Control. Закройте его — два приложения будут перебивать друг друга." >&2
fi

echo "==> Закрываю запущенный FanControl (если есть)"
pkill -x FanControl 2>/dev/null || true

sudo -v

echo "==> Установка помощника в $HELPER"
sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
sudo mkdir -p /Library/PrivilegedHelperTools
sudo install -o root -g wheel -m 755 "$APP/Contents/Resources/fancontrold" "$HELPER"
sudo install -o root -g wheel -m 644 "$APP/Contents/Resources/$LABEL.plist" "$DAEMON"

# После bootout launchd иногда ещё пару секунд освобождает метку.
for attempt in 1 2 3 4 5; do
    if sudo launchctl bootstrap system "$DAEMON" 2>/dev/null; then break; fi
    if [ "$attempt" = 5 ]; then
        echo "Не удалось запустить помощник: sudo launchctl bootstrap system $DAEMON" >&2
        exit 1
    fi
    sleep 1
done

echo "==> Установка приложения в /Applications"
rm -rf /Applications/FanControl.app 2>/dev/null || sudo rm -rf /Applications/FanControl.app
ditto "$APP" /Applications/FanControl.app 2>/dev/null || sudo ditto "$APP" /Applications/FanControl.app

echo "==> Запуск"
open /Applications/FanControl.app
echo "Готово. Иконка вентилятора появится в строке меню. Лог помощника: /var/log/fancontrold.log"
