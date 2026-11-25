import SwiftUI

/// Settings › AI: which services are connected, what models may do, skills and MCP servers.
struct AISettingsView: View {
    @Environment(AIStore.self) private var ai
    @Environment(MCPHub.self) private var mcp
    @Environment(\.colorScheme) private var scheme
    @State private var editingSkill: UUID?
    @State private var addingServer = false

    var body: some View {
        @Bindable var ai = ai
        Group {
            heading(L("AI", "AI"),
                    L("Connect Claude, ChatGPT, Gemini or a local model. They share each Space's nodes, the conversations and one memory, so you can switch models in the middle of a conversation.",
                      "Claude, ChatGPT, Gemini 또는 로컬 모델을 연결하세요. Space의 노드와 대화, 하나의 메모리를 함께 쓰기 때문에 대화 도중에 모델을 바꿔도 이어서 이야기할 수 있어요."))
            card {
                ForEach(Array(AIProviderKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { divider }
                    ProviderRow(kind: kind)
                }
            }
            Text(L("Keys are kept in the macOS Keychain, not in Tether's data folder. Each service bills its API by use, separately from a ChatGPT, Claude or Gemini subscription. When you send a message, the conversation, the shared memory, the titles of the Space's nodes, the open node and whatever nodes the model chooses to read go to the service you picked. Local models stay on this Mac.",
                   "키는 Tether 데이터 폴더가 아니라 macOS 키체인에 보관돼요. 요금은 각 서비스의 API 사용량 기준이며 ChatGPT · Claude · Gemini 구독과는 별개예요. 메시지를 보내면 대화, 공유 메모리, Space의 노드 제목, 열린 노드, 그리고 모델이 읽기로 한 노드가 선택한 서비스로 전송돼요. 로컬 모델은 이 Mac 밖으로 나가지 않아요."))
                .font(.app(11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)

            heading(L("What models may do", "모델이 할 수 있는 일"), nil)
            card {
                ForEach(Array(AIPermission.allCases.enumerated()), id: \.element) { index, option in
                    if index > 0 { divider }
                    Button {
                        withAnimation(Motion.snappy) { ai.settings.permission = option }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: option.symbol)
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                                .frame(width: 26, height: 26)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent.opacity(0.14)))
                            Text(option.title).font(.app(13, .medium))
                            Spacer()
                            if ai.settings.permission == option {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            heading(L("Skills", "스킬"),
                    L("Reusable instructions. Every model can use them: pick one in the composer, or a model loads the one that fits.",
                      "다시 쓰는 지시문이에요. 어떤 모델이든 쓸 수 있어요. 입력창에서 고르거나, 요청에 맞는 것을 모델이 스스로 불러와요."))
            card {
                ForEach(Array(ai.settings.skills.enumerated()), id: \.element.id) { index, skill in
                    if index > 0 { divider }
                    skillRow(skill)
                }
                if !ai.settings.skills.isEmpty { divider }
                addRow(L("New Skill", "새 스킬")) {
                    let skill = AISkill(name: L("New skill", "새 스킬"), summary: "", instructions: "")
                    withAnimation(Motion.spring) {
                        ai.settings.skills.append(skill)
                        editingSkill = skill.id
                    }
                }
            }

            heading(L("MCP servers", "MCP 서버"),
                    L("Tools from Model Context Protocol servers, offered to every model. A local server is a command started on this Mac; a remote one is an address. Servers that need sign-in are not supported yet.",
                      "Model Context Protocol 서버의 도구를 모든 모델에게 제공해요. 로컬 서버는 이 Mac에서 실행하는 명령, 원격 서버는 주소로 연결해요. 로그인이 필요한 서버는 아직 지원하지 않아요."))
            card {
                ForEach(Array(ai.settings.servers.enumerated()), id: \.element.id) { index, server in
                    if index > 0 { divider }
                    ServerRow(server: server)
                }
                if !ai.settings.servers.isEmpty { divider }
                addRow(L("Add Server", "서버 추가")) {
                    withAnimation(Motion.spring) {
                        ai.settings.servers.append(MCPServerConfig(name: L("New server", "새 서버"), enabled: false))
                    }
                }
            }
        }
        .onAppear { ai.refreshAll() }
        .task { await mcp.sync(with: ai.settings.servers) }
    }

    // MARK: Building blocks

    private func heading(_ title: String, _ subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.app(16, .bold))
            if let subtitle {
                Text(subtitle).font(.app(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }.card()
    }

    private var divider: some View {
        Rectangle().fill(Theme.cardStroke(scheme)).frame(height: 1).padding(.leading, 14)
    }

    private func addRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent.opacity(0.14)))
                Text(title).font(.app(13, .medium))
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func skillRow(_ skill: AISkill) -> some View {
        let open = editingSkill == skill.id
        func binding(_ path: WritableKeyPath<AISkill, String>) -> Binding<String> {
            Binding(get: { ai.settings.skills.first { $0.id == skill.id }?[keyPath: path] ?? "" },
                    set: { value in
                        if let index = ai.settings.skills.firstIndex(where: { $0.id == skill.id }) { ai.settings.skills[index][keyPath: path] = value }
                    })
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(skill.name.isEmpty ? L("Untitled skill", "이름 없는 스킬") : skill.name).font(.app(13, .medium))
                    if !skill.summary.isEmpty { Text(skill.summary).font(.app(11.5)).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 8)
                IconButton(symbol: open ? "chevron.up" : "pencil", size: 11, help: open ? L("Done", "완료") : L("Edit", "편집")) {
                    withAnimation(Motion.spring) { editingSkill = open ? nil : skill.id }
                }
                IconButton(symbol: "trash", size: 11, tint: Theme.negative, help: L("Delete", "삭제")) {
                    withAnimation(Motion.spring) { ai.settings.skills.removeAll { $0.id == skill.id } }
                }
            }
            if open {
                GlassField(placeholder: L("Name", "이름"), text: binding(\.name))
                GlassField(placeholder: L("One line on when to use it", "언제 쓰는지 한 줄"), text: binding(\.summary))
                TextEditor(text: binding(\.instructions))
                    .font(.app(12.5))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 120)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.fieldFill(scheme)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.cardStroke(scheme), lineWidth: 1))
                Text(L("Write what the model should do, step by step, as you would brief a colleague.", "동료에게 설명하듯, 모델이 해야 할 일을 순서대로 적어 주세요."))
                    .font(.app(11)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

/// One service: its state, and the field that connects it.
private struct ProviderRow: View {
    let kind: AIProviderKind
    @Environment(AIStore.self) private var ai
    @Environment(\.colorScheme) private var scheme
    @State private var key = ""
    @State private var address = ""

    private var state: (text: String, tint: Color?) {
        switch ai.connection[kind] ?? .unknown {
        case .checking:
            return (L("Checking…", "확인 중…"), nil)
        case .failed(let message):
            return (message, Theme.negative)
        case .connected:
            return (L("Connected · \((ai.models[kind] ?? []).count) models", "연결됨 · 모델 \((ai.models[kind] ?? []).count)개"), Theme.positive)
        case .unknown:
            if ai.isReady(kind) { return (L("Connected · \((ai.models[kind] ?? []).count) models", "연결됨 · 모델 \((ai.models[kind] ?? []).count)개"), Theme.positive) }
            return (kind.needsKey ? L("Not connected", "연결 안 됨") : L("Not checked yet", "아직 확인 안 함"), nil)
        }
    }

    var body: some View {
        let hasKey = kind.needsKey && ai.hasKey(kind)
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ProviderBadge(provider: kind, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(kind.title).font(.app(13.5, .semibold))
                        Text(kind == .ollama ? L("local models on this Mac", "이 Mac의 로컬 모델") : kind.company).font(.app(11)).foregroundStyle(.tertiary)
                    }
                    Text(state.text).font(.app(11.5)).foregroundStyle(state.tint ?? .secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                if let page = kind.keyPage {
                    Button { NSWorkspace.shared.open(page) } label: {
                        Label(kind.needsKey ? L("Get a key", "키 발급") : L("Get Ollama", "Ollama 받기"), systemImage: "arrow.up.right").font(.app(11.5, .medium))
                    }
                    .buttonStyle(SoftButtonStyle())
                }
            }
            HStack(spacing: 8) {
                if kind.needsKey {
                    GlassField(symbol: "key", placeholder: hasKey ? L("A key is saved — paste a new one to replace it", "키가 저장돼 있어요 — 바꾸려면 새 키를 붙여 넣으세요")
                                                                   : L("Paste your \(kind.company) API key", "\(kind.company) API 키를 붙여 넣으세요"),
                               text: $key, secure: true, onSubmit: connect)
                    Button(hasKey && key.isEmpty ? L("Check", "확인") : L("Connect", "연결"), action: connect)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!hasKey && key.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasKey {
                        Button(L("Remove", "삭제")) {
                            key = ""
                            withAnimation(Motion.snappy) { ai.saveKey(nil, for: kind) }
                        }
                        .buttonStyle(SoftButtonStyle(tint: Theme.negative))
                    }
                } else {
                    GlassField(symbol: "network", placeholder: kind.defaultBaseURL, text: $address, onSubmit: connect)
                    Button(L("Check", "확인"), action: connect).buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onAppear { address = ai.settings.baseURLs[kind.rawValue] ?? "" }
    }

    private func connect() {
        if kind.needsKey {
            if !key.trimmingCharacters(in: .whitespaces).isEmpty {
                ai.saveKey(key, for: kind)
                key = ""
            }
        } else {
            ai.settings.baseURLs[kind.rawValue] = address.trimmingCharacters(in: .whitespaces)
        }
        Task { await ai.refreshModels(kind) }
    }
}

/// One MCP server: what to run or where to reach it, and whether it answered.
private struct ServerRow: View {
    let server: MCPServerConfig
    @Environment(AIStore.self) private var ai
    @Environment(MCPHub.self) private var mcp
    @Environment(\.colorScheme) private var scheme

    private func binding<Value>(_ path: WritableKeyPath<MCPServerConfig, Value>, _ fallback: Value) -> Binding<Value> {
        Binding(get: { ai.settings.servers.first { $0.id == server.id }?[keyPath: path] ?? fallback },
                set: { value in
                    if let index = ai.settings.servers.firstIndex(where: { $0.id == server.id }) { ai.settings.servers[index][keyPath: path] = value }
                })
    }

    private var state: (text: String, tint: Color?) {
        guard server.enabled else { return (L("Off", "꺼짐"), nil) }
        switch mcp.status[server.id] ?? .idle {
        case .idle: return (L("Not connected yet", "아직 연결 안 함"), nil)
        case .connecting: return (L("Connecting…", "연결 중…"), nil)
        case .connected(let count): return (L("Connected · \(count) tools", "연결됨 · 도구 \(count)개"), Theme.positive)
        case .failed(let message): return (message, Theme.negative)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 1) {
                    TextField(L("Name", "이름"), text: binding(\.name, ""))
                        .textFieldStyle(.plain).font(.app(13, .medium))
                    Text(state.text).font(.app(11.5)).foregroundStyle(state.tint ?? .secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(get: { server.enabled }, set: { on in
                    binding(\.enabled, false).wrappedValue = on
                    Task { await mcp.sync(with: ai.settings.servers) }
                }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                IconButton(symbol: "trash", size: 11, tint: Theme.negative, help: L("Delete", "삭제")) {
                    mcp.disconnect(server.id)
                    withAnimation(Motion.spring) { ai.settings.servers.removeAll { $0.id == server.id } }
                }
            }
            HStack(spacing: 8) {
                SlidingPicker(options: [(MCPServerConfig.Transport.stdio, L("Local", "로컬"), nil), (MCPServerConfig.Transport.http, L("Remote", "원격"), nil)],
                              selection: binding(\.transport, .stdio))
                if server.transport == .stdio {
                    GlassField(symbol: "terminal", placeholder: "npx -y @modelcontextprotocol/server-filesystem ~/Documents", text: binding(\.command, ""), onSubmit: reconnect)
                } else {
                    GlassField(symbol: "network", placeholder: "https://example.com/mcp", text: binding(\.url, ""), onSubmit: reconnect)
                }
                Button(L("Connect", "연결"), action: reconnect).buttonStyle(SoftButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func reconnect() {
        binding(\.enabled, false).wrappedValue = true
        guard let current = ai.settings.servers.first(where: { $0.id == server.id }) else { return }
        Task { await mcp.connect(current) }
    }
}
