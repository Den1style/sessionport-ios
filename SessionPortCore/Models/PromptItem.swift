import Foundation

struct PromptItem: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var body: String            // supports {{variable}} placeholders
    var attachedFiles: [AttachedFile]
    var isFavorite: Bool
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        attachedFiles: [AttachedFile] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id; self.title = title; self.body = body
        self.attachedFiles = attachedFiles
        self.isFavorite = isFavorite; self.createdAt = createdAt
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
    static let demos: [PromptItem] = [
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
