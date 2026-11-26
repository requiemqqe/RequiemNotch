#!/bin/bash
# Выпуск новой версии RequiemNotch для автообновлений.
# Использование (из папки проекта, где лежит appcast.xml):
#   ./release.sh ~/Desktop/RequiemNotch.app "Что нового в этой версии"
set -euo pipefail

REPO="requiemqqe/RequiemNotch"
APP="${1:?Укажи путь к RequiemNotch.app, например: ./release.sh ~/Desktop/RequiemNotch.app}"
NOTES="${2:-Bug fixes and improvements.}"

[ -d "$APP" ] || { echo "Не найдено приложение: $APP"; exit 1; }
[ -f appcast.xml ] || { echo "Запусти скрипт из папки проекта, где лежит appcast.xml"; exit 1; }

PLIST="$APP/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST")
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$PLIST" 2>/dev/null || echo "14.0")

# Номер сборки должен расти с каждым выпуском, иначе Sparkle не увидит обновление
if grep -q "<sparkle:version>$BUILD</sparkle:version>" appcast.xml; then
  echo "Сборка $BUILD уже выпущена. Увеличь Build в Xcode (General → Identity) и собери заново."
  exit 1
fi

# Утилита подписи из пакета Sparkle (Xcode скачивает её вместе с пакетом)
SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData -path "*artifacts/sparkle/Sparkle/bin/sign_update" -type f 2>/dev/null | head -1)
[ -n "$SIGN_UPDATE" ] || { echo "Не найден sign_update. Собери проект в Xcode хотя бы раз после добавления Sparkle."; exit 1; }

mkdir -p releases
ZIP="releases/RequiemNotch-$VERSION.zip"
rm -f "$ZIP"
echo "→ Упаковываю $VERSION ($BUILD)…"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "→ Подписываю обновление…"
SIGNATURE=$("$SIGN_UPDATE" "$ZIP")

URL="https://github.com/$REPO/releases/download/v$VERSION/RequiemNotch-$VERSION.zip"
ITEM=$(mktemp)
cat > "$ITEM" <<ITEM_EOF
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -R)</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[<p>$NOTES</p>]]></description>
      <enclosure url="$URL" $SIGNATURE type="application/octet-stream"/>
    </item>
ITEM_EOF

# Новая версия встаёт первой в списке
sed -i '' "/<!-- releases -->/r $ITEM" appcast.xml
rm -f "$ITEM"
echo "→ appcast.xml обновлён"

if command -v gh >/dev/null 2>&1; then
  echo "→ Создаю релиз на GitHub…"
  gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "RequiemNotch $VERSION" --notes "$NOTES"
  git add appcast.xml
  git commit -m "Release $VERSION"
  git push
  echo "✓ Готово: у друзей появится обновление до $VERSION"
else
  echo ""
  echo "Осталось два шага вручную:"
  echo "1. github.com/$REPO → Releases → Draft a new release"
  echo "   Tag: v$VERSION, приложи файл $ZIP → Publish release"
  echo "2. git add appcast.xml && git commit -m \"Release $VERSION\" && git push"
fi
