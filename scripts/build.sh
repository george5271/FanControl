#!/bin/bash
# Собирает build/FanControl.app (приложение + root-помощник внутри бандла).
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/FanControl.app
HELPER_LABEL=com.george527.fancontrol.helper

echo "==> Сборка (swift build -c release)"
swift build -c release
BIN=$(swift build -c release --show-bin-path)

if [ ! -f Resources/AppIcon.icns ]; then
    echo "==> Генерация иконки"
    swift scripts/make_icon.swift Resources/AppIcon.icns
fi

echo "==> Упаковка $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/FanControl" "$APP/Contents/MacOS/FanControl"
cp "$BIN/fancontrold" "$APP/Contents/Resources/fancontrold"
cp "Resources/$HELPER_LABEL.plist" "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

echo "==> Подпись (ad-hoc)"
# Помощник принимает XPC-подключения только от кода с идентификатором com.george527.fancontrol.
codesign --force --sign - --identifier "$HELPER_LABEL" "$APP/Contents/Resources/fancontrold"
codesign --force --sign - --identifier com.george527.fancontrol "$APP"
codesign --verify --strict "$APP"

echo "Готово: $APP"
echo "Установка: scripts/install.sh"
