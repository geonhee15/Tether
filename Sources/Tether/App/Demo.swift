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
            store.selectSpace(studio.id)
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
        case "account":
            studio?.activeTab = nil
            ui.overlay = .account
        case "spacesettings":
            studio?.activeTab = nil
            ui.overlay = .spaceSettings
        case "newspace":
            if let account = store.activeAccount { _ = try? store.addSpace(to: account.id) }
        case "spacetest":
            spaceTest(store: store)
        case "cattest":
            categoryTest(store: store)
        case "node0": open(0)
        case "node1": open(1)
        case "node2": open(2)
        case "file": open(3)
        case "filetest":
            fileTest(store: store)
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
        case "undotest":
            undoTest(store: store, editor: editor)
        case "awake":
            studio?.activeTab = nil
            ui.setAwake(true)
        case "awaketest":
            awakeTest(ui: ui)
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
        store.selectSpace(space.id)
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

    /// Makes five separate edits (new node, typing twice, inserting a table, filling a cell), then
    /// undoes and redoes them and checks a deleted node comes back. Prints the state at each step.
    private static func undoTest(store: Store, editor: EditorController) {
        guard let space = store.loggedInSpaces.first else { return }
        store.selectSpace(space.id)
        let before = space.nodes.count
        var node: NodeModel?
        func after(_ seconds: Double, _ work: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
        func state(_ label: String) {
            let current = node.flatMap { space.node($0.id) }
            let kinds = current?.blocks.map { $0.data.kind.rawValue }.joined(separator: ",") ?? "-"
            let text = current?.plainText.replacingOccurrences(of: "\n", with: "⏎") ?? "-"
            let cell = current?.blocks.first { $0.data.kind == .table }?.data.table?.rows[0][0].text ?? "-"
            print("undotest: \(label) → nodes \(space.nodes.count - before) · blocks [\(kinds)] · text “\(text)” · cell “\(cell)”")
        }
        after(0.5) {
            node = space.addNode()
            node?.title = "Undo test"
        }
        after(1.3) {
            guard let node else { return }
            editor.focus(node.blocks[0].id, atEnd: true)
            editor.activeTextView?.insertText("Hello", replacementRange: NSRange(location: 0, length: 0))
        }
        after(2.1) { editor.activeTextView?.insertText(" world", replacementRange: NSRange(location: 5, length: 0)) }
        after(2.9) {
            guard let node else { return }
            editor.insert(Block(kind: .table, table: .blank(rows: 2, columns: 2)), into: node)
        }
        after(3.7) {
            node?.blocks.first { $0.data.kind == .table }?.data.table?.rows[0][0].text = "42"
        }
        after(4.5) {
            state("after 5 edits")
            for step in 1...5 {
                let ok = store.undo(in: space)
                state("undo \(step) (\(ok ? "ok" : "nothing"))")
            }
            print("undotest: undo past the start →", store.undo(in: space) ? "changed something (wrong)" : "nothing left (right)")
            for step in 1...5 {
                let ok = store.redo(in: space)
                state("redo \(step) (\(ok ? "ok" : "nothing"))")
            }
        }
        after(5.3) {
            guard let node else { return }
            space.deleteNode(node.id)
        }
        after(6.1) {
            state("node deleted")
            _ = store.undo(in: space)
            state("undo delete")
            print("undotest: restored node is open =", space.activeTab == node?.id, "· saved-file check follows")
        }
        after(7.2) {
            let saved = (try? Data(contentsOf: store.dataDir.appendingPathComponent("spaces/\(space.id.uuidString).json")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let titles = (saved?["nodes"] as? [[String: Any]])?.compactMap { $0["title"] as? String } ?? []
            print("undotest: restored node saved to disk =", titles.contains("Undo test"))
        }
    }

    /// Turns keep-awake mode on and off and asks macOS whether the power assertion is really held.
    private static func awakeTest(ui: AppUI) {
        func held() -> Bool {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            task.arguments = ["-g", "assertions"]
            let pipe = Pipe()
            task.standardOutput = pipe
            try? task.run()
            task.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return output.contains("Tether keep-awake mode")
        }
        print("awaketest: before =", held())
        ui.setAwake(true)
        print("awaketest: mode on =", ui.isAwake, "· assertion held =", held())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            ui.setAwake(false)
            print("awaketest: mode off =", !ui.isAwake, "· assertion released =", !held())
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
            let nodesBefore = store.spaces(of: studio.id).first?.nodes.count ?? -1
            let spacesBefore = store.spaces(of: studio.id).count
            attempt("reset password") { try store.setPassword(for: studio.id, to: "fresh-pass") }
            attempt("reset to empty password") { try store.setPassword(for: studio.id, to: "") }
            store.logOut(studio.id)
            attempt("old password after reset") { try store.signIn(username: "studio", password: "demo") }
            attempt("new password after reset") { try store.signIn(username: "studio", password: "fresh-pass") }
            print("authtest: nodes kept across reset =", store.spaces(of: studio.id).first?.nodes.count == nodesBefore,
                  "· every Space back after sign-in =", store.spaces(of: studio.id).count == spacesBefore,
                  "· Mac owner check available =", MacAuth.isAvailable)
        }
        let stored = (try? String(contentsOf: store.dataDir.appendingPathComponent("accounts.json"), encoding: .utf8)) ?? ""
        print("authtest: plain password on disk =", stored.contains("\"demo\""))
    }

    // MARK: Sample content

    private static func seed(_ store: Store) {
        let korean = AppSettings.shared.language == .ko
        func t(_ en: String, _ ko: String) -> String { korean ? ko : en }

        // One account holding three Spaces, and a second account to switch to.
        try? store.signUp(username: "studio", password: "demo", email: "")
        guard let owner = store.activeAccount, let studio = store.activeSpace,
              let journal = try? store.addSpace(to: owner.id), let reading = try? store.addSpace(to: owner.id) else { return }
        try? store.signUp(username: "archive", password: "demo", email: "")
        let archive = store.activeSpace
        archive?.info = SpaceInfo(name: t("Archive", "보관함"), subtitle: t("Finished work", "끝난 작업들"), symbol: "briefcase.fill", colorIndex: 7, isConfigured: true)
        let spaces = [studio, journal, reading] + (archive.map { [$0] } ?? [])

        journal.info = SpaceInfo(name: t("Journal", "저널"), subtitle: t("Daily notes", "매일의 기록"), symbol: "leaf.fill", colorIndex: 3, isConfigured: true)
        reading.info = SpaceInfo(name: t("Reading", "독서"), subtitle: t("Books and ideas", "책과 아이디어"), symbol: "book.fill", colorIndex: 5, isConfigured: true)

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
        // Categories: every node is filed under one.
        let planning = studio.addCategory(named: t("Planning", "기획"))
        let peopleGroup = studio.addCategory(named: t("People", "사람"))
        let numbers = studio.addCategory(named: t("Numbers", "수치"))
        studio.updateCategory(planning.id) { $0.colorIndex = 0 }
        studio.updateCategory(peopleGroup.id) { $0.colorIndex = 6 }
        studio.updateCategory(numbers.id) { $0.colorIndex = 2 }
        nodes[0].categoryID = planning.id
        nodes[1].categoryID = peopleGroup.id
        nodes[2].categoryID = numbers.id
        // A file node, made on the spot so no binary has to live in the repository.
        if let pdf = makeSamplePDF(korean: korean), let brief = try? store.importFile(at: pdf, into: studio) {
            studio.links.append(RefLink(from: Anchor(nodeID: brief.id, blockID: nil), to: Anchor(nodeID: plan.id, blockID: nil)))
            brief.categoryID = planning.id
            brief.blocks = [BlockModel(Block(kind: .text, runs: [
                TextRun(t: t("Before the sync\n", "싱크 전에\n"), b: true, z: 17),
                TextRun(t: t("The readiness numbers here are ", "여기 준비도 수치는 ")),
                TextRun(t: t("two weeks old", "2주 전 기준"), h: "FFE0408C"),
                TextRun(t: t(" — the Launch Plan table has the current ones.\n\n", " — 최신 값은 출시 계획의 표에 있어요.\n\n")),
                TextRun(t: t("To do\n", "할 일\n"), b: true, z: 17),
                TextRun(t: t("Ask Jordan whether ", "Jordan에게 ")),
                TextRun(t: t("step 3", "3번 단계"), b: true),
                TextRun(t: t(" can move a week earlier.\n", "를 한 주 앞당길 수 있는지 묻기.\n")),
                TextRun(t: t("Trim “Why now” to two sentences.", "‘왜 지금인가’를 두 문장으로 줄이기."), i: true),
            ]))]
            try? FileManager.default.removeItem(at: pdf)
        }
        studio.activeTab = nil

        // The other Spaces get a little content of their own, so switching shows something.
        func page(_ title: String, _ symbol: String, _ text: String) -> NodeModel {
            NodeModel(NodeDoc(title: title, symbol: symbol, blocks: [Block(kind: .text, runs: [TextRun(t: text)])]))
        }
        journal.nodes = [
            page(t("This week", "이번 주"), "calendar", t("Three things that went well, one to change.", "잘된 일 세 가지, 바꿀 것 한 가지.")),
            page(t("Ideas", "아이디어"), "lightbulb", t("Loose thoughts, sorted on Sundays.", "흩어진 생각들, 일요일마다 정리.")),
        ]
        reading.nodes = [
            page(t("Reading list", "읽을 책"), "book", t("Up next, in order.", "다음에 읽을 책, 순서대로.")),
        ]
        store.switchTo(owner.id)
        store.selectSpace(studio.id)
        store.flushAll()
        for space in spaces { store.resetHistory(for: space) }
    }

    /// Checks what was read from disk (including data saved before an account could hold
    /// several Spaces), then fills an account to the limit, deletes, signs out and reloads.
    private static func spaceTest(store: Store) {
        func attempt(_ label: String, _ work: () throws -> Void) {
            do { try work(); print("spacetest: \(label) → ok") } catch { print("spacetest: \(label) → \(error)") }
        }
        for account in store.accounts {
            let loaded = store.spaces(of: account.id)
            print("spacetest: read “\(account.username)” → spaces \(account.spaceIDs.count) · first shares the account id = \(account.spaceIDs.first == account.id)",
                  "· loaded \(loaded.count) · names \(loaded.map(\.info.name)) · nodes \(loaded.map { $0.nodes.count })",
                  "· files \(loaded.map(\.fileCount)) · categories \(loaded.map { $0.categories.count })")
        }
        guard let account = store.account(named: "studio"), let first = store.spaces(of: account.id).first else { return }
        store.switchTo(account.id)
        let firstNodes = first.nodes.count
        let before = store.spaces(of: account.id).count
        var made: [SpaceModel] = []
        for number in (before + 1)...AppInfo.maxSpaces {
            attempt("add Space #\(number)") {
                let space = try store.addSpace(to: account.id)
                space.info.name = "Extra \(number)"
                space.info.isConfigured = true
                made.append(space)
            }
        }
        attempt("add Space #\(AppInfo.maxSpaces + 1)") { _ = try store.addSpace(to: account.id) }
        print("spacetest: spaces =", store.spaces(of: account.id).count, "· newest is in front =", store.activeSpace?.id == made.last?.id)
        guard made.count >= 2 else { return }
        made[0].addNode().title = "Only here"
        print("spacetest: a node added to one Space → that Space \(made[0].nodes.count) · first Space unchanged =", first.nodes.count == firstNodes)
        if let pdf = makeSamplePDF(korean: false) {
            _ = try? store.importFile(at: pdf, into: made[1])
            try? FileManager.default.removeItem(at: pdf)
        }
        let doomed = made[1]
        let doomedFiles = store.filesDirectory(for: doomed.id).path
        let doomedJSON = store.dataDir.appendingPathComponent("spaces/\(doomed.id.uuidString).json").path
        store.flushAll()
        print("spacetest: Space with a file saved → json =", FileManager.default.fileExists(atPath: doomedJSON), "· files folder =", FileManager.default.fileExists(atPath: doomedFiles))
        store.selectSpace(doomed.id)
        print("spacetest: delete it →", store.deleteSpace(doomed.id), "· spaces =", store.spaces(of: account.id).count,
              "· json gone =", !FileManager.default.fileExists(atPath: doomedJSON), "· files gone =", !FileManager.default.fileExists(atPath: doomedFiles),
              "· a neighbour is in front =", store.activeSpace != nil && store.activeSpace?.id != doomed.id)
        store.selectSpace(first.id)
        print("spacetest: select the first Space → in front =", store.activeSpace?.id == first.id, "· name", store.activeSpace?.info.name ?? "-")
        store.moveSpace(made[0].id, by: -1)
        if let single = store.accounts.first(where: { $0.spaceIDs.count == 1 }), let only = single.spaceIDs.first {
            print("spacetest: delete an account's only Space →", store.deleteSpace(only) ? "deleted (wrong)" : "refused (right)")
        }
        store.flushAll()
        // A second store reads the same folder, the way the next launch would.
        let reloaded = Store()
        let again = reloaded.spaces(of: account.id)
        print("spacetest: reloaded from disk → spaces \(again.count) · order kept =", again.map(\.id) == store.spaces(of: account.id).map(\.id),
              "· first Space nodes kept =", again.first { $0.id == first.id }?.nodes.count == firstNodes,
              "· “Only here” kept =", again.contains { $0.nodes.contains { $0.title == "Only here" } },
              "· front Space kept =", reloaded.activeSpace?.id == first.id)
        store.logOut(account.id)
        print("spacetest: signed out → loaded Spaces of the account =", store.spaces(of: account.id).count)
        attempt("sign in again") { try store.signIn(username: "studio", password: "demo") }
        print("spacetest: signed in → loaded \(store.spaces(of: account.id).count) · front Space is the first =", store.activeSpace?.id == first.id,
              "· nodes", store.activeSpace?.nodes.count ?? -1)
    }

    /// Makes categories, files nodes under them, deletes one and brings it back with Undo.
    private static func categoryTest(store: Store) {
        guard let space = store.loggedInSpaces.first, let node = space.nodes.first else { return }
        store.selectSpace(space.id)
        func after(_ seconds: Double, _ work: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
        let base = space.categories.count, nodesBefore = space.nodes.count
        let original = node.categoryID
        var alpha: NodeCategory?, beta: NodeCategory?
        func state(_ label: String) {
            let names = space.categories.dropFirst(base).map(\.name)
            print("cattest: \(label) → new categories \(names) · in Alpha \(alpha.map { space.nodes(in: $0.id).count } ?? -1)",
                  "· in Beta \(beta.map { space.nodes(in: $0.id).count } ?? -1) · unfiled \(space.nodes(in: nil).count)",
                  "· first node is in “\(space.category(of: node)?.name ?? "none")”")
        }
        state("start")
        after(0.5) {
            alpha = space.addCategory(named: "Alpha")
            beta = space.addCategory(named: "Beta")
        }
        after(1.3) {
            node.categoryID = alpha?.id
            let created = space.addNode(in: beta?.id)
            created.title = "Filed on creation"
            print("cattest: colours differ =", Set(space.categories.map(\.colorIndex)).count == min(space.categories.count, Theme.spaceColors.count),
                  "· new node went into Beta =", space.category(of: created)?.name == "Beta")
        }
        after(2.1) {
            state("filed")
            if let alpha { space.deleteCategory(alpha.id) }
        }
        after(2.9) {
            state("Alpha deleted")
            print("cattest: nodes survive the delete =", space.nodes.count == nodesBefore + 1)
            _ = store.undo(in: space)
            state("undo")
        }
        after(3.7) {
            if let beta { space.updateCategory(beta.id) { $0.name = "Renamed" } }
            if let beta { space.setCollapsed(true, category: beta.id) }
        }
        after(4.8) {
            store.flushAll()
            let saved = (try? Data(contentsOf: store.dataDir.appendingPathComponent("spaces/\(space.id.uuidString).json")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let names = (saved?["categories"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let filed = (saved?["nodes"] as? [[String: Any]])?.filter { $0["categoryID"] != nil }.count ?? -1
            print("cattest: on disk → categories \(names.dropFirst(base)) · nodes with a category \(filed) · folded \((saved?["collapsedCategories"] as? [Any])?.count ?? -1)")
            let reloaded = Store().loggedInSpaces.first { $0.id == space.id }
            print("cattest: reloaded → categories \(reloaded?.categories.count ?? -1) · first node still in “\(reloaded.flatMap { r in r.nodes.first { $0.id == node.id }.flatMap { r.category(of: $0)?.name } } ?? "none")” · was \(original == nil ? "unfiled" : "filed") at the start")
        }
    }

    /// Draws a one-page fictional brief and returns where it was written.
    private static func makeSamplePDF(korean: Bool) -> URL? {
        func t(_ en: String, _ ko: String) -> String { korean ? ko : en }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(t("Launch Brief", "출시 브리프") + ".pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        pdf.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: false)
        func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, in rect: CGRect) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                         .foregroundColor: color, .paragraphStyle: paragraph]).draw(in: rect)
        }
        let ink = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.15, alpha: 1)
        let soft = NSColor(srgbRed: 0.40, green: 0.41, blue: 0.46, alpha: 1)
        NSColor(srgbRed: 1.0, green: 0.31, blue: 0.43, alpha: 1).setFill()
        CGRect(x: 56, y: 716, width: 44, height: 5).fill()
        draw(t("Launch Brief", "출시 브리프"), size: 30, weight: .bold, color: ink, in: CGRect(x: 56, y: 660, width: 500, height: 44))
        draw(t("Studio · one page · draft 3", "스튜디오 · 1쪽 · 초안 3"), size: 12, weight: .regular, color: soft, in: CGRect(x: 56, y: 636, width: 500, height: 18))
        draw(t("Why now", "왜 지금인가"), size: 15, weight: .semibold, color: ink, in: CGRect(x: 56, y: 590, width: 500, height: 22))
        draw(t("The prototype is stable and the first testers keep coming back to it. Shipping a narrow first version before summer lets us learn from real use instead of guessing.",
               "프로토타입이 안정됐고 첫 테스터들이 계속 다시 찾고 있습니다. 여름 전에 범위를 좁힌 첫 버전을 내놓으면 추측 대신 실제 사용에서 배울 수 있습니다."),
             size: 12.5, weight: .regular, color: ink, in: CGRect(x: 56, y: 510, width: 500, height: 72))
        draw(t("Readiness by milestone", "마일스톤별 준비도"), size: 15, weight: .semibold, color: ink, in: CGRect(x: 56, y: 466, width: 500, height: 22))
        let rows: [(String, CGFloat, NSColor)] = [
            (t("Prototype", "프로토타입"), 0.60, NSColor(srgbRed: 0.16, green: 0.47, blue: 0.84, alpha: 1)),
            (t("Private beta", "비공개 베타"), 0.35, NSColor(srgbRed: 0.92, green: 0.41, blue: 0.20, alpha: 1)),
            (t("Public launch", "정식 출시"), 0.10, NSColor(srgbRed: 0.11, green: 0.69, blue: 0.48, alpha: 1)),
        ]
        for (index, row) in rows.enumerated() {
            let y = CGFloat(424 - index * 34)
            draw(row.0, size: 12, weight: .regular, color: ink, in: CGRect(x: 56, y: y - 3, width: 120, height: 18))
            NSColor(white: 0.92, alpha: 1).setFill()
            NSBezierPath(roundedRect: CGRect(x: 180, y: y, width: 330, height: 12), xRadius: 6, yRadius: 6).fill()
            row.2.setFill()
            NSBezierPath(roundedRect: CGRect(x: 180, y: y, width: 330 * row.1, height: 12), xRadius: 6, yRadius: 6).fill()
            draw("\(Int(row.1 * 100))", size: 11, weight: .medium, color: soft, in: CGRect(x: 520, y: y - 3, width: 40, height: 18))
        }
        draw(t("Next steps", "다음 단계"), size: 15, weight: .semibold, color: ink, in: CGRect(x: 56, y: 296, width: 500, height: 22))
        draw(t("1.  Tighten the beta checklist\n2.  Confirm dates with the team\n3.  Share the draft a week early",
               "1.  베타 체크리스트 다듬기\n2.  팀과 일정 확정\n3.  초안을 일주일 먼저 공유"),
             size: 12.5, weight: .regular, color: ink, in: CGRect(x: 56, y: 222, width: 500, height: 66))
        NSGraphicsContext.restoreGraphicsState()
        pdf.endPDFPage()
        pdf.closePDF()
        return url
    }

    /// Adds a file, deletes its node, brings it back with Undo, then checks the leftover clean-up.
    private static func fileTest(store: Store) {
        guard let space = store.loggedInSpaces.first, let pdf = makeSamplePDF(korean: false) else { return }
        let directory = store.filesDirectory(for: space.id)
        func stored() -> Int { (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.count ?? 0 }
        let filesBefore = stored(), nodesBefore = space.nodes.count
        do {
            let node = try store.importFile(at: pdf, into: space)
            try? FileManager.default.removeItem(at: pdf)   // the original is gone; the copy must be enough
            let copy = node.file.map { store.fileURL(for: $0, in: space) }
            print("filetest: imported → nodes +\(space.nodes.count - nodesBefore) · files +\(stored() - filesBefore) · title “\(node.title)” · \(node.file?.summary ?? "-") · symbol \(node.symbol)")
            print("filetest: copy readable after the original was deleted =", copy.map { FileManager.default.isReadableFile(atPath: $0.path) } ?? false, "· opens as tab =", space.activeTab == node.id)
            func later(_ seconds: Double, _ work: @escaping () -> Void) {
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
            }
            // Notes are the node's own text: written, undone and saved like a page.
            later(0.8) { node.blocks[0].data.runs = [TextRun(t: "Read before Friday", b: true)] }
            later(1.6) {
                print("filetest: notes written → “\(node.textPreview)” · words \(node.wordCount) · still a file =", node.isFile)
                _ = store.undo(in: space)
                print("filetest: undo notes → “\(node.textPreview)”")
                _ = store.redo(in: space)
                print("filetest: redo notes → “\(node.textPreview)”")
            }
            later(2.4) { space.deleteNode(node.id) }
            later(3.2) {
                print("filetest: node deleted → nodes +\(space.nodes.count - nodesBefore) · file kept for undo =", stored() - filesBefore == 1)
                _ = store.undo(in: space)
                print("filetest: undo → nodes +\(space.nodes.count - nodesBefore) · file node back =", space.node(node.id)?.isFile ?? false,
                      "· notes back = “\(space.node(node.id)?.textPreview ?? "-")”")
                store.flushAll()
                let saved = (try? String(contentsOf: store.dataDir.appendingPathComponent("spaces/\(space.id.uuidString).json"), encoding: .utf8)) ?? ""
                print("filetest: notes saved to disk =", saved.contains("Read before Friday"))
                space.deleteNode(node.id)
            }
            later(4.0) {
                if let owner = store.owner(of: space.id) { store.logOut(owner.id) }   // history ends here, so the leftover copy goes too
                print("filetest: after sign-out leftover files =", stored() - filesBefore, "· other files untouched =", stored() == filesBefore)
            }
        } catch {
            print("filetest: import failed →", error)
        }
        print("filetest: folder rejected =", (try? store.importFile(at: FileManager.default.temporaryDirectory, into: space)) == nil)
    }
}
