# TESTFLIGHT — как залить сборку (для человека с Apple Developer аккаунтом)

Состояние проекта на момент написания (проверено на Mac, 2026-07-13):

- Release-архив собирается чисто (`** ARCHIVE SUCCEEDED **`), 31/31 тест зелёный.
- Версия **1.0.0**, build **1** (`CFBundleShortVersionString` / `CFBundleVersion`).
- Экспортный контроль уже проставлен: `ITSAppUsesNonExemptEncryption = false`
  (Info.plist) — Apple не будет спрашивать про шифрование.
- **Иконка есть** — `SessionPortApp/Assets.xcassets/AppIcon.appiconset`
  (1024×1024, взята из браузерного расширения). Хочешь резче — замени
  `AppIcon-1024.png` своим 1024×1024 (без альфа-канала!) и пересобери.
- Клавиатура-расширение вшита, `RequestsOpenAccess = true`.

## Идентификаторы (НЕ менять — под них заводить App ID)

| Что | Значение |
|---|---|
| App bundle ID | `com.lusine.sessionport` |
| Keyboard bundle ID | `com.lusine.sessionport.keyboard` |
| App Group | `group.com.lusine.sessionport` |
| Keychain group | `$(AppIdentifierPrefix)com.lusine.sessionport` |
| Версия / build | `1.0.0` / `1` |

> `project.yml` — источник правды (проект генерится `xcodegen`). Если правишь
> идентификаторы — правь `project.yml` и запускай `xcodegen generate`, не
> редактируй `.xcodeproj` руками.

## Шаг 0. Инструменты (один раз)

```bash
brew install xcodegen           # если правишь project.yml
# xcodebuild/altool идут с Xcode
```

## Шаг 1. Твой Team ID и подпись

Вариант А — через `project.yml` (рекомендуется):
1. В `project.yml` у таргетов `SessionPort` и `SessionPortKeyboard` заполнить
   `DEVELOPMENT_TEAM: "ВАШ_TEAM_ID"` (сейчас пусто).
2. `xcodegen generate`.

Вариант Б — в Xcode: открыть проект, для обоих таргетов на вкладке
Signing & Capabilities выбрать свою Team (Automatically manage signing).

## Шаг 2. Регистрация в Apple Developer (developer.apple.com)

1. **Identifiers → App IDs**: создать `com.lusine.sessionport` и
   `com.lusine.sessionport.keyboard`, у обоих включить capability **App Groups**.
2. **Identifiers → App Groups**: создать `group.com.lusine.sessionport`,
   привязать к обоим App ID.
3. Distribution-сертификат Xcode заведёт сам при Automatic signing (или создать
   вручную: Certificates → Apple Distribution).

## Шаг 3. App Store Connect (appstoreconnect.apple.com)

1. **My Apps → +** → New App: платформа iOS, bundle ID `com.lusine.sessionport`,
   имя «SessionPort», SKU любой. (Иконку 1024 App Store Connect подтянет из сборки.)
2. **Users and Access → Integrations → App Store Connect API → +**: создать ключ
   (роль App Manager достаточно). Скачать `.p8`, запомнить **Issuer ID** и **Key ID**.
   Положить файл в `~/.appstoreconnect/private_keys/AuthKey_KEYID.p8`.

## Шаг 4. Собрать, экспортировать, залить

Заполни `ExportOptions.plist` → `teamID` своим Team ID. Затем:

```bash
cd <репозиторий>

# 1. Архив (подписанный — Team ID уже задан в проекте)
xcodebuild archive \
  -scheme SessionPort \
  -destination 'generic/platform=iOS' \
  -archivePath build/SessionPort.xcarchive

# 2. Экспорт .ipa для App Store
xcodebuild -exportArchive \
  -archivePath build/SessionPort.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export

# 3. Загрузка в App Store Connect / TestFlight
xcrun altool --upload-app -t ios \
  -f build/export/SessionPort.ipa \
  --apiKey KEYID --apiIssuer ISSUER_ID
```

Через несколько минут сборка появится в App Store Connect → TestFlight
(статус «Processing» → потом доступна тестировщикам). Первый раз попросит
заполнить Test Information и, для внешних тестировщиков, пройти Beta App Review.

## Шаг 5. Следующие сборки

Поднимай **build number** перед каждой загрузкой (номер должен расти):
в `project.yml` добавить `CURRENT_PROJECT_VERSION` или в Xcode менять Build.
`MARKETING_VERSION` (1.0.0) меняется только при смене публичной версии.

## Известные нюансы

- **Google Drive синк**: `kClientID` в `GoogleDriveService.swift` — реальный
  OAuth-клиент. Чтобы синк работал на твоей подписи, в Google Cloud Console у
  этого OAuth-клиента должен быть зарегистрирован iOS bundle ID
  `com.lusine.sessionport`. Если клиент чужой — заведи свой iOS OAuth client и
  подставь его ID.
- **Иконка** мягковата (апскейл 128→1024 из расширения). Для релиза лучше
  подложить векторно-чёткий 1024×1024.
- Сборка/тесты гоняются на симуляторе `iPhone 17 Pro` (в этой среде нет
  `iPhone 16`); для архива это неважно — он `generic/platform=iOS`.
