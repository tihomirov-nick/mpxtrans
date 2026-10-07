# MPXTrans — расшифровка аудио и видео в текст (macOS)

Маленькое окно: перетаскиваете аудио или видео любого формата → Whisper распознаёт речь локально, без интернета →
текст можно поправить, скопировать, сохранить в файл или отправить через стандартное меню «Поделиться» macOS.

Готовый установщик `MPXTrans-<версия>.dmg` — на странице [релизов](https://github.com/tihomirov-nick/mpxtrans/releases/latest)
(macOS 13.3+, Apple Silicon и Intel; инструкция для пользователей — `docs/Как установить.txt`).

## Возможности

- **Любые форматы** — декодирование через встроенный ffmpeg: MP3, M4A, AAC, WAV, AIFF, FLAC, OGG, OPUS, WMA, AMR,
  MP4, MOV, MKV, WEBM, AVI, MTS… Файл можно перетащить в окно, на значок в Dock или открыть через «Открыть с помощью».
- **Whisper локально** (whisper.cpp 1.9.4, Metal на Apple Silicon). По умолчанию — стандартная **Whisper Large v3 Turbo**;
  в меню внизу окна — любая скачанная модель, в том числе дообученные на русской речи, и язык (русский по умолчанию,
  автоопределение или любой из ~100 языков Whisper).
- **Общие модели с Subtits** — папка `~/Library/Application Support/Subtits/Models`: модели, скачанные в Subtits,
  сразу доступны здесь, и наоборот. Недостающие скачиваются в окне «Модели распознавания» (с проверкой SHA-256
  и докачкой при обрыве связи).
- **Текст появляется по мере распознавания**, прогресс и оставшееся время — в окне и на значке в Dock;
  Mac не засыпает, пока идёт распознавание.
- **Пропуск тишины и музыки** (Silero VAD) — Whisper не придумывает фразы на паузах и музыке. Плюс фильтр типичных
  «галлюцинаций» («Субтитры сделал DimaTorzok», «[музыка]», повторяющиеся фразы).
- **Три вида результата**: текст с абзацами по паузам, текст с таймкодами `[01:23]`, субтитры SRT.
  Текст можно править прямо в окне (⌘F — поиск), правки хранятся отдельно для каждого вида.
- **Скопировать** (⇧⌘C), **Сохранить** (⌘S, `.txt` или `.srt` рядом с исходным файлом), **Поделиться** — AirDrop,
  Сообщения, Почта (с темой письма), Заметки и другие службы macOS.
- **Подсказка с именами и терминами** (настройки, ⌘,) — подставляется в каждое 30-секундное окно Whisper.
- **Дизайн Liquid Glass** (iOS 27 / macOS 26): стеклянные капсулы и карточки над мягким цветным фоном, иконка
  в формате Icon Composer — на macOS 26 система рисует её настоящим стеклом. На macOS 13–15 вместо стекла
  используются системные материалы. Светлая и тёмная тема, «Уменьшить движение».
- Интерфейс на русском и английском: русский, если он есть среди языков macOS (как в Subtits), иначе английский;
  язык, выбранный для приложения в «Системные настройки → Язык и регион → Приложения», важнее.

## Сборка

Нужны Xcode (Swift 5.10+) и, только для пересборки whisper.cpp, Homebrew `cmake`.

```bash
./scripts/make_dmg.sh            # всё сразу: зависимости → MPXTrans.app → dist/MPXTrans-1.0.0.dmg
VERSION=1.1.0 ./scripts/make_dmg.sh
```

| Скрипт | Что делает |
|---|---|
| `scripts/build_whisper.sh` | собирает whisper.cpp 1.9.4 (Metal + Accelerate) как universal static library → `Vendor/whisper` |
| `scripts/fetch_ffmpeg.sh` | скачивает статический ffmpeg 9.0.2 (arm64 + x86_64), проверяет SHA-256, склеивает в universal → `Vendor/ffmpeg` |
| `scripts/fetch_vad.sh` | скачивает модель Silero VAD с проверкой SHA-256 → `Resources/ggml-silero-v6.2.0.bin` |
| `scripts/build_app.sh` | universal-сборка → `build/MPXTrans.app`: ffmpeg в `Contents/Helpers`, иконка из `Resources/AppIcon.icon` через `actool`, переводы, подпись |
| `scripts/make_dmg.sh` | `build_app.sh` + DMG с ярлыком Applications и инструкциями на русском и английском |

Собранный whisper.cpp уже лежит в `Vendor/whisper` (скопирован из Subtits), поэтому обычная сборка занимает меньше
минуты. ffmpeg (154 МБ) в git не хранится — GitHub не принимает файлы больше 100 МБ: `build_app.sh` при первой сборке
сам скачает его через `scripts/fetch_ffmpeg.sh` (для `swift build` запустите этот скрипт один раз вручную).
Скрипты сборки сбрасывают `SDKROOT`: SDK из Command Line Tools в окружении может не совпадать с компилятором Xcode.

Разработка: `swift build` и консольная утилита для проверки распознавания без интерфейса:

```bash
swift build --product mpxtrans-cli
.build/debug/mpxtrans-cli запись.m4a                       # текст в stdout, ход распознавания в stderr
.build/debug/mpxtrans-cli видео.mov --format srt --lang auto
.build/debug/mpxtrans-cli запись.m4a --model large-v3-russian-q5_0 --no-vad --greedy --prompt "Сбербанк, Анна"
```

Иконку можно открыть и поправить в Icon Composer (Xcode → Open Developer Tool → Icon Composer):
`Resources/AppIcon.icon`.

## Тексты и перевод

Строки в коде написаны по-русски внутри `L("…")` и служат ключами перевода. Английский перевод лежит в
`scripts/l10n/en.json`; `scripts/l10n/make_strings.py` собирает из него `Resources/en.lproj/Localizable.strings`
и останавливает сборку, если у какой-то строки нет перевода или не совпадают `%@`.

## Подпись и Gatekeeper

По умолчанию приложение подписывается ad-hoc, поэтому на других Mac при первом запуске нужно разрешить его в
«Системные настройки → Конфиденциальность и безопасность → Всё равно открыть» (подробно — в `docs/Как установить.txt`).
Чтобы предупреждения не было, нужен сертификат **Developer ID Application** и нотаризация:

```bash
SIGN_IDENTITY="Developer ID Application: Имя (TEAMID)" ./scripts/make_dmg.sh
xcrun notarytool submit dist/MPXTrans-1.0.0.dmg --keychain-profile <профиль> --wait
xcrun stapler staple dist/MPXTrans-1.0.0.dmg
```

## Где что лежит

- `Sources/TransCore` — ffmpeg (`FFmpeg`: сведения о файле, звук 16 кГц), распознавание (`WhisperEngine`, фильтр
  галлюцинаций), форматы результата (`Transcript`: текст с абзацами, таймкоды, SRT), каталог моделей, локализация.
- `Sources/MPXTrans` — интерфейс SwiftUI: `Transcriber` (состояние окна и задача распознавания), `ModelStore`
  (загрузка моделей), `Views/` (зона перетаскивания, прогресс, результат, окно моделей, настройки, стеклянные элементы
  в `Glass.swift`), `DebugHooks` (переменные окружения `MPXTRANS_*` для автоматических проверок интерфейса).
- `Sources/MPXTransCLI` — консольная утилита.
- Модели: `~/Library/Application Support/Subtits/Models/` (общая папка с Subtits). Настройки — в
  `UserDefaults` (`com.mpxtrans.app`). Временные файлы со звуком удаляются сразу после распознавания.

## Лицензии компонентов

whisper.cpp — MIT; модели Whisper — MIT (OpenAI), русские дообученные — см. их страницы на Hugging Face;
Silero VAD — MIT; FFmpeg — сборка GPL (ffmpeg.martin-riedl.de).
