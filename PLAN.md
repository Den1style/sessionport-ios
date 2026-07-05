# SessionPort iOS — Plan

## Архитектура

```
SessionPort.xcodeproj
├── SessionPortApp/          ← Host App (target 1)
│   ├── App/
│   │   ├── SessionPortApp.swift
│   │   └── ContentView.swift
│   ├── Features/
│   │   ├── Onboarding/
│   │   ├── Snapshots/
│   │   └── Settings/
│   └── Services/
│       ├── GoogleDriveService.swift
│       └── StoreKitService.swift
│
├── SessionPortKeyboard/     ← Keyboard Extension (target 2)
│   ├── KeyboardViewController.swift
│   └── UI/
│       ├── KeyboardPanelView.swift
│       ├── TransferView.swift
│       ├── PromptsView.swift
│       └── HistoryView.swift
│
└── SessionPortCore/         ← Shared framework / App Group
    ├── Models/
    │   ├── Snapshot.swift
    │   ├── PromptItem.swift
    │   └── TransferMode.swift
    └── Storage/
        └── SharedStorage.swift
```

## App Group & Bundle IDs

| Target | Bundle ID |
|--------|-----------|
| Host App | `com.sessionport.app` |
| Keyboard Extension | `com.sessionport.app.keyboard` |
| App Group | `group.com.sessionport.app` |

## Snapshot — модель данных

```swift
struct Snapshot: Codable, Identifiable {
    let id: String           // transfer_id
    var parentId: String?    // parent_transfer_id
    var title: String
    var goal: String
    var decisions: [String]
    var rejected: [String]
    var state: String
    var nextStep: String
    var llmSource: String    // "claude" | "chatgpt" | "gemini" ...
    var createdAt: Date
}
```

Маркеры при вставке:
```
---BEGIN CONTEXT---
{JSON снэпшота}
---END CONTEXT---
```

## LLM-приложения (hostBundleID)

```swift
let llmBundleIDs: Set<String> = [
    "com.anthropic.claudeios",      // Claude
    "com.openai.chat",              // ChatGPT
    "com.google.Bard",              // Gemini
    "ai.perplexity.perplexity-ios", // Perplexity
    "com.x.twitter",                // Grok (через Twitter)
    "ai.mistral.ios",               // Mistral
]
```

## UI клавиатуры — состояния

```
[collapsed — не LLM]  →  серая полоска "——— ∨ ———"
                          тап → toast "Работает только в LLM-приложениях"

[collapsed — LLM]     →  зелёная полоска "——— ∨ ———"
                          тап → expanded

[expanded]            →  полная панель:
  ┌─────────────────────────────────────┐
  │ 🕐  [Transfer] [Prompts]  [Claude▼] ∧│  ← Header
  ├─────────────────────────────────────┤
  │                                     │
  │  ⚡ Simple    🔬 Extended            │  ← Transfer tab (mode select)
  │                                     │
  └─────────────────────────────────────┘

  После выбора режима:
  ┌─────────────────────────────────────┐
  │ 🕐  [Transfer] [Prompts]  [Claude▼] ∧│
  ├─────────────────────────────────────┤
  │ ← Back                              │
  │                                     │
  │  Step 1: [Save & Send ⚡]           │  Simple
  │  Step 2: [Load ↑]                   │
  │                                     │
  └─────────────────────────────────────┘
```

## Фазы реализации

### Фаза 1 — Фундамент (Task 1, 2)
- Xcode проект, два таргета, App Group
- Snapshot.swift, SharedStorage.swift
- Проверка передачи данных через App Group

### Фаза 2 — Keyboard Extension (Task 4, 5, 6)
- UIInputViewController с LLM-детектором
- Collapsed / expanded анимации
- Header, Transfer tab (Simple + Extended), Prompts tab, History

### Фаза 3 — Google Drive (Task 3)
- ASWebAuthenticationSession OAuth
- Чтение "SessionPort Backups" папки
- Парсинг JSON → Snapshot[], сохранение в SharedStorage
- Фоновая синхронизация (Background App Refresh)

### Фаза 4 — Host App (Task 7)
- Онбординг: инструкция по добавлению клавиатуры
- Список снэпшотов с поиском
- Экран настроек: Google аккаунт, интервал синхронизации

### Фаза 5 — Монетизация (Task 8)
- StoreKit 2 подписка $4.99/мес
- Лимит: 5 снэпшотов бесплатно
- Paywall при превышении лимита
- Разблокировка истории и cross-device sync для Pro

## Google Drive — iOS OAuth flow

```
1. ASWebAuthenticationSession → accounts.google.com/o/oauth2/auth
   scope: https://www.googleapis.com/auth/drive.file
   redirect: com.sessionport.app://oauth

2. Получить code → обменять на access_token + refresh_token
   POST https://oauth2.googleapis.com/token

3. Сохранить refresh_token в Keychain (не UserDefaults!)

4. Читать папку "SessionPort Backups":
   GET /drive/v3/files?q='folder_id' in parents
   → список sessionport-backup-*.json

5. Скачать последний → распарсить → сохранить снэпшоты
```

## Ключевые технические решения

- **Shared data**: UserDefaults с App Group suite — доступен из extension и host app без XPC
- **OAuth токены**: только Keychain, никогда UserDefaults
- **textDocumentProxy**: `insertText()` для вставки контекста в поле ввода LLM
- **hostBundleID**: `textInputMode?.primaryLanguage` для iOS < 16, `inputView?.window?.rootViewController` для определения приложения
- **SwiftUI в extension**: `UIHostingController` внутри `UIInputViewController`
- **StoreKit 2**: `Product.subscription.status` для проверки активной подписки

## Файлы для создания (порядок)

1. `SessionPortCore/Models/Snapshot.swift`
2. `SessionPortCore/Models/PromptItem.swift`
3. `SessionPortCore/Storage/SharedStorage.swift`
4. `SessionPortKeyboard/KeyboardViewController.swift`
5. `SessionPortKeyboard/UI/KeyboardPanelView.swift`
6. `SessionPortKeyboard/UI/TransferView.swift`
7. `SessionPortKeyboard/UI/PromptsView.swift`
8. `SessionPortKeyboard/UI/HistoryView.swift`
9. `SessionPortApp/Services/GoogleDriveService.swift`
10. `SessionPortApp/Services/StoreKitService.swift`
11. `SessionPortApp/App/ContentView.swift`
12. `SessionPortApp/Features/Onboarding/OnboardingView.swift`
13. `SessionPortApp/Features/Settings/SettingsView.swift`
