import SwiftUI

struct TransferView: View {
    @Binding var flowState: TransferFlowState
    let llmName: String
    let onInsertText: (String) -> Void

    var body: some View {
        Group {
            switch flowState {
            case .modeSelection:      modeSelection
            case .inProgress(let m, let s): stepsView(mode: m, step: s)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    // MARK: Mode cards — match mockup exactly

    private var modeSelection: some View {
        HStack(spacing: 10) {
            ModeCard(
                icon: "⚡", title: "Simple",
                subtitle: "3 шага · быстро",
                bg: Color(red: 0.22, green: 0.14, blue: 0.02),
                accent: Color(red: 1.0, green: 0.75, blue: 0.1)
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    flowState = .inProgress(mode: .simple, step: 0)
                }
            }
            ModeCard(
                icon: "🔬", title: "Extended",
                subtitle: "4 шага · полный контроль",
                bg: Color(red: 0.12, green: 0.1, blue: 0.28),
                accent: Color(red: 0.6, green: 0.5, blue: 1.0)
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    flowState = .inProgress(mode: .extended, step: 0)
                }
            }
        }
    }

    // MARK: Steps

    private func stepsView(mode: TransferMode, step: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { flowState = .modeSelection }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                    Text("Back").font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            let cols = mode.steps.count <= 3
                ? Array(repeating: GridItem(.flexible(), spacing: 5), count: mode.steps.count)
                : [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)]

            LazyVGrid(columns: cols, spacing: 5) {
                ForEach(Array(mode.steps.enumerated()), id: \.offset) { i, s in
                    StepButton(
                        title: s.title,
                        index: i,
                        state: i < step ? .done : i == step ? .active : .waiting
                    ) { handleStep(mode: mode, index: i, currentStep: step) }
                }
            }

            // Status hint — prevents premature capture (empty template issue)
            // User must wait for LLM to respond before tapping the next step
            if step < mode.steps.count {
                let hints: [String] = mode == .simple
                    ? [
                        "↑ Вставлено — отправь LLM и дождись ответа",
                        "↑ Вставлено — скопируй JSON из ответа LLM",
                        "Вставит сохранённый снэпшот в новый LLM",
                      ]
                    : [
                        "↑ Вставлено — отправь и дождись ответа",
                        "↑ Вставлено — проверь 6 якорей с LLM",
                        "↑ Вставлено — скопируй JSON из ответа LLM",
                        "Вставит сохранённый снэпшот в новый LLM",
                      ]
                if step < hints.count {
                    Text(hints[step])
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    // MARK: Logic

    private func handleStep(mode: TransferMode, index: Int, currentStep: Int) {
        guard index == currentStep else { return }
        let storage = SharedStorage.shared

        switch mode {
        case .simple:
            switch index {
            case 0:
                // Step 1: insert SIMPLE_ANALYZE prompt → user sends to LLM
                onInsertText(analyzePrompt)
                advance(mode: mode, from: index)
            case 1:
                // Step 2: insert SIMPLE_CONFIRM prompt → user sends, copies JSON from LLM response
                onInsertText(confirmPrompt)
                advance(mode: mode, from: index)
            default:
                // Step 3: load last saved snapshot into new LLM
                guard storage.canAddSnapshot else { return }
                let snap = makeSnapshot()
                storage.addSnapshot(snap)
                if let latest = storage.snapshots.first { onInsertText(latest.contextText()) }
                flowState = .modeSelection
            }

        case .extended:
            switch index {
            case 0:
                // Step 1: preparation prompt (same as analyze)
                onInsertText(analyzePrompt)
                advance(mode: mode, from: index)
            case 1:
                // Step 2: anchor validation — copy analyze prompt again for deeper pass
                onInsertText("""
                Проверь 6 якорей переноса SessionPort:
                1. ЦЕЛЬ — сформулирована как инструкция-продолжение?
                2. РЕШЕНИЯ — все [ОТКЛОНЕНО] задокументированы с причиной?
                3. СОСТОЯНИЕ — текущая задача и следующий шаг ясны?
                4. НЕЯВНЫЕ ЗАПРЕТЫ — что я перестал предлагать и почему?
                5. ИНСТРУКЦИИ — 3–5 конкретных правил для новой модели?
                6. ДНА — стек, ограничения, стиль общения зафиксированы?

                Для каждого якоря: ✅ готово / ⚠️ нужно уточнить / ❌ отсутствует.
                Дополни пропущенное перед генерацией слепка.
                """)
                advance(mode: mode, from: index)
            case 2:
                // Step 3: generate JSON snapshot
                onInsertText(confirmPrompt)
                advance(mode: mode, from: index)
            default:
                // Step 4: load into new LLM
                guard storage.canAddSnapshot else { return }
                let snap = makeSnapshot()
                storage.addSnapshot(snap)
                if let latest = storage.snapshots.first { onInsertText(latest.contextText()) }
                flowState = .modeSelection
            }
        }
    }

    private func advance(mode: TransferMode, from i: Int) {
        let next = i + 1
        withAnimation(.spring(response: 0.22)) {
            flowState = next < mode.steps.count
                ? .inProgress(mode: mode, step: next)
                : .modeSelection
        }
    }

    private func makeSnapshot() -> Snapshot {
        Snapshot(
            id: UUID().uuidString,
            parentId: SharedStorage.shared.snapshots.first?.id,
            title: "Context \(Date().formatted(date: .abbreviated, time: .shortened))",
            goal: "", decisions: [], rejected: [],
            state: "ACTIVE", nextStep: "",
            llmSource: llmName.isEmpty ? "unknown" : llmName.lowercased(),
            createdAt: Date()
        )
    }

    // SIMPLE_ANALYZE — ported from browser extension popup-shell.js
    // Inserted into LLM at step 1 (Simple) and step 2 (Extended)
    private var analyzePrompt: String {
        let id = UUID().uuidString.lowercased()
        return """
        ПРОТОКОЛ SessionPort — ПРОСТОЙ ПЕРЕНОС.

        Сначала ответь на один вопрос: что из нашей текущей переписки будет ПОТЕРЯНО при переносе? Для каждого пункта: критично / допустимо / неважно. В слепок войдёт только критичное.

        Затем выведи строго по секциям:

        ## DNA ПРОЕКТА
        - Домен, стек, цель — одно предложение-инструкция (глагол + задача + приоритет)
        - Язык и стиль общения пользователя (лаконичный/многословный, рус/англ)
        - Глобальные ограничения (технологии, запреты, дедлайны)

        ## РЕШЕНИЯ
        Каждый пункт отдельной строкой. Причина и контекст обязательны:
        [ПРИНЯТО] что именно — потому что причина — при каких обстоятельствах
        [ОТКЛОНЕНО] что именно — потому что причина — почему никогда не предлагать снова
        [ПРАВИЛО] что именно — потому что причина
        Минимум 3, лучше 5–10. Включи ВСЕ реальные [ОТКЛОНЕНО] — всё что пробовали и явно отвергли. НЕ придумывай отклонения. Если их не было — пропусти [ОТКЛОНЕНО] полностью.

        ## СОСТОЯНИЕ
        Последние 3–5 действий · что работает / что сломано / что в процессе · следующий шаг.

        ## НЕЯВНЫЕ ЗАПРЕТЫ
        Что ты перестал предлагать в этой сессии потому что пользователь молча не принимал? (implicit negative feedback — самое ценное что теряется при переносе)

        ## ИНСТРУКЦИИ ДЛЯ НОВОЙ МОДЕЛИ
        3–5 правил: «Если [X] → [Y]» или «Всегда/Никогда [Z] — потому что [причина]».
        """
    }

    // SIMPLE_CONFIRM — ported from browser extension popup-shell.js
    // Inserted at step 2 (Simple) to generate the actual JSON snapshot
    private var confirmPrompt: String {
        let id = UUID().uuidString.lowercased()
        return """
        ПРОТОКОЛ SessionPort — ГЕНЕРАЦИЯ СЛЕПКА.

        Проанализируй нашу переписку в этом чате и сформируй JSON-слепок. Подставь реальные данные из нашего диалога вместо «…». transfer_id ниже — уникальная метка, просто скопируй в meta.transfer_id как есть:

        ```json
        {"meta":{"protocol":"SessionPort","transfer_id":"\(id)","project":"…","version":"1.1","date":"YYYY-MM-DD"},"dna":{"goal":"инструкция-продолжение (глагол+задача+приоритет)","language":"ru","style":"…","constraints":["…"]},"decisions":[{"what":"…","why":"причина","context":"при каких обстоятельствах","type":"accepted"},{"what":"…","why":"причина","context":"что пробовали и явно отвергли","type":"rejected"},{"what":"…","why":"причина","context":"","type":"rule"}],"state":{"current_task":"…","last_actions":["…","…","…"],"next_step":"…"},"instructions":["Если X → Y","Всегда Z при W","Никогда Q — потому что R"]}
        ```

        или ---BEGIN CONTEXT---{…}---END CONTEXT---

        КРИТИЧНО: Все данные — из нашей переписки выше.
        decisions — минимум 3, включая type:"rejected". Каждое с непустым "why".
        meta.transfer_id = "\(id)" — символ-в-символ.
        Первый символ {. Последний }. Только JSON, без пояснений.
        """
    }
}

// MARK: - ModeCard

struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let bg: Color
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(icon).font(.system(size: 28))
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(accent.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(bg, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StepButton

enum StepButtonState { case waiting, active, done }

struct StepButton: View {
    let title: String
    let index: Int
    let state: StepButtonState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(dotColor).frame(width: 20, height: 20)
                    if state == .done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(state == .active ? .white : .secondary)
                    }
                }
                Text(title)
                    .font(.system(size: 12, weight: state == .active ? .semibold : .regular))
                    .foregroundStyle(state == .waiting ? .secondary : .primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(state == .active
                          ? Color.accentColor.opacity(0.13)
                          : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(state == .active ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(state == .waiting)
        .opacity(state == .waiting ? 0.45 : 1)
    }

    private var dotColor: Color {
        switch state {
        case .waiting: .secondary.opacity(0.3)
        case .active:  .accentColor
        case .done:    .green
        }
    }
}
