#!/bin/bash
# Полностью удаляет FanControl: приложение, помощник, автозапуск и настройки.
set -euo pipefail

LABEL=com.george527.fancontrol.helper

pkill -x FanControl 2>/dev/null || true
sudo -v
# Помощник по SIGTERM возвращает вентиляторы под управление macOS.
sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
sudo rm -f "/Library/PrivilegedHelperTools/$LABEL" "/Library/LaunchDaemons/$LABEL.plist" /var/log/fancontrold.log
rm -rf /Applications/FanControl.app 2>/dev/null || sudo rm -rf /Applications/FanControl.app
rm -f ~/Library/LaunchAgents/com.george527.fancontrol.plist
defaults delete com.george527.fancontrol 2>/dev/null || true
echo "FanControl удалён, вентиляторы снова под управлением macOS."
