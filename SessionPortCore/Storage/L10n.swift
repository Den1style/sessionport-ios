import Foundation

/// Lightweight in-code localization (RU/EN). Works in both the app and the
/// keyboard extension without .strings bundles. Reads the selected language
/// from the shared App Group; falls back to English.
enum L {
    private static var code: String {
        let raw = UserDefaults(suiteName: "group.com.lusine.sessionport")?
            .string(forKey: "sp_language") ?? "system"
        return (AppLanguage(rawValue: raw) ?? .system).code
    }

    static func t(_ key: String) -> String {
        guard let entry = table[key] else { return key }
        return entry[code] ?? entry["en"] ?? key
    }

    // MARK: - String table  [key: [langCode: value]]

    private static let table: [String: [String: String]] = [
        // Common
        "common.cancel":  ["en": "Cancel",  "ru": "Отмена"],
        "common.save":    ["en": "Save",    "ru": "Сохранить"],
        "common.ok":      ["en": "OK",      "ru": "OK"],
        "common.done":    ["en": "Done",    "ru": "Готово"],
        "common.delete":  ["en": "Delete",  "ru": "Удалить"],
        "common.restore": ["en": "Restore", "ru": "Восстановить"],
        "common.close":   ["en": "Close",   "ru": "Закрыть"],

        // Tabs
        "tab.history":  ["en": "History",  "ru": "История"],
        "tab.prompts":  ["en": "Prompts",  "ru": "Промпты"],
        "tab.mindmap":  ["en": "Mind Map", "ru": "Mind Map"],
        "tab.settings": ["en": "Settings", "ru": "Настройки"],

        // Onboarding
        "onb.1.title": ["en": "Add the Keyboard", "ru": "Добавь клавиатуру"],
        "onb.1.body":  ["en": "SessionPort works as a custom keyboard that appears in Claude, ChatGPT, Gemini and other AI apps.",
                        "ru": "SessionPort работает как клавиатура, которая появляется в Claude, ChatGPT, Gemini и других ИИ-приложениях."],
        "onb.2.title": ["en": "Enable in Settings", "ru": "Включи в Настройках"],
        "onb.2.body":  ["en": "Settings → General → Keyboard → Keyboards → Add New Keyboard → SessionPort.\n\nThen tap SessionPort and enable Full Access.",
                        "ru": "Настройки → Основные → Клавиатура → Клавиатуры → Добавить новую клавиатуру → SessionPort.\n\nЗатем нажми SessionPort и включи «Разрешить полный доступ»."],
        "onb.3.title": ["en": "Transfer Context", "ru": "Переноси контекст"],
        "onb.3.body":  ["en": "Open Claude or ChatGPT, tap 🌐 to switch to SessionPort keyboard, and use ⚡ Simple or 🔬 Extended mode to save and load context.",
                        "ru": "Открой Claude или ChatGPT, нажми 🌐 для переключения на SessionPort и используй ⚡ Simple или 🔬 Extended, чтобы сохранять и загружать контекст."],
        "onb.next":    ["en": "Next",          "ru": "Далее"],
        "onb.added":   ["en": "I've added it",  "ru": "Я добавил"],
        "onb.start":   ["en": "Get started",    "ru": "Начать"],
        "onb.openSettings": ["en": "Open Settings", "ru": "Открыть Настройки"],

        // Keyboard setup
        "kb.banner.title": ["en": "Add the keyboard", "ru": "Добавь клавиатуру"],
        "kb.banner.sub":   ["en": "Tap to see the instructions", "ru": "Нажми, чтобы увидеть инструкцию"],
        "kb.sheet.title":  ["en": "Adding the keyboard", "ru": "Добавление клавиатуры"],
        "kb.step1.title":  ["en": "Open Settings", "ru": "Открой Настройки"],
        "kb.step1.body":   ["en": "Tap the button below — it opens iPhone Settings on the right screen.",
                            "ru": "Нажми кнопку ниже — она откроет Настройки iPhone на нужном экране."],
        "kb.step2.title":  ["en": "Add the keyboard", "ru": "Добавь клавиатуру"],
        "kb.step2.body":   ["en": "Settings → General → Keyboard → Keyboards → Add New Keyboard → choose SessionPort.",
                            "ru": "Настройки → Основные → Клавиатура → Клавиатуры → Добавить новую клавиатуру → выбери SessionPort."],
        "kb.step3.title":  ["en": "Enable Full Access", "ru": "Включи полный доступ"],
        "kb.step3.body":   ["en": "Tap SessionPort in the keyboards list and turn on «Allow Full Access». Without it history won't be available.",
                            "ru": "Нажми SessionPort в списке клавиатур и включи «Разрешить полный доступ». Без этого история не будет доступна."],
        "kb.step4.title":  ["en": "Switch in AI apps", "ru": "Переключайся в ИИ-приложениях"],
        "kb.step4.body":   ["en": "In Claude, ChatGPT or Gemini hold 🌐 on the keyboard and pick SessionPort.",
                            "ru": "В Claude, ChatGPT или Gemini зажми 🌐 на клавиатуре и выбери SessionPort."],
        "kb.openKbSettings": ["en": "Open Keyboard Settings", "ru": "Открыть Настройки клавиатуры"],

        // Keyboard extension UI
        "kb.step.analyze":   ["en": "Analyze",  "ru": "Анализ"],
        "kb.step.snapshot":  ["en": "Snapshot", "ru": "Слепок"],
        "kb.step.prepare":   ["en": "Prepare",  "ru": "Подготовка"],
        "kb.step.anchors":   ["en": "Anchors",  "ru": "Якоря"],
        "kb.step.save":      ["en": "Save",     "ru": "Сохранить"],
        "kb.back":           ["en": "Back",     "ru": "Назад"],
        "kb.history.header": ["en": "SNAPSHOT HISTORY", "ru": "ИСТОРИЯ СНЭПШОТОВ"],
        "kb.history.empty":  ["en": "No snapshots",     "ru": "Нет снэпшотов"],
        "kb.project.new":    ["en": "＋ New",            "ru": "＋ Новый"],

        // Snapshots / History
        "snap.title":        ["en": "History", "ru": "История"],
        "snap.search":       ["en": "Search snapshots", "ru": "Поиск снэпшотов"],
        "snap.empty.title":  ["en": "No snapshots", "ru": "Нет снэпшотов"],
        "snap.empty.desc":   ["en": "Use the SessionPort keyboard to capture context",
                              "ru": "Используй клавиатуру SessionPort для захвата контекста"],
        "snap.notfound":     ["en": "Nothing found", "ru": "Ничего не найдено"],
        "snap.notfound.desc":["en": "Try another query", "ru": "Попробуй другой запрос"],
        "snap.all":          ["en": "All", "ru": "Все"],
        "snap.export":       ["en": "Export JSON", "ru": "Экспорт JSON"],
        "snap.import":       ["en": "Import JSON", "ru": "Импорт JSON"],
        "snap.buffer":       ["en": "Buffer:", "ru": "Буфер:"],
        "snap.importError":  ["en": "Import error", "ru": "Ошибка импорта"],
        "proj.rename":       ["en": "Rename project", "ru": "Переименовать проект"],
        "proj.name":         ["en": "Project name", "ru": "Имя проекта"],

        // Prompts
        "prompts.title":     ["en": "Prompts", "ru": "Промпты"],
        "prompts.search":    ["en": "Search prompts", "ru": "Поиск промптов"],
        "prompts.empty":     ["en": "No prompts", "ru": "Нет промптов"],
        "prompts.trash":     ["en": "Trash", "ru": "Корзина"],
        "prompt.text":       ["en": "Text", "ru": "Текст"],
        "prompt.variables":  ["en": "Variables", "ru": "Переменные"],
        "prompt.preview":    ["en": "Preview", "ru": "Предпросмотр"],
        "prompt.files":      ["en": "Files", "ru": "Файлы"],
        "prompt.attach":     ["en": "Attach file", "ru": "Прикрепить файл"],
        "prompt.copy":       ["en": "Copy & paste", "ru": "Скопировать и вставить"],
        "prompt.copied":     ["en": "Copied ✓", "ru": "Скопировано ✓"],
        "prompt.favorite":   ["en": "Favorite", "ru": "Избранное"],
        "prompt.value":      ["en": "value", "ru": "значение"],
        "prompt.new.title":  ["en": "New prompt", "ru": "Новый промпт"],
        "prompt.new.name":   ["en": "Name", "ru": "Название"],
        "prompt.new.nameField": ["en": "Prompt name", "ru": "Название промпта"],
        "prompt.new.bodyHeader": ["en": "Text (use {{variable}} for placeholders)",
                                  "ru": "Текст (используй {{переменная}} для плейсхолдеров)"],
        "prompt.delete.title": ["en": "Delete prompt?", "ru": "Удалить промпт?"],
        "prompt.delete.msg":   ["en": "It will be moved to Trash.", "ru": "Промпт будет перемещён в корзину."],
        "prompt.fileLimit":    ["en": "exceeds the 5 MB limit", "ru": "превышает лимит 5 МБ"],
        "prompt.fileError":    ["en": "File error", "ru": "Ошибка файла"],

        // File delete confirm
        "file.delete.title": ["en": "Remove file?", "ru": "Удалить файл?"],
        "file.delete.msg":   ["en": "The attachment will be removed.", "ru": "Вложение будет удалено."],

        // Trash (shared)
        "trash.title":        ["en": "Trash", "ru": "Корзина"],
        "trash.empty.title":  ["en": "Trash is empty", "ru": "Корзина пуста"],
        "trash.snap.empty":   ["en": "Deleted snapshots appear here", "ru": "Удалённые снэпшоты появятся здесь"],
        "trash.prompt.empty": ["en": "Deleted prompts appear here", "ru": "Удалённые промпты появятся здесь"],
        "trash.clear":        ["en": "Empty", "ru": "Очистить"],
        "trash.clear.title":  ["en": "Empty Trash?", "ru": "Очистить корзину?"],
        "trash.clear.msg":    ["en": "This action cannot be undone.", "ru": "Это действие необратимо."],
        "trash.deletedAgo":   ["en": "Deleted", "ru": "Удалено"],
        "trash.deleteForever":["en": "Delete forever", "ru": "Удалить навсегда"],

        // Settings
        "settings.title":         ["en": "Settings", "ru": "Настройки"],
        "settings.appearance":    ["en": "Appearance", "ru": "Оформление"],
        "settings.theme":         ["en": "Theme", "ru": "Тема"],
        "settings.theme.system":  ["en": "System", "ru": "Системная"],
        "settings.theme.light":   ["en": "Light", "ru": "Светлая"],
        "settings.theme.dark":    ["en": "Dark", "ru": "Тёмная"],
        "settings.language":      ["en": "Language", "ru": "Язык"],
        "settings.language.system": ["en": "System", "ru": "Системный"],
        "settings.keyboard":      ["en": "Keyboard", "ru": "Клавиатура"],
        "settings.keyboard.howto":["en": "How to add the keyboard", "ru": "Как добавить клавиатуру"],
        "settings.subscription":  ["en": "Subscription", "ru": "Подписка"],
        "settings.pro.active":    ["en": "SessionPort Pro — Active", "ru": "SessionPort Pro — Активна"],
        "settings.pro.upgrade":   ["en": "Upgrade to Pro", "ru": "Перейти на Pro"],
        "settings.restore":       ["en": "Restore purchases", "ru": "Восстановить покупки"],
        "settings.gdrive":        ["en": "Google Drive", "ru": "Google Drive"],
        "settings.connected":     ["en": "Connected", "ru": "Подключено"],
        "settings.lastSync":      ["en": "Last sync", "ru": "Последняя синхронизация"],
        "settings.backup":        ["en": "Create backup", "ru": "Создать резервную копию"],
        "settings.restoreDrive":  ["en": "Restore from Drive", "ru": "Восстановить из Drive"],
        "settings.disconnect":    ["en": "Disconnect", "ru": "Отключить"],
        "settings.connectDrive":  ["en": "Connect Google Drive", "ru": "Подключить Google Drive"],
        "settings.drive.note":    ["en": "Reads SessionPort backups. Your files only.",
                                   "ru": "Читает резервные копии SessionPort. Только ваши файлы."],
        "settings.about":         ["en": "About", "ru": "О приложении"],
        "settings.version":       ["en": "Version", "ru": "Версия"],
        "settings.drive.error":   ["en": "Google Drive error", "ru": "Ошибка Google Drive"],
    ]
}
