import AppKit

@MainActor
final class HistoryPanel: NSPanel {
    var handleKey: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKey?(event) == true { return }
        super.sendEvent(event)
    }
}

@MainActor
final class HistoryWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let panel = HistoryPanel(
        contentRect: NSRect(x: 0, y: 0, width: 540, height: 450),
        styleMask: [.titled, .closable, .fullSizeContentView],
        backing: .buffered, defer: false
    )
    private let settingsButton = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 26))
    private let settingsMenu: NSMenu
    private let search = NSTextField()
    private let tabs = NSSegmentedControl(labels: ["历史", "收藏"], trackingMode: .selectOne,
                                          target: nil, action: nil)
    private let table = NSTableView()
    private let message = NSTextField(labelWithString: "")
    private let footer = NSTextField(labelWithString: "")
    private let favoriteButton = NSButton(title: "收藏选中项", target: nil, action: nil)
    private let history: History

    private var results: [Clip] = []
    private var selectedTab: History.Tab { tabs.selectedSegment == 0 ? .recent : .favorites }
    var onChoose: ((Clip) -> Void)?
    var onCancel: (() -> Void)?
    var isVisible: Bool { panel.isVisible }

    init(history: History, settingsMenu: NSMenu) {
        self.history = history
        self.settingsMenu = settingsMenu
        super.init()

        panel.title = "Paste++"
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.target = self
        panel.standardWindowButton(.closeButton)?.action = #selector(cancel)
        panel.handleKey = { [weak self] in self?.handleKey($0) ?? false }

        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置")
        settingsButton.symbolConfiguration = .init(pointSize: 16, weight: .medium)
        settingsButton.bezelStyle = .accessoryBarAction
        settingsButton.toolTip = "设置"
        settingsButton.setAccessibilityLabel("设置")
        settingsButton.target = self
        settingsButton.action = #selector(showSettings)
        let accessory = NSTitlebarAccessoryViewController()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 48, height: 26))
        settingsButton.autoresizingMask = [.minYMargin, .maxYMargin]
        container.addSubview(settingsButton)
        accessory.view = container
        accessory.layoutAttribute = .right
        panel.addTitlebarAccessoryViewController(accessory)

        search.placeholderString = "搜索剪贴板历史"
        search.setAccessibilityLabel("搜索剪贴板历史")
        search.font = .systemFont(ofSize: 19)
        search.cell?.sendsActionOnEndEditing = false
        search.delegate = self

        tabs.selectedSegment = 0
        tabs.setWidth(78, forSegment: 0)
        tabs.setWidth(78, forSegment: 1)
        tabs.target = self
        tabs.action = #selector(switchTab)
        tabs.setAccessibilityLabel("记录类别")

        favoriteButton.target = self
        favoriteButton.action = #selector(saveFavorite)
        favoriteButton.bezelStyle = .rounded
        favoriteButton.isEnabled = false

        let column = NSTableColumn(identifier: .init("clip"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.rowHeight = 39
        table.style = .plain
        table.usesAlternatingRowBackgroundColors = true
        table.setAccessibilityLabel("剪贴板历史")
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClick)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder

        message.textColor = .secondaryLabelColor
        message.font = .systemFont(ofSize: 14)
        footer.textColor = .secondaryLabelColor
        footer.font = .systemFont(ofSize: 12)
        footer.lineBreakMode = .byTruncatingTail

        guard let content = panel.contentView else { return }
        for view in [search, tabs, scroll, message, footer, favoriteButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 41),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            search.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            search.heightAnchor.constraint(equalToConstant: 34),
            tabs.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            tabs.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: favoriteButton.topAnchor, constant: -9),
            footer.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: favoriteButton.leadingAnchor, constant: -12),
            footer.centerYAnchor.constraint(equalTo: favoriteButton.centerYAnchor),
            favoriteButton.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            favoriteButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            favoriteButton.widthAnchor.constraint(equalToConstant: 106),
            message.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])
    }

    func show() {
        search.stringValue = ""
        refresh(resetSelection: true)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.midY - panel.frame.height / 2
            ))
        }
        focus()
    }

    func focus() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(search)
    }

    func hide() {
        panel.orderOut(nil)
    }

    @objc func showSettings() {
        guard panel.isVisible, NSApp.modalWindow == nil else { return }
        let point = NSPoint(x: settingsButton.bounds.maxX - settingsMenu.size.width,
                            y: settingsButton.bounds.minY)
        settingsMenu.popUp(positioning: nil, at: point, in: settingsButton)
    }

    func refresh(resetSelection: Bool = false) {
        let previous = table.selectedRow
        let selected = results.indices.contains(previous) ? results[previous] : nil
        results = history.search(search.stringValue, in: selectedTab)
        table.reloadData()

        if results.isEmpty {
            if search.stringValue.isEmpty {
                message.stringValue = selectedTab == .recent
                    ? "复制的文本会出现在这里"
                    : "在「历史」中选择一条记录并收藏"
            } else {
                message.stringValue = "没有匹配的记录"
            }
        } else {
            let retained = selected.flatMap { clip in
                results.firstIndex { $0.copiedAt == clip.copiedAt && $0.text == clip.text }
            }
            select(resetSelection ? 0 : retained ?? 0)
        }
        message.isHidden = !results.isEmpty
        var count = "\(results.count) 条收藏"
        if selectedTab == .recent {
            count = "\(history.clips.count)/\(history.limit) 条"
            if history.remainingCapacity == 0 {
                count += "，新记录将替换最旧的记录"
            }
        }
        footer.stringValue = "\(count)   ·   ↑ ↓ 选择   ·   ↩ 粘贴   ·   Esc 取消"
        updateFavoriteButton()
    }

    func controlTextDidChange(_ notification: Notification) {
        refresh(resetSelection: true)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateFavoriteButton()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("clipCell")
        let cell: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        let text = results[row].text
        let prefix = text.prefix(180)
        let preview = prefix.map { character in
            character.isNewline ? "↵ " : character == "\t" ? "⇥ " : String(character)
        }.joined()
        cell.textField?.stringValue = preview.trimmingCharacters(in: .whitespaces).isEmpty
            ? "（空白文本）"
            : preview + (prefix.endIndex == text.endIndex ? "" : "…")
        return cell
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.isEmpty,
              (panel.firstResponder as? NSTextView)?.hasMarkedText() != true else { return false }

        switch event.keyCode {
        case 125, 126:
            if !results.isEmpty {
                let offset = event.keyCode == 125 ? 1 : -1
                select(max(0, min(results.count - 1, table.selectedRow + offset)))
            }
        case 36, 76:
            choose(row: table.selectedRow)
        case 53:
            cancel()
        default:
            return false
        }
        return true
    }

    private func select(_ row: Int) {
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func switchTab() {
        let label = selectedTab == .recent ? "搜索剪贴板历史" : "搜索收藏"
        search.placeholderString = label
        search.setAccessibilityLabel(label)
        table.setAccessibilityLabel(selectedTab == .recent ? "剪贴板历史" : "收藏记录")
        refresh(resetSelection: true)
        panel.makeFirstResponder(search)
    }

    private func updateFavoriteButton() {
        let row = table.selectedRow
        let hasSelection = results.indices.contains(row)
        let alreadySaved = hasSelection && history.isFavorite(results[row])
        favoriteButton.isHidden = selectedTab == .favorites
        favoriteButton.title = alreadySaved ? "已收藏" : "收藏选中项"
        favoriteButton.isEnabled = selectedTab == .recent && hasSelection && !alreadySaved
    }

    @objc private func saveFavorite() {
        let row = table.selectedRow
        guard selectedTab == .recent, results.indices.contains(row) else { return }
        do {
            try history.addFavorite(results[row])
            updateFavoriteButton()
        } catch {
            footer.stringValue = "收藏保存失败，请重试。"
        }
    }

    @objc private func doubleClick() {
        choose(row: table.clickedRow)
    }

    private func choose(row: Int) {
        if results.indices.contains(row) { onChoose?(results[row]) }
    }

    @objc private func cancel() {
        onCancel?()
    }
}
