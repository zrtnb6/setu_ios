import SetuIOSCore
import SwiftUI

struct AiDrawView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.setuRecoveryActions) private var recovery
    @Environment(RouterPath.self) private var router
    @Environment(SystemPushCoordinator.self) private var pushNotifications
    @Bindable var environment: AppEnvironment
    @AppStorage("setu_has_explained_generation_notifications") private var hasExplainedGenerationNotifications = false
    @State private var statusState: LoadState<AiServiceStatusResponse> = .idle
    @State private var capabilityState: LoadState<AiCapabilityResponse> = .idle
    @FocusState private var promptFocused: Bool
    @State private var promptCn = ""
    @State private var styleTags = ""
    @State private var positivePrompt = ""
    @State private var negativePrompt = AiDrawDefaults.defaultNegativePrompt
    @State private var styleNotes = ""
    @State private var width = 768
    @State private var height = 1024
    @State private var steps = 28
    @State private var cfg = 7.0
    @State private var nsfwMode = false
    @State private var nsfwVisibilityLevel = "STANDARD"
    @State private var generationMode = "SINGLE"
    @State private var selectedCheckpoint = ""
    @State private var selectedLora = ""
    @State private var loraStrength = 0.8
    @State private var selectedCharacter = ""
    @State private var selectedSecondLora = ""
    @State private var secondLoraStrength = 0.65
    @State private var selectedSecondCharacter = ""
    @State private var isTranslating = false
    @State private var isSubmitting = false
    @State private var feedback: SetuFeedback?
    @State private var userFacingError: UserFacingError?
    @State private var draftLoaded = false
    @State private var isApplyingDraft = false
    @State private var loadedDraftUpdatedAt: Date?
    @State private var enabledStylePresetNames: [String] = []
    @State private var showingGenerationNotificationPrompt = false
    @State private var pendingGenerationID: Int?
    @State private var showingAdvancedSettings = false
    @State private var showingClearDraftConfirmation = false

    private let estimatedPointsCost = 20

    var body: some View {
        lifecycleDecorated
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    SetuToolbarLogo(assetName: "AiDrawLogo", accessibilityLabel: "AI 绘画")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { promptFocused = false }
                        .accessibilityIdentifier("ai.draw.keyboard.done")
                }
                #endif
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        router.navigate(to: .aiHistory)
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("AI 绘画历史")

                    Menu {
                        Button {
                            router.navigate(to: .aiDeleteRequests)
                        } label: {
                            Label("我的删除记录", systemImage: "xmark.bin")
                        }
                        Button("清空当前草稿", role: .destructive) {
                            showingClearDraftConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("更多创作操作")
                }
            }
            .task { await loadMetadata() }
            .refreshable { await loadMetadata() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                generationCTA
            }
            .alert("生成完成时通知我？", isPresented: $showingGenerationNotificationPrompt) {
                Button("开启通知") {
                    Task {
                        _ = await pushNotifications.requestAuthorizationForGenerationUpdates()
                        openPendingGeneration()
                    }
                }
                Button("暂不", role: .cancel) {
                    openPendingGeneration()
                }
            } message: {
                Text("即使离开 App，也不会错过这次作品的完成提醒。系统权限只会在你确认后请求。")
            }
            .confirmationDialog("清空当前创作草稿？", isPresented: $showingClearDraftConfirmation, titleVisibility: .visible) {
                Button("清空草稿", role: .destructive) {
                    clearDraft()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("画面描述、风格、角色和高级设置都会恢复为推荐值。")
            }
    }

    private var lifecycleDecorated: some View {
        navigationDecorated
            .onAppear {
                applyDraftIfNeeded()
                refreshEnabledStylePresets()
            }
            .onDisappear { saveDraft() }
            .onChange(of: promptCn) { saveDraft() }
            .onChange(of: positivePrompt) { saveDraft() }
            .onChange(of: width) { saveDraft() }
            .onChange(of: height) { saveDraft() }
            .onChange(of: steps) { saveDraft() }
            .onChange(of: cfg) { saveDraft() }
            .onChange(of: nsfwMode) { saveDraft() }
            .onChange(of: nsfwVisibilityLevel) { saveDraft() }
            .onChange(of: generationMode) { saveDraft() }
            .onChange(of: selectedCheckpoint) { saveDraft() }
            .onChange(of: selectedLora) { saveDraft() }
            .onChange(of: loraStrength) { saveDraft() }
            .onChange(of: selectedCharacter) { saveDraft() }
            .onChange(of: selectedSecondLora) { saveDraft() }
            .onChange(of: secondLoraStrength) { saveDraft() }
            .onChange(of: selectedSecondCharacter) { saveDraft() }
            .onChange(of: styleTags) { saveDraft() }
            .onChange(of: negativePrompt) { saveDraft() }
            .onChange(of: styleNotes) { saveDraft() }
    }

    private var navigationDecorated: some View {
        decoratedList
            .setuFeedbackPresentation($feedback)
            .setuRefreshAfterLogin(environment.authSession) { Task { await loadMetadata() } }
            .setuRetry { Task { await loadMetadata() } }
            .navigationTitle("AI 绘画")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ai.draw.page")
            .scrollDismissesKeyboard(.interactively)
    }

    private var decoratedList: some View {
        List {
            serviceNoticeSection
            quickPromptSection
            quickCanvasSection
            quickAssetSection
            advancedSettingsSection
            feedbackSection
        }
        .listStyle(.plain)
        .setuBackground()
    }

    @ViewBuilder
    private var serviceNoticeSection: some View {
        switch statusState {
        case .failed(let text):
            Section {
                SetuCard {
                    SetuEmptyState(error: text, retry: { Task { await loadMetadata() } })
                }
            }
            .setuListRow()
        case .loaded(let status) where !status.available:
            Section {
                SetuCard {
                    SetuEmptyState(
                        title: "AI 绘画暂不可用",
                        message: status.userFacingUnavailableMessage,
                        systemImage: "sparkles"
                    )
                    Button("重试") { Task { await loadMetadata() } }
                        .buttonStyle(.bordered)
                }
            }
            .setuListRow()
        case .loaded(let status) where (status.estimatedWaitSeconds ?? 0) > 60 || (status.queuedCount ?? 0) > 0:
            Section {
                SetuPill(
                    text: estimatedWaitText(status.estimatedWaitSeconds),
                    systemImage: "clock",
                    tone: .warning
                )
            }
            .setuListRow()
        default:
            EmptyView()
        }
    }

    private var quickPromptSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "想画什么？", subtitle: "用自然语言描述场景、人物、氛围和光线")
                    TextField("例如：银发少女站在雨夜街角，霓虹灯倒映在路面，电影感光影", text: $promptCn, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($promptFocused)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("画面描述")
                        .accessibilityIdentifier("ai.draw.prompt")
                    Text("\(promptCn.count) 字 · 可直接开始，细节会自动补全")
                        .font(.caption)
                        .foregroundStyle(SetuColor.textTertiary)
                    if isTranslating {
                        SetuPill(text: "正在理解你的画面", systemImage: "wand.and.sparkles", tone: .brand)
                    }
                }
            }
        }
        .setuListRow()
    }

    private var quickCanvasSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "画幅", subtitle: "选择最适合作品展示的比例")
                    canvasPresetGrid
                }
            }
        }
        .setuListRow()
    }

    private var quickAssetSection: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "风格与角色", subtitle: "可选，不选择也能直接生成")
                    Picker("人物数量", selection: $generationMode) {
                        Text("单人物").tag("SINGLE")
                        Text("双人物").tag("DUAL")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("ai.draw.generationMode")
                    SetuNavigationRow(title: "选择风格与角色", subtitle: selectedAssetSummary, systemImage: "photo.stack") {
                        saveDraft()
                        router.navigate(to: .aiAssets)
                    }
                    if generationMode == "DUAL" {
                        SetuPill(
                            text: "双人物已开启，请在角色库分别选择主角色和副角色",
                            systemImage: "person.2.fill",
                            tone: .brand
                        )
                    }
                    if !enabledStylePresetNames.isEmpty {
                        Text(enabledStylePresetNames.joined(separator: "、"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SetuColor.textPrimary)
                    }
                    if hasAssetDraft {
                        SetuPill(text: "已应用所选风格或角色", systemImage: "checkmark.circle", tone: .success)
                    }
                }
            }
        }
        .setuListRow()
    }

    private var selectedAssetSummary: String {
        var names = enabledStylePresetNames
        if case .loaded(let capabilities) = capabilityState {
            var selections = [(selectedCharacter, selectedLora)]
            if generationMode == "DUAL" { selections.append((selectedSecondCharacter, selectedSecondLora)) }
            for (character, lora) in selections {
                if !character.isEmpty {
                    names.append(capabilities.characters.first { $0.name == character }?.displayName ?? character)
                } else if !lora.isEmpty {
                    names.append(capabilities.loras.first { $0.name == lora }?.displayName ?? lora)
                }
            }
        }
        return names.isEmpty ? "浏览风格、角色和画面预设" : names.joined(separator: "、")
    }

    private var advancedSettingsSection: some View {
        Section {
            SetuCard {
                DisclosureGroup("高级设置", isExpanded: $showingAdvancedSettings) {
                    VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                        Divider()
                        Stepper("画面宽度 \(width)", value: $width, in: 512...1536, step: 64)
                        Stepper("画面高度 \(height)", value: $height, in: 512...1536, step: 64)
                        Stepper("精细程度 \(steps)", value: $steps, in: 12...60)
                        HStack {
                            Text("提示遵循强度")
                            Slider(value: $cfg, in: 3...12, step: 0.5)
                                .tint(SetuColor.brandPink)
                            Text(cfg.formatted(.number.precision(.fractionLength(1))))
                                .monospacedDigit()
                        }
                        Toggle("成人内容模式", isOn: $nsfwMode)
                            .tint(SetuColor.brandPink)
                        if nsfwMode {
                            Picker("内容呈现程度", selection: $nsfwVisibilityLevel) {
                                Text("含蓄").tag("LIGHT")
                                Text("标准").tag("STANDARD")
                                Text("直接").tag("STRONG")
                            }
                            Text("仅影响生成画面的遮挡、服装和细节表现。")
                                .font(.footnote)
                                .foregroundStyle(SetuColor.textSecondary)
                        }

                        advancedModelSettings

                        TextField("画面细节提示（选填）", text: $positivePrompt, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.roundedBorder)
                        TextField("需要避开的内容（选填）", text: $negativePrompt, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.roundedBorder)

                        Button("恢复推荐设置") {
                            restoreRecommendedSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, SetuSpacing.sm)
                }
                .font(.body.weight(.semibold))
            }
        }
        .setuListRow()
    }

    @ViewBuilder
    private var advancedModelSettings: some View {
        if case .loaded(let capabilities) = capabilityState {
            Picker("基础画风", selection: $selectedCheckpoint) {
                Text("推荐").tag("")
                ForEach(capabilities.checkpoints) { item in
                    Text(item.displayName ?? item.name).tag(item.name)
                }
            }
            Picker("主要风格", selection: $selectedLora) {
                Text("不使用").tag("")
                ForEach(capabilities.loras) { item in
                    Text(item.displayName ?? item.name).tag(item.name)
                }
            }
            Picker("主要角色", selection: $selectedCharacter) {
                Text("不使用").tag("")
                ForEach(capabilities.characters) { item in
                    Text(item.displayName ?? item.name).tag(item.name)
                }
            }
            if !selectedLora.isEmpty {
                HStack {
                    Text("主要风格强度")
                    Slider(value: $loraStrength, in: 0.1...1.5, step: 0.1)
                        .tint(SetuColor.brandPink)
                }
            }
            if generationMode == "DUAL" {
                Picker("第二风格", selection: $selectedSecondLora) {
                    Text("不使用").tag("")
                    ForEach(capabilities.loras) { item in
                        Text(item.displayName ?? item.name).tag(item.name)
                    }
                }
                Picker("第二角色", selection: $selectedSecondCharacter) {
                    Text("不使用").tag("")
                    ForEach(capabilities.characters) { item in
                        Text(item.displayName ?? item.name).tag(item.name)
                    }
                }
                if !selectedSecondLora.isEmpty {
                    HStack {
                        Text("第二风格强度")
                        Slider(value: $secondLoraStrength, in: 0.1...1.5, step: 0.1)
                            .tint(SetuColor.brandPink)
                    }
                }
            }
        } else if case .failed = capabilityState {
            Text("高级画风暂时无法加载，仍可使用推荐设置生成。")
                .font(.footnote)
                .foregroundStyle(SetuColor.textSecondary)
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
        if let userFacingError {
            Section {
                SetuFeedbackBanner(error: userFacingError, onAction: handleErrorAction)
            }
            .setuListRow()
        } else if let feedback {
            Section {
                SetuFeedbackBanner(feedback: feedback)
            }
            .setuListRow()
        }
    }

    private var generationCTA: some View {
        SetuBottomCTA {
            SetuPrimaryButton {
                Task { await submit() }
            } label: {
                if isSubmitting || isTranslating {
                    HStack(spacing: SetuSpacing.sm) {
                        ProgressView().tint(.white)
                        Text(isTranslating ? "正在理解画面" : "正在创建作品")
                    }
                } else if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: SetuSpacing.xs) {
                        Text("开始生成")
                        Text("预计 \(estimatedPointsCost) 积分")
                            .font(.footnote)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, SetuSpacing.sm)
                } else {
                    Label("开始生成 · 预计 \(estimatedPointsCost) 积分", systemImage: "sparkles")
                }
            }
            .accessibilityIdentifier("ai.draw.generate")
            .disabled(!hasDrawablePrompt || isSubmitting || isTranslating || !serviceReady)
        }
    }

    private var canvasPresetGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(AiCanvasPreset.allCases) { preset in
                    Button {
                        width = preset.width
                        height = preset.height
                        saveDraft()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Image(systemName: preset.systemImage)
                                .font(.title3)
                            Text(preset.title)
                                .font(.footnote.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(width == preset.width && height == preset.height ? SetuColor.brandPink : SetuColor.textSecondary)
                    .accessibilityAddTraits(width == preset.width && height == preset.height ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func loadMetadata() async {
        statusState = .loading
        capabilityState = .loading
        async let status = environment.aiGenerationClient.serviceStatus()
        async let capabilities = environment.aiGenerationClient.capabilities()
        do {
            statusState = .loaded(try await status)
        } catch {
            statusState = .failed(UserFacingErrorMapper.map(error))
        }
        do {
            capabilityState = .loaded(try await capabilities)
        } catch {
            capabilityState = .failed(UserFacingErrorMapper.map(error))
        }
    }

    @discardableResult
    private func preparePrompt() async -> Bool {
        let prompt = promptCn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            if applyPresetPromptToGeneratedFields() {
                feedback = nil
                saveDraft()
                return true
            }
            feedback = .warning("先描述想画的画面，或选择一个风格与角色。")
            return false
        }
        guard serviceReady else {
            if applyPresetPromptToGeneratedFields() {
                feedback = nil
                saveDraft()
                return true
            }
            feedback = .warning(serviceUnavailableText)
            return false
        }
        if generationMode == "DUAL", selectedSecondCharacter.isEmpty, selectedSecondLora.isEmpty {
            feedback = .warning("双人物创作需要选择第二角色或第二风格。")
            return false
        }

        isTranslating = true
        defer {
            isTranslating = false
        }
        do {
            var response = try await environment.aiGenerationClient.translatePrompt(
                AiPromptTranslateRequest(
                    promptCn: prompt,
                    styleTags: trimmedOptional(styleTags),
                    negativePrompt: trimmedOptional(negativePrompt),
                    nsfwMode: nsfwMode,
                    nsfwVisibilityLevel: nsfwMode ? nsfwVisibilityLevel : "STANDARD"
                )
            )
            if response.status != "COMPLETED", response.positive?.isEmpty != false {
                guard let id = response.id else {
                    throw AiDrawPromptPreparationError.missingTranslationId
                }
                response = try await waitForPromptTranslation(id: id)
            }
            if let positive = response.positive, !positive.isEmpty {
                positivePrompt = positive
            }
            if let negative = response.negative, !negative.isEmpty {
                negativePrompt = negative
            } else if negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                negativePrompt = AiDrawDefaults.defaultNegativePrompt
            }
            if let styleNotes = response.styleNotes, !styleNotes.isEmpty {
                self.styleNotes = styleNotes
            }
            feedback = nil
            saveDraft()
            return true
        } catch {
            feedback = nil
            userFacingError = UserFacingErrorMapper.map(error)
            return false
        }
    }

    private func waitForPromptTranslation(id: Int) async throws -> AiPromptTranslateResponse {
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            let response = try await environment.aiGenerationClient.promptTranslation(id: id)
            switch response.status {
            case "COMPLETED":
                return response
            case "FAILED":
                throw AiDrawPromptPreparationError.translationFailed(response.errorMessage)
            default:
                try await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
        throw AiDrawPromptPreparationError.translationTimedOut
    }

    private func submit() async {
        userFacingError = nil
        let prompt = promptCn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasDrawablePrompt else {
            feedback = .warning("先描述想画的画面，或选择一个风格与角色。")
            return
        }
        guard serviceReady else {
            feedback = .warning(serviceUnavailableText)
            return
        }
        var promptPositive = positivePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if promptPositive.isEmpty {
            if !prompt.isEmpty {
                let prepared = await preparePrompt()
                guard prepared else { return }
                promptPositive = positivePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if applyPresetPromptToGeneratedFields() {
                promptPositive = presetPromptSeed
            }
        }
        let promptNegative = resolvedNegativePrompt
        isSubmitting = true
        feedback = nil
        defer { isSubmitting = false }
        do {
            let job = try await environment.aiGenerationClient.create(
                AiGenerationCreateRequest(
                    promptCn: prompt,
                    promptPositive: promptPositive,
                    promptNegative: promptNegative,
                    styleNotes: styleNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                    width: width,
                    height: height,
                    steps: steps,
                    cfg: cfg,
                    checkpoint: selectedCheckpoint.isEmpty ? nil : selectedCheckpoint,
                    generationMode: generationMode,
                    loraName: selectedLora.isEmpty ? nil : selectedLora,
                    loraStrength: selectedLora.isEmpty ? nil : loraStrength,
                    characterId: selectedCharacter.isEmpty ? nil : selectedCharacter,
                    secondLoraName: generationMode == "DUAL" && !selectedSecondLora.isEmpty ? selectedSecondLora : nil,
                    secondLoraStrength: generationMode == "DUAL" && !selectedSecondLora.isEmpty ? secondLoraStrength : nil,
                    secondCharacterId: generationMode == "DUAL" && !selectedSecondCharacter.isEmpty ? selectedSecondCharacter : nil,
                    nsfwMode: nsfwMode,
                    nsfwVisibilityLevel: nsfwMode ? nsfwVisibilityLevel : "STANDARD"
                )
            )
            feedback = .success("作品已提交，正在开始生成。")
            resetGeneratedStyleStateForNextJob()
            AiDrawDraftStore.clear()
            AiAssetBrowserCacheStore.clearSelectedStyles()
            await AiGenerationLiveActivityCenter.start(job: job, mobileClient: environment.mobileAppClient)
            if !hasExplainedGenerationNotifications,
               pushNotifications.authorizationStatus == .notDetermined {
                hasExplainedGenerationNotifications = true
                pendingGenerationID = job.id
                showingGenerationNotificationPrompt = true
            } else {
                router.navigate(to: .aiGenerationDetail(job.id))
            }
        } catch {
            feedback = nil
            userFacingError = UserFacingErrorMapper.map(error)
        }
    }

    private func handleErrorAction(_ action: UserFacingErrorAction) {
        switch action {
        case .retry:
            Task { await loadMetadata() }
        case .refresh:
            Task { await loadMetadata() }
        case .signIn:
            recovery.signIn?()
        case .goBack:
            userFacingError = nil
            if !router.path.isEmpty {
                router.path.removeLast()
            }
        case .reviewInput:
            userFacingError = nil
            showingAdvancedSettings = true
        case .wait:
            userFacingError = nil
        case .viewPoints:
            userFacingError = nil
            router.navigate(to: .pointsLogs)
        }
    }

    private func openPendingGeneration() {
        guard let pendingGenerationID else { return }
        self.pendingGenerationID = nil
        router.navigate(to: .aiGenerationDetail(pendingGenerationID))
    }

    private func estimatedWaitText(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "当前创作较多，可能需要稍等" }
        let minutes = max(1, (seconds + 59) / 60)
        return "当前繁忙，预计等待约 \(minutes) 分钟"
    }

    private func restoreRecommendedSettings() {
        width = 768
        height = 1024
        steps = 28
        cfg = 7
        nsfwMode = false
        nsfwVisibilityLevel = "STANDARD"
        generationMode = "SINGLE"
        selectedCheckpoint = ""
        selectedLora = ""
        loraStrength = 0.8
        selectedCharacter = ""
        selectedSecondLora = ""
        secondLoraStrength = 0.65
        selectedSecondCharacter = ""
        positivePrompt = ""
        negativePrompt = AiDrawDefaults.defaultNegativePrompt
        styleNotes = ""
        saveDraft()
    }

    private func clearDraft() {
        AiDrawDraftStore.clear()
        AiAssetBrowserCacheStore.clearSelectedStyles()
        promptCn = ""
        styleTags = ""
        enabledStylePresetNames = []
        restoreRecommendedSettings()
    }

    private var hasDrawablePrompt: Bool {
        !promptCn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !positivePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || hasPresetPromptSeed
    }

    private var presetPromptSeed: String {
        styleTags.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasPresetPromptSeed: Bool {
        !presetPromptSeed.isEmpty
    }

    private var resolvedNegativePrompt: String {
        let trimmed = negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AiDrawDefaults.defaultNegativePrompt : trimmed
    }

    private var serviceReady: Bool {
        if case .loaded(let status) = statusState {
            return status.available
        }
        return false
    }

    private var serviceUnavailableText: String {
        if case .loaded(let status) = statusState {
            return status.userFacingUnavailableMessage
        }
        if case .failed(let message) = statusState {
            return message.message
        }
        return "AI 服务状态加载中"
    }

    private func trimmedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    private func applyPresetPromptToGeneratedFields() -> Bool {
        guard hasPresetPromptSeed else { return false }
        if positivePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            positivePrompt = presetPromptSeed
        }
        if negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            negativePrompt = AiDrawDefaults.defaultNegativePrompt
        }
        return true
    }

    private var hasAssetDraft: Bool {
        !selectedCheckpoint.isEmpty
            || !selectedLora.isEmpty
            || !selectedCharacter.isEmpty
            || !selectedSecondLora.isEmpty
            || !selectedSecondCharacter.isEmpty
            || !styleTags.isEmpty
            || !isDefaultNegativePrompt
    }

    private func applyDraftIfNeeded() {
        guard let draft = AiDrawDraftStore.loadIfPresent() else {
            AiAssetBrowserCacheStore.clearSelectedStyles()
            enabledStylePresetNames = []
            applyGeneratedStyleReset()
            draftLoaded = true
            return
        }
        guard loadedDraftUpdatedAt != draft.updatedAt else {
            draftLoaded = true
            return
        }
        isApplyingDraft = true
        promptCn = draft.promptCn
        positivePrompt = draft.promptPositive
        width = draft.width
        height = draft.height
        steps = draft.steps
        cfg = draft.cfg
        nsfwMode = draft.nsfwMode
        nsfwVisibilityLevel = draft.nsfwVisibilityLevel
        generationMode = draft.generationMode
        selectedCheckpoint = draft.checkpoint
        selectedLora = draft.loraName
        loraStrength = draft.loraStrength
        selectedCharacter = draft.characterId
        selectedSecondLora = draft.secondLoraName
        secondLoraStrength = draft.secondLoraStrength
        selectedSecondCharacter = draft.secondCharacterId
        styleTags = draft.styleTags
        negativePrompt = draft.negativePrompt.isEmpty ? AiDrawDefaults.defaultNegativePrompt : draft.negativePrompt
        styleNotes = draft.styleNotes
        loadedDraftUpdatedAt = draft.updatedAt
        draftLoaded = true
        isApplyingDraft = false
    }

    private func applyGeneratedStyleReset() {
        var nextStyleTags = styleTags
        var nextPositivePrompt = positivePrompt
        var nextStyleNotes = styleNotes
        AiDrawEditorDraftSync.resetGeneratedStyleState(
            styleTags: &nextStyleTags,
            positivePrompt: &nextPositivePrompt,
            styleNotes: &nextStyleNotes
        )
        styleTags = nextStyleTags
        positivePrompt = nextPositivePrompt
        styleNotes = nextStyleNotes
    }

    private func resetGeneratedStyleStateForNextJob() {
        isApplyingDraft = true
        applyGeneratedStyleReset()
        enabledStylePresetNames = []
        loadedDraftUpdatedAt = nil
        isApplyingDraft = false
    }

    private func refreshEnabledStylePresets() {
        #if DEBUG
        if AiDrawDraftStore.isUsingPreviewStorage {
            enabledStylePresetNames = []
            return
        }
        #endif
        enabledStylePresetNames = AiAssetBrowserCacheStore.enabledStyleDisplayNames()
    }

    private func saveDraft() {
        guard draftLoaded, !isApplyingDraft else { return }
        AiDrawDraftStore.updateFromForm(
            promptCn: promptCn,
            promptPositive: positivePrompt,
            width: width,
            height: height,
            steps: steps,
            cfg: cfg,
            nsfwMode: nsfwMode,
            nsfwVisibilityLevel: nsfwVisibilityLevel,
            generationMode: generationMode,
            checkpoint: selectedCheckpoint,
            loraName: selectedLora,
            loraStrength: loraStrength,
            characterId: selectedCharacter,
            secondLoraName: selectedSecondLora,
            secondLoraStrength: secondLoraStrength,
            secondCharacterId: selectedSecondCharacter,
            styleTags: styleTags,
            negativePrompt: negativePrompt,
            styleNotes: styleNotes
        )
    }

    private var isDefaultNegativePrompt: Bool {
        negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines) == AiDrawDefaults.defaultNegativePrompt
    }
}

private enum AiCanvasPreset: String, CaseIterable, Identifiable {
    case portrait
    case square
    case landscape
    case tall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portrait: "竖图"
        case .square: "方图"
        case .landscape: "横图"
        case .tall: "长竖图"
        }
    }

    var width: Int {
        switch self {
        case .portrait: 768
        case .square: 1024
        case .landscape: 1024
        case .tall: 832
        }
    }

    var height: Int {
        switch self {
        case .portrait: 1024
        case .square: 1024
        case .landscape: 768
        case .tall: 1216
        }
    }

    var systemImage: String {
        switch self {
        case .portrait: "rectangle.portrait"
        case .square: "square"
        case .landscape: "rectangle"
        case .tall: "rectangle.portrait.fill"
        }
    }
}

enum AiDrawDefaults {
    static let defaultNegativePrompt = "low quality, worst quality, bad anatomy, bad hands, extra fingers, missing fingers, deformed, blurry, text, watermark, logo, cropped"
}

private enum AiDrawPromptPreparationError: LocalizedError {
    case missingTranslationId
    case translationFailed(String?)
    case translationTimedOut

    var errorDescription: String? {
        switch self {
        case .missingTranslationId:
            return "暂时无法开始理解画面"
        case .translationFailed(let message):
            return message ?? "画面理解失败"
        case .translationTimedOut:
            return "画面理解等待时间过长"
        }
    }
}

#if DEBUG
#Preview("AI 绘画 · 390 · 深色大字") {
    SetuFeaturePreviewHost { environment, _ in
        AiDrawView(environment: environment)
    }
    .frame(width: 390, height: 844)
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .xxLarge)
}
#endif
