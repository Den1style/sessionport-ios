import SwiftUI
import UIKit

struct TransferView: View {
    @Binding var flowState: TransferFlowState
    let llmName: String
    let targetProject: String          // "" == new project (LLM names it)
    let onInsertText: (String) -> Void

    // Set when the Load step finds no valid JSON in the clipboard, so we show a
    // hint instead of fabricating and inserting an empty template.
    @State private var loadFailed = false
    // Distinguishes "clipboard empty" (likely Full Access off) from "not JSON"
    @State private var clipWasEmpty = false
    // Shows the "snapshot saved" confirmation on the mode-selection screen
    @State private var savedOK = false
    // True when the pasteboard changed after the snapshot prompt was inserted —
    // the user copied the LLM reply, so the Save step lights up green.
    @State private var clipReady = false

    var body: some View {
        Group {
            switch flowState {
            case .modeSelection:      modeSelection
            case .inProgress(let m, let s):
                stepsView(mode: m, step: s)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: Mode cards — centered, fixed height (balanced spacing, no bottom void)

    private var modeSelection: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            if savedOK { savedBanner }
            cards.frame(height: 132)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Confirmation after the Save step — the snapshot is in the app; nothing was
    // typed into the chat. Auto-hides.
    private var savedBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
            Text(SharedStorage.shared.kbLangCode == "en"
                 ? "Snapshot saved — insert it into a new chat via History (clock icon)"
                 : "Снэпшот сохранён — вставить в новый чат можно из Истории (значок часов)")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1), in: Capsule())
        .task {
            try? await Task.sleep(for: .seconds(6))
            withAnimation { savedOK = false }
        }
    }

    private var cards: some View {
        let isEn = SharedStorage.shared.kbLangCode == "en"
        return HStack(spacing: 10) {
            ModeCard(
                icon: "⚡", title: "Simple",
                subtitle: isEn ? "3 steps · fast" : "3 шага · быстро",
                bg: Color(red: 0.22, green: 0.14, blue: 0.02),
                accent: Color(red: 1.0, green: 0.75, blue: 0.1)
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    flowState = .inProgress(mode: .simple, step: 0)
                }
            }
            ModeCard(
                icon: "🔬", title: "Extended",
                subtitle: isEn ? "4 steps · full control" : "4 шага · полный контроль",
                bg: Color(red: 0.12, green: 0.1, blue: 0.28),
                accent: Color(red: 0.6, green: 0.5, blue: 1.0)
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    flowState = .inProgress(mode: .extended, step: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Steps

    private func stepsView(mode: TransferMode, step: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { flowState = .modeSelection }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                    Text(L.t("kb.back")).font(.system(size: 12))
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
                        state: i < step ? .done : i == step ? .active : .waiting,
                        ready: clipReady && i == step && i == mode.steps.count - 1
                    ) { handleStep(mode: mode, index: i, currentStep: step) }
                }
            }

            // Status hint — prevents premature capture (empty template issue)
            // User must wait for LLM to respond before tapping the next step
            if step < mode.steps.count {
                let isEn = SharedStorage.shared.kbLangCode == "en"
                let hints: [String] = mode == .simple
                    ? (isEn
                       ? [
                           "↑ Inserted — send to the LLM and wait for its reply",
                           "↑ Inserted — copy the JSON from the LLM's reply",
                           "Saves the snapshot from the clipboard into the app",
                         ]
                       : [
                           "↑ Вставлено — отправь LLM и дождись ответа",
                           "↑ Вставлено — скопируй JSON из ответа LLM",
                           "Сохранит снэпшот из буфера в приложение",
                         ])
                    : (isEn
                       ? [
                           "↑ Inserted — answer the LLM's clarifying questions, then say \"ready\"",
                           "↑ Inserted — review the 5 verification layers with the LLM",
                           "↑ Inserted — copy the JSON from the LLM's reply",
                           "Saves the snapshot from the clipboard into the app",
                         ]
                       : [
                           "↑ Вставлено — ответь на уточняющие вопросы LLM, затем скажи «готово»",
                           "↑ Вставлено — проверь 5 слоёв с LLM",
                           "↑ Вставлено — скопируй JSON из ответа LLM",
                           "Сохранит снэпшот из буфера в приложение",
                         ])
                if step < hints.count {
                    let isLast = step == mode.steps.count - 1
                    Group {
                        if isLast && loadFailed {
                            Text(clipWasEmpty
                                 ? (isEn
                                    ? "⚠️ Clipboard is empty. Copy the LLM reply and check the keyboard's Full Access."
                                    : "⚠️ Буфер пуст. Скопируй ответ LLM и проверь «Полный доступ» у клавиатуры.")
                                 : (isEn
                                    ? "⚠️ No valid JSON in the clipboard. Copy the LLM's JSON reply and tap again."
                                    : "⚠️ В буфере нет валидного JSON. Скопируй JSON-ответ LLM и нажми снова."))
                                .foregroundStyle(Color.orange)
                        } else if isLast && clipReady {
                            Text(isEn
                                 ? "✓ Clipboard ready — tap \"Save\""
                                 : "✓ Буфер готов — нажми «Сохранить»")
                                .foregroundStyle(Color.green)
                        } else if isLast {
                            copyHint(isEn: isEn)
                        } else {
                            Text(hints[step]).foregroundStyle(Color.secondary)
                        }
                    }
                    .font(.system(size: 9.5, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            }
        }
        // Poll pasteboard METADATA (changeCount/hasStrings — never the contents,
        // so no system paste banner) while the Save step is active.
        .task(id: step) {
            guard step == mode.steps.count - 1 else {
                clipReady = false
                return
            }
            while !Task.isCancelled {
                refreshClipReady()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // Visual "where to tap" hint: a mini replica of the copy button that chat
    // apps show under the LLM's reply (two overlapping squares).
    private func copyHint(isEn: Bool) -> some View {
        HStack(spacing: 5) {
            Text(isEn ? "Under the LLM reply tap" : "Под ответом LLM нажми")
                .foregroundStyle(Color.secondary)
            HStack(spacing: 3) {
                Image(systemName: "square.on.square").font(.system(size: 9, weight: .semibold))
                Text(isEn ? "Copy" : "Копировать")
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            Text(isEn ? "— then \"Save\"" : "— затем «Сохранить»")
                .foregroundStyle(Color.secondary)
        }
    }

    private func refreshClipReady() {
        let pb = UIPasteboard.general
        let stored = SharedStorage.shared.kbClipCountAtPrompt
        let ready = pb.hasStrings && stored != -1 && pb.changeCount != stored
        if ready != clipReady {
            withAnimation(.easeInOut(duration: 0.2)) { clipReady = ready }
        }
    }

    // MARK: Logic

    // Stable transfer_id for the whole session (generated once, persisted,
    // reused in every prompt and as the saved snapshot id — like the browser).
    private func sessionTransferId() -> String {
        let s = SharedStorage.shared
        if let id = s.kbTransferId { return id }
        let id = TransferFlowState.generateTransferId()
        s.kbTransferId = id
        return id
    }

    // parent_transfer_id = head of the SAME project (inheritance is per-project,
    // matching the browser, where switching project sets active to that project's
    // head). `activeSnapshots` is newest-first, so .first(where:) is the head.
    private func projectHead(_ project: String?) -> String? {
        SharedStorage.shared.activeSnapshots.first { $0.project == project }?.id
    }

    // Selected existing project, or nil when "＋ Новый" (start a fresh chain).
    private var effectiveProject: String? {
        (targetProject.isEmpty || targetProject == "__new__") ? nil : targetProject
    }

    // Parent priority: an explicit fork target (chosen on the Mind Map) wins;
    // otherwise the head of the selected project; a new project has no parent.
    private var parentTransferId: String? {
        if let fork = SharedStorage.shared.kbForkParentId { return fork }
        guard let p = effectiveProject else { return nil }
        return projectHead(p)
    }

    private func handleStep(mode: TransferMode, index: Int, currentStep: Int) {
        guard index == currentStep else { return }
        let storage = SharedStorage.shared

        switch mode {
        case .simple:
            switch index {
            case 0:
                _ = sessionTransferId()             // begin session
                onInsertText(analyzePrompt)
                advance(mode: mode, from: index)
            case 1:
                onInsertText(confirmPrompt(transferId: sessionTransferId(), parent: parentTransferId))
                // Baseline for the "clipboard ready" highlight on the Save step
                storage.kbClipCountAtPrompt = UIPasteboard.general.changeCount
                advance(mode: mode, from: index)
            default:
                loadFromClipboardAndInsert(storage: storage)
            }

        case .extended:
            switch index {
            case 0:
                _ = sessionTransferId()             // begin session
                onInsertText(preparePrompt)
                advance(mode: mode, from: index)
            case 1:
                onInsertText(anchorsPrompt)
                advance(mode: mode, from: index)
            case 2:
                onInsertText(extendedTransferPrompt(transferId: sessionTransferId(), parent: parentTransferId))
                // Baseline for the "clipboard ready" highlight on the Save step
                storage.kbClipCountAtPrompt = UIPasteboard.general.changeCount
                advance(mode: mode, from: index)
            default:
                loadFromClipboardAndInsert(storage: storage)
            }
        }
    }

    // Reads the LLM's JSON from the clipboard, saves the snapshot and inserts its
    // context. If the clipboard has no valid snapshot, we do NOTHING but flag the
    // failure — we must never fabricate and insert an empty template.
    private func loadFromClipboardAndInsert(storage: SharedStorage) {
        guard storage.canAddSnapshot else { return }
        let src = llmName.isEmpty ? "unknown" : llmName.lowercased()
        let clipText = UIPasteboard.general.string ?? ""

        var parsed: Snapshot?
        if !clipText.isEmpty {
            if let s = Snapshot.fromLLMOutput(clipText, llmSource: src) {
                parsed = s
            } else if var s = Snapshot.fromBackupJSON(Data(clipText.utf8)).first {
                if s.llmSource.isEmpty { s.llmSource = src }
                parsed = s
            }
        }

        guard let valid = parsed else {
            // No JSON captured → keep the step active and tell the user why.
            clipWasEmpty = clipText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            loadFailed = true
            return
        }

        loadFailed = false
        clipWasEmpty = false
        let snap = applyProject(to: valid)
        storage.addSnapshot(snap)
        storage.kbForkParentId = nil   // fork consumed
        // Save-only: the snapshot goes into the app, NOT into the chat input.
        // Inserting into a new LLM is done explicitly from History (Load ↑).
        savedOK = true
        withAnimation { flowState = .modeSelection }   // also clears the session transfer_id via persist()
    }

    private func advance(mode: TransferMode, from i: Int) {
        let next = i + 1
        withAnimation(.spring(response: 0.22)) {
            flowState = next < mode.steps.count
                ? .inProgress(mode: mode, step: next)
                : .modeSelection
        }
    }

    // Chain to the selected project's head. The project chosen in the keyboard
    // WINS over whatever the LLM wrote — otherwise the chip selection would
    // have no effect. With "＋ New" the LLM-invented name is kept (placeholder
    // leftovers like "…" are dropped so they never become a phantom project).
    private func applyProject(to parsed: Snapshot) -> Snapshot {
        var s = parsed
        if s.parentId == nil { s.parentId = parentTransferId }
        if let p = effectiveProject {
            s.project = p
        } else if let proj = s.project, proj.isEmpty || proj == "…" {
            s.project = nil
        }
        return s
    }

    // SIMPLE_ANALYZE — ported from browser extension popup-shell.js
    // Inserted into LLM at step 1 (Simple) and step 2 (Extended).
    // Bilingual like confirmPrompt — English users must not receive RU prompts.
    private var analyzePrompt: String {
        if SharedStorage.shared.kbLangCode == "en" {
            return """
            SessionPort PROTOCOL — QUICK TRANSFER.

            First, answer one question: what from our current conversation will be LOST in the transfer? For each item: critical / acceptable / irrelevant. Only critical items go into the snapshot.

            Then output strictly by sections:

            ## PROJECT DNA
            - Domain, stack, goal — one instruction sentence (verb + task + priority)
            - User's language and communication style (concise/verbose, language)
            - Global constraints (technologies, restrictions, deadlines)

            ## DECISIONS
            Each on its own line. Reason and context are required:
            [ACCEPTED] what exactly — because reason — under what circumstances
            [REJECTED] what exactly — because reason — why never suggest again
            [RULE] what exactly — because reason
            Minimum 3, ideally 5–10. Include ALL real [REJECTED] items — everything that was tried and explicitly refused. Do NOT invent rejections that didn't happen. If there were none, omit [REJECTED] entirely.

            ## STATE
            Last 3–5 actions · what works / what's broken / what's in progress · next step.

            ## IMPLICIT BLOCKS
            What did you stop suggesting in this session because the user silently rejected it? (implicit negative feedback — the most valuable thing lost in a transfer)

            ## INSTRUCTIONS FOR THE NEW MODEL
            3–5 rules: "If [X] → [Y]" or "Always/Never [Z] — because [reason]".

            ⚠️ If context is partially lost — use Full Transfer for manual correction.
            """
        }
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

        ⚠️ Если контекст частично потерян — используй Расширенный перенос для ручной корректировки.
        """
    }

    // EXTENDED step 1 — EXTENDED_PREPARE, ported 1:1 from popup-shell.js
    private var preparePrompt: String {
        if SharedStorage.shared.kbLangCode == "en" {
            return """
            SessionPort PROTOCOL — TRANSFER PREPARATION.

            Analyze our current conversation in this chat. Ask clarifying questions by category (one at a time):

            DECISIONS: Which decisions in our dialogue cannot be reconsidered? Why exactly?
            REJECTIONS: What was tried and discarded? Why exactly — so the new model never suggests it again?
            RULES: What working rules and constraints emerged from our conversation?
            STATE: Where did we stop? What is the next step? Specific files/functions?
            PATTERNS: How did your response style change over the session? What did you stop suggesting and why?

            No limit on iterations. After I say "ready" — we move to anchor verification.
            """
        }
        return """
        ПРОТОКОЛ SessionPort — ПОДГОТОВКА К ПЕРЕНОСУ.

        Проанализируй нашу переписку в этом чате. Задай уточняющие вопросы по категориям (по одной за раз):

        РЕШЕНИЯ: Какие решения из нашего диалога нельзя пересматривать? Почему именно такие?
        ОТКАЗЫ: Что пробовали и отвергли? Почему именно — чтобы новая модель никогда не предлагала снова?
        ПРАВИЛА: Какие рабочие правила и ограничения возникли в ходе разговора?
        СОСТОЯНИЕ: На чём остановились? Что следующий шаг? Конкретные файлы/функции?
        ПАТТЕРНЫ: Как изменился твой стиль ответов за сессию? Что ты перестал предлагать и почему?

        Количество итераций не ограничено. После моего «готово» — переходим к проверке якорей.
        """
    }

    // EXTENDED step 2 — EXTENDED_ANCHORS (5-layer verification), ported 1:1
    private var anchorsPrompt: String {
        if SharedStorage.shared.kbLangCode == "en" {
            return """
            SessionPort PROTOCOL — ANCHOR VERIFICATION.

            Based on everything discussed in this chat, output by layers:

            ## LAYER 1 — GOAL AND DNA
            Continuation instruction · language · communication style · global constraints.

            ## LAYER 2 — DECISIONS
            Each on its own line with reason and type:
            [ACCEPTED] what · why · under what circumstances
            [REJECTED] what · why · why never suggest again (all real ones; do not invent)
            [RULE] what · why

            ## LAYER 3 — STATE
            Last actions · artifacts (files/functions/concepts) · next step.

            ## LAYER 4 — INSTRUCTIONS
            Behavioral rules: "If X → Y", "Always/Never Z — because reason".

            ## LAYER 5 — IMPLICIT
            CALIBRATION: User expertise level (beginner/confident/expert/guru) — and what is your assessment based on?
            PATTERNS: When did the user accept suggestions quickly — what do they have in common? When rejected — what do they share?
            ADAPTATIONS: What did you stop suggesting and after which message? How did you adjust response length/tone?
            ASSUMPTIONS: What do you assume about the project without explicit data? (each with confidence: high/medium/low)
            BLIND SPOTS: Which specific questions, had you asked them, would have changed your earlier decisions?

            I will review each layer and tell you what to change. If everything is fine — we proceed to generation.
            """
        }
        return """
        ПРОТОКОЛ SessionPort — ПРОВЕРКА ЯКОРЕЙ.

        На основе всего обсуждения в этом чате выведи по слоям:

        ## СЛОЙ 1 — ЦЕЛЬ И ДНК
        Инструкция-продолжение · язык · стиль общения · глобальные ограничения.

        ## СЛОЙ 2 — РЕШЕНИЯ
        Каждое отдельной строкой с причиной и типом:
        [ПРИНЯТО] что · почему · при каких обстоятельствах
        [ОТКЛОНЕНО] что · почему · почему никогда не предлагать снова (все реальные; не придумывать)
        [ПРАВИЛО] что · почему

        ## СЛОЙ 3 — СОСТОЯНИЕ
        Последние действия · артефакты (файлы/функции/концепты) · следующий шаг.

        ## СЛОЙ 4 — ИНСТРУКЦИИ
        Поведенческие правила: «Если X → Y», «Всегда/Никогда Z — потому что причина».

        ## СЛОЙ 5 — НЕЯВНОЕ
        КАЛИБРОВКА: Уровень экспертизы пользователя (новичок/уверенный/эксперт/гуру) — и на чём основана оценка?
        ПАТТЕРНЫ: Когда пользователь принимал предложения быстро — что у них общего? Когда отклонял — что общего?
        АДАПТАЦИИ: Что ты перестал предлагать и после какого сообщения? Как изменил длину/тон ответов?
        ПРЕДПОЛОЖЕНИЯ: Что предполагаешь о проекте без явных данных? (каждое с уровнем уверенности high/medium/low)
        СЛЕПЫЕ ПЯТНА: Какие конкретные вопросы, если бы ты их задал, изменили бы твои предыдущие решения?

        Я проверю каждый слой и скажу что изменить. Если всё ок — переходим к генерации.
        """
    }

    // SIMPLE_CONFIRM / EXTENDED_TRANSFER — ported 1:1 from the browser extension
    // (popup-shell.js). Uses the stable session transfer_id and embeds
    // parent_transfer_id so the LLM writes the chain link into the JSON.
    private func confirmPrompt(transferId: String, parent: String?) -> String {
        let isEn = SharedStorage.shared.kbLangCode == "en"
        let parentMetaRU = parent.map { ",\"parent_transfer_id\":\"\($0)\"" } ?? ""
        let parentMetaEN = parentMetaRU
        let parentTidRU  = parent.map { "\nmeta.parent_transfer_id = \"\($0)\" символ-в-символ." } ?? ""
        let parentTidEN  = parent.map { "\nmeta.parent_transfer_id = \"\($0)\" character-for-character." } ?? ""
        // Selected target project goes into the template verbatim; for a new
        // project the LLM is asked to invent a short name.
        let projectValue = effectiveProject ?? "…"
        let projectRuleRU = effectiveProject.map { "\nmeta.project = \"\($0)\" — символ-в-символ." }
            ?? "\nmeta.project — придумай короткое имя проекта (1–3 слова) по теме переписки."
        let projectRuleEN = effectiveProject.map { "\nmeta.project = \"\($0)\" character-for-character." }
            ?? "\nmeta.project — invent a short project name (1–3 words) matching the conversation."

        if isEn {
            let json = "{\"meta\":{\"protocol\":\"SessionPort\",\"transfer_id\":\"\(transferId)\",\"project\":\"\(projectValue)\",\"version\":\"1.1\",\"date\":\"YYYY-MM-DD\"\(parentMetaEN)},\"dna\":{\"goal\":\"continuation instruction (verb+task+priority)\",\"language\":\"en\",\"style\":\"…\",\"constraints\":[\"…\"],\"trajectory\":\"where the project is heading — next major step or goal\"},\"decisions\":[{\"what\":\"…\",\"why\":\"reason\",\"context\":\"under what circumstances\",\"type\":\"accepted\"},{\"what\":\"…\",\"why\":\"reason\",\"context\":\"what was tried and refused\",\"type\":\"rejected\"},{\"what\":\"…\",\"why\":\"reason\",\"context\":\"\",\"type\":\"rule\"}],\"state\":{\"current_task\":\"…\",\"last_actions\":[\"…\",\"…\",\"…\"],\"next_step\":\"…\",\"artifacts\":[\"file/function/concept\"]},\"instructions\":[\"If X → Y\",\"Always Z when W\",\"Never Q — because R\"],\"open_threads\":[\"genuinely unresolved question or branch we left open — why it matters\"],\"validation\":{\"questions\":[\"?\",\"?\",\"?\"],\"expected\":[\"criterion 1\",\"criterion 2\",\"criterion 3\"]}}"
            return """
            SessionPort PROTOCOL — SNAPSHOT GENERATION.

            Convert the structured breakdown you produced in the previous step into a JSON snapshot — one-to-one, do NOT re-analyze the conversation from scratch or add items the user has not already seen. Fill in real data from our dialogue instead of "…". The transfer_id below is a unique label — do NOT look it up anywhere, just copy it into meta.transfer_id as-is:

            ```json
            \(json)
            ```

            or ---BEGIN CONTEXT---{…}---END CONTEXT---

            CRITICAL: All data comes from our conversation above — no external sources needed.
            decisions — minimum 3. Include ALL real type:"rejected" entries (what was tried and explicitly refused). Do NOT invent rejections — if there were none, the array may be empty. Each must have a non-empty "why".
            validation.questions — make them probe real decisions and rejected items, so a wrong or partial restore yields a visibly wrong answer; do NOT ask trivia that can be copied straight from dna.goal.
            meta.transfer_id = "\(transferId)" character-for-character.\(parentTidEN)\(projectRuleEN)
            First character {. Last character }. JSON only, no explanation.
            """
        }

        let json = "{\"meta\":{\"protocol\":\"SessionPort\",\"transfer_id\":\"\(transferId)\",\"project\":\"\(projectValue)\",\"version\":\"1.1\",\"date\":\"YYYY-MM-DD\"\(parentMetaRU)},\"dna\":{\"goal\":\"инструкция-продолжение (глагол+задача+приоритет)\",\"language\":\"ru\",\"style\":\"…\",\"constraints\":[\"…\"],\"trajectory\":\"куда движется проект — следующий крупный шаг или цель\"},\"decisions\":[{\"what\":\"…\",\"why\":\"причина\",\"context\":\"при каких обстоятельствах\",\"type\":\"accepted\"},{\"what\":\"…\",\"why\":\"причина\",\"context\":\"что пробовали и явно отвергли\",\"type\":\"rejected\"},{\"what\":\"…\",\"why\":\"причина\",\"context\":\"\",\"type\":\"rule\"}],\"state\":{\"current_task\":\"…\",\"last_actions\":[\"…\",\"…\",\"…\"],\"next_step\":\"…\",\"artifacts\":[\"файл/функция/концепт\"]},\"instructions\":[\"Если X → Y\",\"Всегда Z при W\",\"Никогда Q — потому что R\"],\"open_threads\":[\"реально нерешённый вопрос или ветка, которую оставили открытой — почему это важно\"],\"validation\":{\"questions\":[\"?\",\"?\",\"?\"],\"expected\":[\"критерий 1\",\"критерий 2\",\"критерий 3\"]}}"
        return """
        ПРОТОКОЛ SessionPort — ГЕНЕРАЦИЯ СЛЕПКА.

        Преобразуй структурный разбор, который ты выдал на предыдущем шаге, в JSON-слепок — один-в-один, не анализируй переписку заново и не добавляй пункты, которых пользователь ещё не видел. Подставь реальные данные из нашего диалога вместо «…». transfer_id ниже — уникальная метка, не ищи её нигде — просто скопируй в meta.transfer_id как есть:

        ```json
        \(json)
        ```

        или ---BEGIN CONTEXT---{…}---END CONTEXT---

        КРИТИЧНО: Все данные — из нашей переписки выше.
        decisions — минимум 3. Включи ВСЕ реальные type:"rejected" (что пробовали и явно отвергли). НЕ выдумывай отклонения — если их не было, массив может быть пустым. Каждое с непустым "why".
        validation.questions — формулируй так, чтобы они проверяли реальные решения и отклонённые варианты: при неверном или неполном восстановлении ответ будет заметно ошибочным. Не спрашивай то, что тривиально копируется из dna.goal.
        meta.transfer_id = "\(transferId)" — символ-в-символ.\(parentTidRU)\(projectRuleRU)
        Первый символ {. Последний }. Только JSON, без пояснений.
        """
    }

    // EXTENDED step 3 — EXTENDED_TRANSFER, ported 1:1 from the browser extension
    // (adds the "implicit" block on top of the SIMPLE_CONFIRM schema).
    private func extendedTransferPrompt(transferId: String, parent: String?) -> String {
        let isEn = SharedStorage.shared.kbLangCode == "en"
        let parentMeta = parent.map { ",\"parent_transfer_id\":\"\($0)\"" } ?? ""
        let parentTidRU = parent.map { "\nmeta.parent_transfer_id = \"\($0)\" символ-в-символ." } ?? ""
        let parentTidEN = parent.map { "\nmeta.parent_transfer_id = \"\($0)\" character-for-character." } ?? ""
        let projectValue = effectiveProject ?? "…"
        let projectRuleRU = effectiveProject.map { "\nmeta.project = \"\($0)\" — символ-в-символ." }
            ?? "\nmeta.project — придумай короткое имя проекта (1–3 слова) по теме переписки."
        let projectRuleEN = effectiveProject.map { "\nmeta.project = \"\($0)\" character-for-character." }
            ?? "\nmeta.project — invent a short project name (1–3 words) matching the conversation."

        if isEn {
            let json = "{\"meta\":{\"protocol\":\"SessionPort\",\"transfer_id\":\"\(transferId)\",\"project\":\"\(projectValue)\",\"version\":\"1.1\",\"date\":\"YYYY-MM-DD\"\(parentMeta)},\"dna\":{\"goal\":\"continuation instruction\",\"language\":\"en\",\"style\":\"…\",\"constraints\":[\"…\"],\"trajectory\":\"next major step/goal of the project\"},\"decisions\":[{\"what\":\"…\",\"why\":\"reason — what was tried and explicitly refused\",\"type\":\"rejected\"},{\"what\":\"…\",\"why\":\"reason\",\"type\":\"rule\"},{\"what\":\"…\",\"why\":\"reason\",\"type\":\"accepted\"}],\"state\":{\"current_task\":\"…\",\"last_actions\":[\"…\",\"…\",\"…\"],\"next_step\":\"…\",\"artifacts\":[\"…\"]},\"instructions\":[\"If X → Y\",\"Always Z when W\",\"Never Q — because R\"],\"open_threads\":[\"genuinely unresolved question or branch we left open — why it matters\"],\"implicit\":{\"user_profile\":{\"expertise\":\"expert/confident/beginner\",\"style\":\"…\",\"priorities\":[\"…\"],\"profile_confidence\":\"high/medium/low — based on N messages\"},\"adaptation_log\":[\"Stopped suggesting X after message N — user never accepted it\",\"Reduced detail level — user replied briefly\"],\"blind_spots\":[\"Which question, had I asked it, would have changed my decision about X?\"],\"assumptions\":[{\"what\":\"…\",\"confidence\":\"high/medium/low\"}]},\"validation\":{\"questions\":[\"?\",\"?\",\"?\"],\"expected\":[\"criterion 1\",\"criterion 2\",\"criterion 3\"]}}"
            return """
            SessionPort PROTOCOL — SNAPSHOT GENERATION.

            Based on the anchors (layers 1–4) and implicit context (layer 5) verified above, generate JSON. The transfer_id below is a unique label — do NOT look it up anywhere, just copy it into meta.transfer_id as-is:

            ```json
            \(json)
            ```

            or ---BEGIN CONTEXT---{…}---END CONTEXT---

            CRITICAL: decisions — include ALL real type:"rejected" (what was tried and explicitly refused). Do NOT invent rejections — if there were none, the array may be empty. Each with non-empty "why". implicit.adaptation_log — real behavior changes only.
            validation.questions — make them probe real decisions and rejected items, so a wrong or partial restore yields a visibly wrong answer; do NOT ask trivia copyable straight from dna.goal.
            meta.transfer_id = "\(transferId)" character-for-character.\(parentTidEN)\(projectRuleEN)
            First character {. Last character }. JSON only.
            """
        }

        let json = "{\"meta\":{\"protocol\":\"SessionPort\",\"transfer_id\":\"\(transferId)\",\"project\":\"\(projectValue)\",\"version\":\"1.1\",\"date\":\"YYYY-MM-DD\"\(parentMeta)},\"dna\":{\"goal\":\"инструкция-продолжение\",\"language\":\"ru\",\"style\":\"…\",\"constraints\":[\"…\"],\"trajectory\":\"следующий крупный шаг/цель проекта\"},\"decisions\":[{\"what\":\"…\",\"why\":\"причина — что пробовали и явно отвергли\",\"type\":\"rejected\"},{\"what\":\"…\",\"why\":\"причина\",\"type\":\"rule\"},{\"what\":\"…\",\"why\":\"причина\",\"type\":\"accepted\"}],\"state\":{\"current_task\":\"…\",\"last_actions\":[\"…\",\"…\",\"…\"],\"next_step\":\"…\",\"artifacts\":[\"…\"]},\"instructions\":[\"Если X → Y\",\"Всегда Z при W\",\"Никогда Q — потому что R\"],\"open_threads\":[\"реально нерешённый вопрос или ветка, которую оставили открытой — почему это важно\"],\"implicit\":{\"user_profile\":{\"expertise\":\"эксперт/уверенный/новичок\",\"style\":\"…\",\"priorities\":[\"…\"],\"profile_confidence\":\"high/medium/low — основано на N сообщениях\"},\"adaptation_log\":[\"Перестал предлагать X после сообщения N — пользователь ни разу не принял\",\"Сократил детальность — пользователь отвечал коротко\"],\"blind_spots\":[\"Какой вопрос, если бы я его задал, изменил бы моё решение по X?\"],\"assumptions\":[{\"what\":\"…\",\"confidence\":\"high/medium/low\"}]},\"validation\":{\"questions\":[\"?\",\"?\",\"?\"],\"expected\":[\"критерий 1\",\"критерий 2\",\"критерий 3\"]}}"
        return """
        ПРОТОКОЛ SessionPort — ГЕНЕРАЦИЯ СЛЕПКА.

        На основе якорей (слои 1–4) и неявного контекста (слой 5), верифицированных выше, сформируй JSON. transfer_id — уникальная метка, не ищи её нигде — просто скопируй в meta.transfer_id как есть:

        ```json
        \(json)
        ```

        или ---BEGIN CONTEXT---{…}---END CONTEXT---

        КРИТИЧНО: decisions — включи ВСЕ реальные type:"rejected" (что пробовали и явно отвергли). НЕ выдумывай отклонения — если их не было, массив может быть пустым. Каждое с непустым "why". implicit.adaptation_log — только реальные изменения поведения.
        validation.questions — формулируй так, чтобы они проверяли реальные решения и отклонённые варианты: при неверном или неполном восстановлении ответ будет заметно ошибочным. Не спрашивай то, что тривиально копируется из dna.goal.
        meta.transfer_id = "\(transferId)" символ-в-символ.\(parentTidRU)\(projectRuleRU)
        Первый символ {. Последний }. Только JSON.
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
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    var ready: Bool = false     // clipboard holds fresh content → green highlight
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
                    } else if ready {
                        Image(systemName: "arrow.down.doc.fill")
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
                          ? (ready ? Color.green.opacity(0.16) : Color.accentColor.opacity(0.13))
                          : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(ready ? Color.green : (state == .active ? Color.accentColor : .clear),
                            lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(state == .waiting)
        .opacity(state == .waiting ? 0.45 : 1)
    }

    private var dotColor: Color {
        if ready { return .green }
        switch state {
        case .waiting: return .secondary.opacity(0.3)
        case .active:  return .accentColor
        case .done:    return .green
        }
    }
}
