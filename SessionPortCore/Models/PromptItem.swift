import Foundation

struct PromptItem: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var body: String            // supports {{variable}} placeholders
    var attachedFiles: [AttachedFile]
    var isFavorite: Bool
    var createdAt: Date
    var deletedAt: Date?        // non-nil → in Trash

    var isTrashed: Bool { deletedAt != nil }

    init(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        attachedFiles: [AttachedFile] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id; self.title = title; self.body = body
        self.attachedFiles = attachedFiles
        self.isFavorite = isFavorite; self.createdAt = createdAt
        self.deletedAt = deletedAt
    }

    var variables: [String] {
        let pattern = #"\{\{(\w+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(body.startIndex..., in: body)
        return regex.matches(in: body, range: range).compactMap {
            Range($0.range(at: 1), in: body).map { String(body[$0]) }
        }
    }

    func resolved(with values: [String: String]) -> String {
        var result = body
        for (key, value) in values { result = result.replacingOccurrences(of: "{{\(key)}}", with: value) }
        return result
    }

    // Full text for insertion: resolved body + file contents
    func insertionText(variableValues: [String: String] = [:]) -> String {
        var text = resolved(with: variableValues)
        for file in attachedFiles {
            if let content = file.textContent() {
                text += "\n\n---FILE: \(file.name)---\n\(content)\n---END FILE---"
            }
        }
        return text
    }
}

// MARK: - Demo prompts (mirrored from browser extension demo-prompts.json)

extension PromptItem {
    /// Demo prompts in the interface language. Falls back to English.
    static func demos(for code: String) -> [PromptItem] {
        code == "ru" ? demosRU : demosEN
    }

    static let demosEN: [PromptItem] = [
        PromptItem(
            id: "demo_001",
            title: "Context transfer (SessionPort)",
            body: """
            Create a JSON snapshot of our session to transfer via SessionPort.

            Include:
            - Task and goal
            - Decisions made and their rationale
            - Current progress
            - Open questions
            - Next step

            Format: valid JSON, SessionPort schema v1.1.
            """,
            isFavorite: true
        ),
        PromptItem(
            id: "demo_002",
            title: "Code Review",
            body: """
            Do a detailed code review.

            Check:
            1. Critical errors and bugs
            2. Security (injections, data leaks)
            3. Performance
            4. Readability and best practices
            5. Edge case coverage

            For each issue: severity (critical/major/minor), explanation, ready-to-apply fix.
            """,
            isFavorite: true
        ),
        PromptItem(
            id: "demo_003",
            title: "Debug an error",
            body: """
            Find and fix the error:

            {{error or stacktrace}}

            Explain:
            - Why it happens
            - How to fix it (with code)
            - How to avoid it in the future

            Context: {{language / framework}}
            """
        ),
        PromptItem(
            id: "demo_004",
            title: "Data analysis",
            body: """
            Analyze the data and provide a structured report:

            1. Key metrics and indicators
            2. Trends and patterns
            3. Anomalies and outliers
            4. Comparison with baseline values
            5. Conclusions and recommendations

            Use tables where appropriate.
            """
        ),
        PromptItem(
            id: "demo_005",
            title: "Copywriting",
            body: """
            Write a {{type: post/article/email}} for {{product or topic}}.

            Audience: {{target audience}}
            Tone: {{tone: expert/friendly/sales}}
            Length: {{length}}

            Key points:
            {{points}}

            CTA (call to action): {{action}}
            """
        ),
        PromptItem(
            id: "demo_006",
            title: "Meeting summary",
            body: """
            Format a meeting summary in a structured way:

            **Participants:** {{list}}
            **Date:** {{date}}

            **Topics discussed:**
            {{topics}}

            **Decisions made:**
            — ...

            **Action items and owners:**
            | Task | Owner | Deadline |

            **Next meeting:** {{date and format}}
            """
        ),
        PromptItem(
            id: "demo_007",
            title: "Code refactoring",
            body: """
            Refactor the code below without changing its behavior:

            Goals:
            - Improve readability
            - Remove duplication (DRY)
            - Apply patterns where appropriate
            - Optimize performance

            After refactoring, explain each change.
            """,
            isFavorite: true
        ),
    ]

    static let demosRU: [PromptItem] = [
        PromptItem(
            id: "demo_001",
            title: "Перенос контекста (SessionPort)",
            body: """
            Создай JSON-снапшот нашей сессии для переноса через SessionPort.

            Включи:
            - Задача и цель
            - Принятые решения и их обоснование
            - Текущий прогресс
            - Открытые вопросы
            - Следующий шаг

            Формат: валидный JSON, схема SessionPort v1.1.
            """,
            isFavorite: true
        ),
        PromptItem(
            id: "demo_002",
            title: "Code Review",
            body: """
            Проведи детальный code review.

            Проверь:
            1. Критические ошибки и баги
            2. Безопасность (инъекции, утечки данных)
            3. Производительность
            4. Читаемость и соответствие best practices
            5. Покрытие edge cases

            Для каждой проблемы: severity (critical/major/minor), объяснение, готовое исправление.
            """,
            isFavorite: true
        ),
        PromptItem(
            id: "demo_003",
            title: "Отладка ошибки",
            body: """
            Найди и исправь ошибку:

            {{ошибка или стектрейс}}

            Объясни:
            - Почему она возникает
            - Как исправить (с кодом)
            - Как избежать в будущем

            Контекст: {{язык / фреймворк}}
            """
        ),
        PromptItem(
            id: "demo_004",
            title: "Анализ данных",
            body: """
            Проанализируй данные и предоставь структурированный отчёт:

            1. Ключевые метрики и показатели
            2. Тренды и паттерны
            3. Аномалии и выбросы
            4. Сравнение с базовыми значениями
            5. Выводы и рекомендации

            Оформи таблицами там, где уместно.
            """
        ),
        PromptItem(
            id: "demo_005",
            title: "Копирайтинг",
            body: """
            Напиши {{тип текста: пост/статья/письмо}} для {{продукт или тема}}.

            Аудитория: {{целевая аудитория}}
            Тон: {{тон: экспертный/дружелюбный/продающий}}
            Длина: {{длина}}

            Основные тезисы:
            {{тезисы}}

            CTA (призыв к действию): {{действие}}
            """
        ),
        PromptItem(
            id: "demo_006",
            title: "Резюме встречи",
            body: """
            Оформи резюме встречи в структурированном виде:

            **Участники:** {{список}}
            **Дата:** {{дата}}

            **Обсуждаемые темы:**
            {{темы}}

            **Принятые решения:**
            — ...

            **Задачи и ответственные:**
            | Задача | Ответственный | Дедлайн |

            **Следующая встреча:** {{дата и формат}}
            """
        ),
        PromptItem(
            id: "demo_007",
            title: "Рефакторинг кода",
            body: """
            Выполни рефакторинг кода ниже без изменения поведения:

            Цели:
            - Улучшить читаемость
            - Устранить дублирование (DRY)
            - Применить паттерны там, где уместно
            - Оптимизировать производительность

            После рефакторинга объясни каждое изменение.
            """,
            isFavorite: true
        ),
    ]
}
