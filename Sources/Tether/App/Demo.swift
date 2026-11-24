import AppKit
import SwiftUI

/// Sample content and scripted scenes for screenshots. Nothing here runs in normal use:
/// it needs TETHER_DATA_DIR (a scratch data folder) together with TETHER_DEMO=1.
///
///   TETHER_DATA_DIR=/tmp/tether-demo TETHER_DEMO=1 TETHER_SCENE=node1 \
///   TETHER_SNAPSHOT=/tmp/shot.png Tether.app/Contents/MacOS/Tether
@MainActor
enum Demo {
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    static var isActive: Bool { env["TETHER_DATA_DIR"] != nil && env["TETHER_DEMO"] == "1" }

    static var windowSize: NSSize? {
        guard let parts = env["TETHER_WINDOW"]?.split(separator: "x"), parts.count == 2,
              let w = Double(parts[0]), let h = Double(parts[1]) else { return nil }
        return NSSize(width: w, height: h)
    }

    /// Fills an empty demo folder with fictional Spaces.
    static func prepare(store: Store, ui: AppUI) {
        guard isActive, store.accounts.isEmpty else { return }
        seed(store)
    }

    static func runScene(store: Store, ui: AppUI, editor: EditorController, window: NSWindow) {
        guard isActive else { return }
        let scene = env["TETHER_SCENE"] ?? "home"
        let studio = store.loggedInSpaces.first
        func open(_ index: Int) {
            guard let studio, studio.nodes.indices.contains(index) else { return }
            store.switchTo(studio.id)
            studio.open(studio.nodes[index].id)
        }
        switch scene {
        case "login":
            for id in store.session.loggedIn { store.logOut(id) }
        case "reset":
            for id in store.session.loggedIn { store.logOut(id) }
            ui.demoResetPassword = true
        case "setup":
            try? store.signUp(username: "atelier", password: "demo", email: "")
        case "home":
            studio?.activeTab = nil
        case "node0": open(0)
        case "node1": open(1)
        case "node2": open(2)
        case "insert":
            open(0)
            ui.demoInsertMenu = true
        case "settings":
            open(1)
            ui.settingsTab = SettingsTab(rawValue: env["TETHER_SETTINGS_TAB"] ?? "") ?? .appearance
            ui.overlay = .settings
        case "addaccount":
            studio?.activeTab = nil
            ui.overlay = .addAccount
        case "selftest":
            selfTest(store: store, editor: editor)
        case "authtest":
            authTest(store: store)
        default:
            break
        }
        if let offset = env["TETHER_SCROLL"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { scroll(window, by: offset) }
        }
        guard let path = env["TETHER_SNAPSHOT"] else { return }
        let delay = Double(env["TETHER_SNAPSHOT_DELAY"] ?? "") ?? 2.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            snapshot(window, to: path)
            NSApp.terminate(nil)
        }
    }

    /// Scrolls the tallest scroll view in the window (the page) down by `offset` points.
    private static func scroll(_ window: NSWindow, by offset: Double) {
        func find(_ view: NSView) -> [NSScrollView] {
            var result = (view as? NSScrollView).map { [$0] } ?? []
            for sub in view.subviews { result += find(sub) }
            return result
        }
        guard let content = window.contentView,
              let target = find(content).max(by: { $0.frame.height * $0.frame.width < $1.frame.height * $1.frame.width }) else { return }
        target.contentView.scroll(to: NSPoint(x: 0, y: offset))
        target.reflectScrolledClipView(target.contentView)
    }

    /// Captures the app's own window (no screen-recording permission needed for own windows).
    private static func snapshot(_ window: NSWindow, to path: String) {
        let id = CGWindowID(window.windowNumber)
        if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution]),
           let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            return
        }
        if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Drives the editor the way a person would (type, style, insert at the caret, keep typing)
    /// and logs the resulting document, so the editing paths can be checked without a human.
    private static func selfTest(store: Store, editor: EditorController) {
        guard let space = store.loggedInSpaces.first else { return }
        store.switchTo(space.id)
        let node = space.addNode()
        node.title = "Self test"
        func after(_ seconds: Double, _ work: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
        func select(_ text: String, in view: TetherTextView) {
            view.setSelectedRange((view.string as NSString).range(of: text))
        }
        after(0.6) {
            editor.focus(node.blocks[0].id, atEnd: true)
            guard let view = editor.activeTextView else { print("selftest: no active text view"); return }
            view.insertText("Heading line\nA second paragraph that is long enough to wrap around the page so the block has to grow taller as more text is typed into it, which is exactly what should happen here.\n한글도 굵게 기울여서 써 봅니다.\nLast line before the table.", replacementRange: view.selectedRange())
            select("Heading line", in: view)
            view.applyPreset(.heading)
            select("long enough to wrap", in: view)
            view.toggle(\.bold)
            select("grow taller", in: view)
            view.mutateStyle { $0.color = TextPalette.text[4] }
            select("exactly what should happen", in: view)
            view.mutateStyle { $0.highlight = TextPalette.highlight[0] }
            select("굵게 기울여서", in: view)
            view.toggle(\.bold)
            view.toggle(\.italic)
            select("typed into it", in: view)
            view.toggle(\.strike)
            view.toggle(\.underline)
            // Caret at the end of the Korean line, then insert a table there.
            let range = (view.string as NSString).range(of: "써 봅니다.")
            view.setSelectedRange(NSRange(location: range.location + range.length, length: 0))
            editor.insert(Block(kind: .table, table: .blank(rows: 2, columns: 3)), into: node)
        }
        after(1.4) {
            print("selftest: blocks =", node.blocks.map { $0.data.kind.rawValue })
            editor.activeTextView?.insertText("Typed right after inserting. ", replacementRange: NSRange(location: 0, length: 0))
            print("selftest: active block is tail =", editor.activeTextView?.blockID == node.blocks.last?.id)
            for block in node.blocks where block.data.kind == .text {
                print("selftest: text =", block.plainText.replacingOccurrences(of: "\n", with: "⏎"))
                print("selftest: styled runs =", (block.data.runs ?? []).filter { $0.b != nil || $0.i != nil || $0.c != nil || $0.h != nil || $0.s != nil || $0.z != nil }.map { "\($0.t.prefix(14))[b\($0.b ?? false) i\($0.i ?? false) s\($0.s ?? false) u\($0.u ?? false) c\($0.c ?? "-") h\($0.h ?? "-") z\($0.z ?? 0)]" })
            }
        }
        after(2.0) {
            // Remove the table again: the two halves should merge back into one block.
            if let table = node.blocks.first(where: { $0.data.kind == .table }), ProcessInfo.processInfo.environment["TETHER_SELFTEST_MERGE"] == "1" {
                space.deleteBlock(table.id, in: node)
                print("selftest: after delete blocks =", node.blocks.map { $0.data.kind.rawValue }, "text =", node.plainText.replacingOccurrences(of: "\n", with: "⏎"))
            }
        }
    }

    /// Exercises sign-out, wrong and right passwords, duplicate names and the account limit.
    private static func authTest(store: Store) {
        func attempt(_ label: String, _ work: () throws -> Void) {
            do { try work(); print("authtest: \(label) → ok") } catch { print("authtest: \(label) → \(error)") }
        }
        let first = store.session.loggedIn[0]
        store.logOut(first)
        print("authtest: signed in after sign-out =", store.session.loggedIn.count, "active is another space =", store.session.active != first)
        attempt("wrong password") { try store.signIn(username: "studio", password: "nope") }
        attempt("unknown user") { try store.signIn(username: "nobody", password: "demo") }
        attempt("right password (case-insensitive name)") { try store.signIn(username: "Studio", password: "demo") }
        print("authtest: nodes restored =", store.activeSpace?.nodes.count ?? -1, "active =", store.activeSpace?.info.name ?? "-")
        attempt("duplicate username") { try store.signUp(username: "studio", password: "x", email: "") }
        for index in store.accounts.count..<AppInfo.maxAccounts {
            attempt("create account #\(index + 1)") { try store.signUp(username: "space\(index + 1)", password: "demo", email: "") }
        }
        attempt("create account #\(AppInfo.maxAccounts + 1)") { try store.signUp(username: "overflow", password: "demo", email: "") }
        print("authtest: accounts =", store.accounts.count, "signed in =", store.session.loggedIn.count)
        if let studio = store.account(named: "studio") {
            let nodesBefore = store.spaces[studio.id]?.nodes.count ?? -1
            attempt("reset password") { try store.setPassword(for: studio.id, to: "fresh-pass") }
            attempt("reset to empty password") { try store.setPassword(for: studio.id, to: "") }
            store.logOut(studio.id)
            attempt("old password after reset") { try store.signIn(username: "studio", password: "demo") }
            attempt("new password after reset") { try store.signIn(username: "studio", password: "fresh-pass") }
            print("authtest: nodes kept across reset =", store.spaces[studio.id]?.nodes.count == nodesBefore, "· Mac owner check available =", MacAuth.isAvailable)
        }
        let stored = (try? String(contentsOf: store.dataDir.appendingPathComponent("accounts.json"), encoding: .utf8)) ?? ""
        print("authtest: plain password on disk =", stored.contains("\"demo\""))
    }

    // MARK: Sample content

    private static func seed(_ store: Store) {
        let korean = AppSettings.shared.language == .ko
        func t(_ en: String, _ ko: String) -> String { korean ? ko : en }

        try? store.signUp(username: "studio", password: "demo", email: "")
        try? store.signUp(username: "journal", password: "demo", email: "")
        try? store.signUp(username: "reading", password: "demo", email: "")
        let spaces = store.loggedInSpaces
        guard spaces.count == 3 else { return }

        spaces[1].info = SpaceInfo(name: t("Journal", "저널"), subtitle: t("Daily notes", "매일의 기록"), symbol: "leaf.fill", colorIndex: 3, isConfigured: true)
        spaces[2].info = SpaceInfo(name: t("Reading", "독서"), subtitle: t("Books and ideas", "책과 아이디어"), symbol: "book.fill", colorIndex: 5, isConfigured: true)

        let studio = spaces[0]
        studio.info = SpaceInfo(name: t("Studio", "스튜디오"), subtitle: t("Side projects & collaborators", "사이드 프로젝트와 협업"),
                                about: t("Plans, numbers and the people involved — kept in one place and linked together.",
                                         "계획과 수치, 함께하는 사람들을 한곳에 모아 서로 연결해 둔 공간."),
                                symbol: "sparkles", colorIndex: 0, isConfigured: true)

        // Node 3 first, so nodes 1 and 2 can link to its values.
        let attention = ChartPoint(label: t("Responsiveness", "응답 속도"), value: 55, colorSlot: 0)
        let depth = ChartPoint(label: t("Feedback depth", "피드백 깊이"), value: 40, colorSlot: 1)
        let trust = ChartPoint(label: t("Autonomy given", "맡겨주는 정도"), value: 35, colorSlot: 2)
        let signals = Block(kind: .chart, chart: ChartData(title: t("Collaboration signals", "협업 신호"), style: .bar, points: [attention, depth, trust]))
        let hours = Block(kind: .chart, chart: ChartData(title: t("Focus hours per week", "주간 집중 시간"), style: .line, points: [
            ChartPoint(label: "W1", value: 9, colorSlot: 0), ChartPoint(label: "W2", value: 12, colorSlot: 1), ChartPoint(label: "W3", value: 11, colorSlot: 2),
            ChartPoint(label: "W4", value: 15, colorSlot: 3), ChartPoint(label: "W5", value: 14, colorSlot: 4), ChartPoint(label: "W6", value: 18, colorSlot: 5),
        ]))
        let board = NodeDoc(title: t("Signals Board", "신호 보드"), symbol: "chart.bar", blocks: [
            Block(kind: .text, runs: [
                TextRun(t: t("Numbers that other nodes feed. ", "다른 노드가 채워 주는 수치들. ")),
                TextRun(t: t("Linked values update on their own", "링크된 값은 스스로 갱신돼요"), b: true),
                TextRun(t: t(" when an action is completed elsewhere.", " — 다른 곳에서 액션을 완료하면요.")),
            ]),
            signals,
            Block(kind: .text, runs: [TextRun(t: t("Time is the other half of the picture:", "나머지 절반은 시간이에요:"))]),
            hours,
            Block(kind: .text),
        ])

        let split = Block(kind: .chart, chart: ChartData(title: t("Where the effort goes", "노력의 배분"), style: .pie, points: [
            ChartPoint(label: t("Design", "디자인"), value: 35, colorSlot: 0), ChartPoint(label: t("Build", "개발"), value: 40, colorSlot: 1),
            ChartPoint(label: t("Testing", "테스트"), value: 15, colorSlot: 2), ChartPoint(label: t("Writing", "문서"), value: 10, colorSlot: 3),
        ]))
        func row(_ cells: [String]) -> [TableCell] { cells.map { TableCell(text: $0) } }
        let readiness = TableCell(text: "60")
        let milestones = Block(kind: .table, table: TableData(title: t("Milestones", "마일스톤"), hasHeader: true, rows: [
            row([t("Milestone", "마일스톤"), t("Owner", "담당"), t("Due", "기한"), t("Readiness", "준비도")]),
            row([t("Prototype", "프로토타입"), "Mina", t("Mar 14", "3월 14일")]) + [readiness],
            row([t("Private beta", "비공개 베타"), "Jordan", t("Apr 02", "4월 2일"), "35"]),
            row([t("Public launch", "정식 출시"), t("Everyone", "전원"), t("May 20", "5월 20일"), "10"]),
        ]))
        let plan = NodeDoc(title: t("Launch Plan", "출시 계획"), symbol: "flag", blocks: [
            Block(kind: .text, runs: [
                TextRun(t: t("Goal\n", "목표\n"), b: true, z: 21),
                TextRun(t: t("Ship a small, ", "작지만 ")),
                TextRun(t: t("polished", "완성도 높은"), b: true),
                TextRun(t: t(" first version before summer. Keep the scope ", " 첫 버전을 여름 전에 내놓기. 범위는 ")),
                TextRun(t: t("deliberately narrow", "의도적으로 좁게"), i: true, h: "FFE0408C"),
                TextRun(t: t(" and cut anything that is ", " 유지하고, ")),
                TextRun(t: t("nice to have", "있으면 좋은 것"), s: true),
                TextRun(t: t(" rather than essential.\n\n", "은 과감히 덜어내기.\n\n")),
                TextRun(t: t("Milestones\n", "마일스톤\n"), b: true, z: 21),
                TextRun(t: t("Each row is a checkpoint; readiness is a rough 0–100 guess.", "각 행은 체크포인트, 준비도는 0–100의 대략적인 감이에요.")),
            ]),
            milestones,
            Block(kind: .text, runs: [
                TextRun(t: t("Effort\n", "노력\n"), b: true, z: 21),
                TextRun(t: t("Roughly how the hours split this month — ", "이번 달 시간이 대략 어떻게 나뉘는지 — ")),
                TextRun(t: t("build still dominates", "아직은 개발 비중이 가장 커요"), c: "4080F2"),
                TextRun(t: "."),
            ]),
            split,
            Block(kind: .text, runs: [TextRun(t: t("Next: tighten the beta checklist and confirm dates with the team.", "다음: 베타 체크리스트를 다듬고 팀과 일정 확정하기."))]),
        ])

        let boardRef = { (point: ChartPoint) in ValueRef(nodeID: board.id, blockID: signals.id, itemID: point.id) }
        let profile = Block(kind: .analytics, analytics: AnalyticsData(
            name: "Jordan Lee",
            relation: t("Project mentor", "프로젝트 멘토"),
            baseScore: 58,
            traits: [Tag(text: t("Direct", "직설적")), Tag(text: t("Detail-oriented", "꼼꼼함")), Tag(text: t("Morning person", "아침형")), Tag(text: t("Values preparation", "준비성을 중시"))],
            likes: [Tag(text: t("Short written updates", "짧은 서면 공유")), Tag(text: t("Concrete questions", "구체적인 질문")), Tag(text: t("Early drafts", "이른 초안 공유"))],
            cautions: [Tag(text: t("Last-minute changes", "막판 변경")), Tag(text: t("Vague status", "모호한 진행 상황"))],
            attitude: t("Supportive but still evaluating. Replies quickly when I send something specific, slower when the ask is open-ended. Started sharing unprompted feedback after the second demo — a good sign.",
                        "지지해 주지만 아직은 지켜보는 단계. 구체적인 내용을 보내면 답이 빠르고, 막연한 요청에는 느려요. 두 번째 데모 이후로 먼저 피드백을 주기 시작했는데, 좋은 신호예요."),
            observations: [
                LogEntry(date: Date().addingTimeInterval(-86400 * 9), text: t("Asked for a written summary instead of a call.", "통화 대신 서면 요약을 요청함."), impact: 0),
                LogEntry(date: Date().addingTimeInterval(-86400 * 5), text: t("Shared two pages of notes on the prototype without being asked.", "요청하지 않았는데 프로토타입에 대한 메모 두 쪽을 공유해 줌."), impact: 1),
                LogEntry(date: Date().addingTimeInterval(-86400 * 2), text: t("Seemed frustrated when the scope changed mid-week.", "주중에 범위가 바뀌자 답답해하는 기색."), impact: -1),
            ],
            actions: [
                ActionItem(title: t("Bring one prepared question to each sync", "싱크마다 준비한 질문 하나 가져가기"), target: 4, progress: 4, scoreDelta: 10,
                           effects: [LinkEffect(target: boardRef(attention), delta: 15)]),
                ActionItem(title: t("Send a weekly progress note", "주간 진행 노트 보내기"), target: 3, progress: 2, scoreDelta: 8,
                           effects: [LinkEffect(target: boardRef(depth), delta: 20)]),
                ActionItem(title: t("Share the beta draft a week early", "베타 초안을 일주일 먼저 공유"), target: 1, progress: 0, scoreDelta: 12,
                           effects: [LinkEffect(target: boardRef(trust), delta: 25),
                                     LinkEffect(target: ValueRef(nodeID: plan.id, blockID: milestones.id, itemID: readiness.id), delta: 15)]),
            ]))
        let people = NodeDoc(title: t("Working with Jordan", "Jordan과 함께 일하기"), symbol: "person.2", blocks: [
            Block(kind: .text, runs: [
                TextRun(t: t("What I've noticed so far, and what I plan to do about it. Completing an action below raises the score here and pushes the linked numbers on the ",
                             "지금까지 관찰한 것과 앞으로의 계획. 아래 액션을 완료하면 이곳의 점수가 오르고, ")),
                TextRun(t: t("Signals Board", "신호 보드"), b: true),
                TextRun(t: t(".", "의 링크된 수치도 함께 올라가요.")),
            ]),
            profile,
            Block(kind: .text, runs: [TextRun(t: t("Review this again after the next sync.", "다음 싱크 후에 다시 검토하기."), i: true)]),
        ])

        let nodes = [plan, people, board].map(NodeModel.init)
        studio.nodes = nodes
        studio.openTabs = nodes.map(\.id)
        studio.activeTab = nil
        studio.links = [
            RefLink(from: Anchor(nodeID: people.id, blockID: nil), to: Anchor(nodeID: plan.id, blockID: nil)),
            RefLink(from: Anchor(nodeID: plan.id, blockID: milestones.id), to: Anchor(nodeID: board.id, blockID: hours.id)),
            RefLink(from: Anchor(nodeID: board.id, blockID: signals.id), to: Anchor(nodeID: people.id, blockID: profile.id)),
        ]
        store.switchTo(studio.id)
        store.flushAll()
    }
}
