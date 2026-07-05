# HANDOFF — что доделать на Mac (после коммита a7930e1)

> Контекст: на Windows-машине смержена ветка `sync-june` и выполнен **пункт 3
> архитектурного плана** — схема `Snapshot` расширена rich-полями v1.1.
> Код написан и вычитан, но **НЕ собирался** — на Windows нет Swift-компилятора.
> Этот файл — чеклист для Mac.

## 1. Собрать и прогнать тесты — ✅ СДЕЛАНО (Mac, 2026-07-05)

Проект в корне репозитория (не в `iOS/`), `.xcodeproj` закоммичен — `xcodegen`
не требуется. Собрано и протестировано на симуляторе **iPhone 17 Pro**
(iPhone 16 в этой системе недоступен):

```bash
xcodebuild test -scheme SessionPort -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

**Результат: `** TEST SUCCEEDED **`, 23/23 теста прошли в 5 сьютах.**
Код пункта 3 компилируется без ошибок — правок не потребовалось. Ключевые
тесты пункта 3, подтверждённые зелёными:
`preservesRichV11Fields`, `parseBrowserBackupWithV11Payload`,
`exportThenImportPreservesRichFields`, `decodesPreRichSchemaStoredJSON`
(обратная совместимость старых снапшотов — главный риск правки).

Затронутые пунктом 3 файлы (для справки, компилируются чисто):

| Файл | Что менялось |
|---|---|
| `SessionPortCore/Models/Snapshot.swift` | +6 полей, custom Codable, richFields-хелперы, fromRawDict v1.1 |
| `SessionPortCore/Models/SnapshotInterchange.swift` | экспорт rich-полей в payload |
| `SessionPortApp/Features/Snapshots/SnapshotDetailView.swift` | 6 новых секций UI |
| `SessionPortTests/SessionPortTests.swift` | 4 новых теста |

## 2. Что именно сделано (пункт 3)

- `Snapshot` получил: `trajectory: String?`, `constraints: [String]`,
  `instructions: [String]`, `openThreads: [String]` (JSON: `open_threads`),
  `artifacts: [String]`, `validation: SnapshotValidation?` (questions/expected).
- **Обратная совместимость**: custom `init(from:)` через `decodeIfPresent` —
  старые снапшоты в App Group читаются без миграции; custom `encode(to:)`
  опускает пустые rich-поля — старые данные кодируются как раньше.
- `fromLLMOutput` парсит все поля v1.1 (раньше выбрасывал).
- `fromRawDict` понимает **оба** диалекта payload:
  - legacy `core/ledger/runtime`
  - v1.1 `dna/decisions/state` — то, что `capture.js` расширения хранит как есть.
    Раньше импорт свежего браузерного бэкапа давал ПУСТЫЕ goal/decisions/state.
- `SnapshotInterchange.exportJSON` эмитит rich-поля рядом с legacy-якорями —
  round-trip iOS ⇄ браузер без потерь.
- `restoreContext` поднят до семантики расширения v1.0.4: подтверждение
  goal+next_step одной строкой, «не выдумывай — спроси», constraints/instructions
  с первого ответа, open_threads как живые задачи, ответ на validation.questions.

## 3. Ручная проверка на симуляторе/устройстве — ⏳ ОСТАЁТСЯ

> Логику схемы покрывают автотесты из п.1 (round-trip, обратная совместимость,
> парсинг v1.1). Ниже — UI-проверки, требующие живого взаимодействия с
> приложением и внешней LLM; их нужно пройти руками.

1. **Старые данные**: если в App Group есть снапшоты со старой схемой —
   открыть Историю, убедиться что всё читается (главный риск правки).
2. **Приём из LLM**: скопировать в буфер v1.1 JSON (сгенерировать промптом
   расширения в Claude/ChatGPT), в клавиатуре нажать Load — открыть деталку,
   проверить новые секции: Траектория, Ограничения, Инструкции,
   Открытые вопросы, Артефакты, Контрольные вопросы.
3. **Импорт браузерного бэкапа**: экспортировать JSON из расширения
   (History → Export), импортировать в iOS — goal/decisions/state должны быть
   заполнены (раньше были пустые для v1.1-payload).
4. **Round-trip**: экспорт из iOS → импорт в расширение → экспорт → импорт в iOS,
   rich-поля не должны теряться.

## 4. Следующая задача — пункт 4 (единый источник промптов)

НЕ начат. Суть: трансферные промпты (`SIMPLE_ANALYZE`, `SIMPLE_CONFIRM`,
`EXTENDED_*`) живут в двух местах и дрейфуют:
- расширение: `popup-shell.js` (~760 строк, 9 языков, функции с transfer_id)
- iOS: `SessionPortKeyboard/UI/TransferView.swift` (en/ru версии)

План: вынести тексты в нейтральный JSON (шаблоны с плейсхолдерами
`{transfer_id}`, `{parent_transfer_id}`, `{today}`, `{json_template}`),
расширение читает напрямую, iOS эмбедит при сборке (добавить в `project.yml`
как ресурс). Теперь это имеет смысл: после пункта 3 схема iOS больше
не обрезает то, что промпт просит у модели.

## 5. Прочее

- Ключевые константы перед сборкой: `kClientID` в GoogleDriveService.swift,
  Bundle ID `com.sessionport.app`, App Group `group.com.sessionport.app`.
- После успешной сборки и тестов — удалить этот файл или обновить под
  следующий handoff.
