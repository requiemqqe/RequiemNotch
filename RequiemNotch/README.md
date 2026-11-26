<div align="center">

# RequiemNotch

**A Dynamic Island for your Mac.**
Music, files, clipboard, camera mirror and more — right in the notch.

[**⬇︎ Download the latest version**](https://github.com/requiemqqe/RequiemNotch/releases/latest)

macOS 14 Sonoma or later · Works best on MacBooks with a notch

[English](#features) · [Русский](#русский)

</div>

---

## Features

- **Now Playing** — artwork, progress bar with scrubbing, play/pause, next/previous, shuffle, repeat and ±15 s. Works with Music, Spotify, YouTube in the browser and most other players. Colors adapt to the artwork.
- **File shelf** — drop files onto the notch and drag them out on another desktop or into any app.
- **Clipboard history** — the text and images you copied, one click to copy again, pin the important ones. Passwords from password managers are never saved.
- **Camera mirror** — a quick look at yourself before a call.
- **Volume and brightness HUD** — a sleek indicator in the notch instead of the standard macOS one, plus sliders right in the island.
- **Live notifications** — charging, connected headphones and track changes appear in the notch for a moment.
- **Settings** in the menu bar icon: English, Русский, Українська.
- **Automatic updates.**

## Installation

1. Download **`RequiemNotch-x.x.zip`** from the [latest release](https://github.com/requiemqqe/RequiemNotch/releases/latest) and open it.
2. Drag **RequiemNotch** into your **Applications** folder.
3. The app isn't signed with a paid Apple developer certificate, so macOS will block the first launch. Unblock it **once**, either way:
   - **Terminal (simplest):**
     ```bash
     xattr -dr com.apple.quarantine /Applications/RequiemNotch.app
     ```
   - **Or System Settings:** open the app → click **Done** in the warning → **System Settings → Privacy & Security** → scroll down → **Open Anyway** → enter your password.
4. Launch RequiemNotch. Hover over the notch — that's it.

After that, new versions install themselves: you'll see an "Update available" window.

## Permissions

| Permission | Why | When |
|---|---|---|
| Bluetooth | Show connected headphones | Asked on first launch |
| Camera | Mirror | When you open the mirror |
| Accessibility | Replace the volume/brightness indicator | Only if you turn on *Settings → HUD* |

Everything works locally on your Mac. Nothing is sent anywhere.

## FAQ

**Where are the settings?** Click the island icon in the menu bar → **Settings…**

**How do I quit?** Menu bar icon → **Quit RequiemNotch**.

**My headphones show no battery level.** Many headphones don't report it to macOS — if it isn't in the Bluetooth menu, the app can't see it either. AirPods and Beats work.

**My Mac has no notch.** The island appears when you hover over the top center of the screen. Change it in *Settings → Island → Macs without a notch*.

**How do I uninstall?** Quit the app and move it from Applications to the Trash.

**Found a bug or have an idea?** [Open an issue](https://github.com/requiemqqe/RequiemNotch/issues/new).

---

<a id="русский"></a>

## Русский

**RequiemNotch** — Dynamic Island для Mac: музыка, файлы, буфер обмена, зеркало камеры и многое другое прямо в вырезе экрана.

### Возможности

- **Плеер** — обложка, перемотка, пауза, переключение треков, перемешивание, повтор и ±15 секунд. Работает с Музыкой, Spotify, YouTube в браузере и большинством других плееров. Цвета подстраиваются под обложку.
- **Полка файлов** — бросьте файлы на вырез и утащите их на другом рабочем столе или в любое приложение.
- **История буфера обмена** — скопированные тексты и картинки, копирование в один клик, закрепление важного. Пароли из менеджеров паролей не сохраняются.
- **Зеркало** — быстро глянуть на себя перед созвоном.
- **Громкость и яркость** — аккуратный индикатор в вырезе вместо стандартного и ползунки прямо в острове.
- **Живые уведомления** — зарядка, подключение наушников и смена трека ненадолго появляются в вырезе.
- **Настройки** — через значок в строке меню. Языки: English, Русский, Українська.
- **Автоматические обновления.**

### Установка

1. Скачайте **`RequiemNotch-x.x.zip`** со [страницы последнего релиза](https://github.com/requiemqqe/RequiemNotch/releases/latest) и откройте его.
2. Перетащите **RequiemNotch** в папку **Программы**.
3. Приложение не подписано платным сертификатом Apple, поэтому macOS заблокирует первый запуск. Разблокируйте **один раз** любым способом:
   - **Через Терминал (проще всего):**
     ```bash
     xattr -dr com.apple.quarantine /Applications/RequiemNotch.app
     ```
   - **Или через Системные настройки:** откройте приложение → в предупреждении нажмите **Готово** → **Системные настройки → Конфиденциальность и безопасность** → пролистайте вниз → **Всё равно открыть** → введите пароль.
4. Запустите RequiemNotch и наведите курсор на вырез — готово.

Дальше новые версии устанавливаются сами: появится окно «Доступно обновление».

### Разрешения

| Разрешение | Зачем | Когда спросит |
|---|---|---|
| Bluetooth | Показывать подключённые наушники | При первом запуске |
| Камера | Зеркало | Когда откроете зеркало |
| Универсальный доступ | Свой индикатор громкости и яркости | Только если включите *Settings → HUD* |

Всё работает только на вашем Mac, никакие данные никуда не отправляются.

### Частые вопросы

**Где настройки?** Значок острова в строке меню → **Settings…**

**Как закрыть приложение?** Значок в строке меню → **Quit RequiemNotch**.

**Не видно заряда наушников.** Многие наушники не сообщают заряд macOS: если его нет в меню Bluetooth, приложение его тоже не увидит. AirPods и Beats работают.

**У меня Mac без выреза.** Остров появляется при наведении на центр верхнего края экрана. Поведение меняется в *Settings → Island → Macs without a notch*.

**Как удалить?** Закройте приложение и перенесите его из «Программ» в Корзину.

**Нашли баг или есть идея?** [Напишите сюда](https://github.com/requiemqqe/RequiemNotch/issues/new).
