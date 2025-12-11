import SwiftUI
import AppKit

class ClickableTextView: NSTextView {
    weak var clickDelegate: MarkdownEditor.Coordinator?

    override func mouseDown(with event: NSEvent) {
        let point = self.convert(event.locationInWindow, from: nil)
        let charIndex = self.characterIndexForInsertion(at: point)

        if let delegate = clickDelegate,
           let checkboxRange = delegate.findTaskCheckboxRange(in: self, at: charIndex),
           delegate.isPositionInCheckbox(charIndex, checkboxRange: checkboxRange) {
            delegate.toggleTaskStatus(in: self, at: charIndex)
            return
        }

        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = self.convert(event.locationInWindow, from: nil)
        let charIndex = self.characterIndexForInsertion(at: point)

        if let delegate = clickDelegate,
           let checkboxRange = delegate.findTaskCheckboxRange(in: self, at: charIndex),
           delegate.isPositionInCheckbox(charIndex, checkboxRange: checkboxRange) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }

        super.mouseMoved(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        clickDelegate?.setupTrackingArea(for: self)
    }
}

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var searchQuery: String = ""
    var currentMatchIndex: Int = 0
    @Binding var showSlashMenu: Bool
    @Binding var slashMenuPosition: CGPoint
    @Binding var slashMenuQuery: String
    @Binding var slashMenuSelectedIndex: Int
    @Binding var selectedLanguage: CodeLanguage?

    init(text: Binding<String>,
         searchQuery: String = "",
         currentMatchIndex: Int = 0,
         showSlashMenu: Binding<Bool> = .constant(false),
         slashMenuPosition: Binding<CGPoint> = .constant(.zero),
         slashMenuQuery: Binding<String> = .constant(""),
         slashMenuSelectedIndex: Binding<Int> = .constant(0),
         selectedLanguage: Binding<CodeLanguage?> = .constant(nil)) {
        self._text = text
        self.searchQuery = searchQuery
        self.currentMatchIndex = currentMatchIndex
        self._showSlashMenu = showSlashMenu
        self._slashMenuPosition = slashMenuPosition
        self._slashMenuQuery = slashMenuQuery
        self._slashMenuSelectedIndex = slashMenuSelectedIndex
        self._selectedLanguage = selectedLanguage
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer()
        layoutManager.addTextContainer(textContainer)

        let textView = ClickableTextView(frame: .zero, textContainer: textContainer)
        textView.clickDelegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.documentView = textView

        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 15, weight: .regular)
        textView.textColor = NSColor(red: 0.17, green: 0.17, blue: 0.17, alpha: 1.0)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.delegate = context.coordinator

        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = 0
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: NSColor(red: 0.17, green: 0.17, blue: 0.17, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]

        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller = CustomScroller()

        context.coordinator.renderMarkdown(in: textView, text: text)
        context.coordinator.setupTrackingArea(for: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.parent = self

        if textView.delegate == nil {
            textView.delegate = context.coordinator
        }

        let queryChanged = context.coordinator.lastSearchQuery != searchQuery
        let indexChanged = context.coordinator.lastMatchIndex != currentMatchIndex

        if textView.string != text && !context.coordinator.isUpdating {
            context.coordinator.renderMarkdown(in: textView, text: text)
        }

        if queryChanged || indexChanged {
            context.coordinator.lastSearchQuery = searchQuery
            context.coordinator.lastMatchIndex = currentMatchIndex
            context.coordinator.applySearchHighlight(in: textView, query: searchQuery, currentIndex: currentMatchIndex)
        }

        if let language = selectedLanguage, context.coordinator.lastSelectedLanguage != language {
            context.coordinator.lastSelectedLanguage = language
            context.coordinator.insertCodeBlock(in: textView, language: language)
            DispatchQueue.main.async {
                self.selectedLanguage = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var isUpdating = false
        var renderTask: DispatchWorkItem?
        var lastText: String = ""
        var shouldRenderImmediately = false
        var lastSearchQuery: String = ""
        var lastMatchIndex: Int = 0
        var currentEditingLineRange: NSRange?
        var slashCommandRange: NSRange?
        var lastSelectedLanguage: CodeLanguage?
        var trackingArea: NSTrackingArea?

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if parent.showSlashMenu {
                switch commandSelector {
                case #selector(NSResponder.moveDown(_:)):
                    let filteredCommands = SlashCommand.filter(by: parent.slashMenuQuery)
                    if !filteredCommands.isEmpty {
                        parent.slashMenuSelectedIndex = (parent.slashMenuSelectedIndex + 1) % filteredCommands.count
                    }
                    return true
                case #selector(NSResponder.moveUp(_:)):
                    let filteredCommands = SlashCommand.filter(by: parent.slashMenuQuery)
                    if !filteredCommands.isEmpty {
                        parent.slashMenuSelectedIndex = (parent.slashMenuSelectedIndex - 1 + filteredCommands.count) % filteredCommands.count
                    }
                    return true
                case #selector(NSResponder.insertNewline(_:)):
                    let filteredCommands = SlashCommand.filter(by: parent.slashMenuQuery)
                    if parent.slashMenuSelectedIndex < filteredCommands.count {
                        insertSlashCommand(in: textView, command: filteredCommands[parent.slashMenuSelectedIndex])
                    }
                    return true
                case #selector(NSResponder.cancelOperation(_:)):
                    closeSlashMenu()
                    return true
                default:
                    break
                }
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let event = NSApp.currentEvent
                if event?.modifierFlags.contains(.command) == true {
                    let cursorPosition = textView.selectedRange().location
                    if findTaskCheckboxRange(in: textView, at: cursorPosition) != nil {
                        toggleTaskStatus(in: textView, at: cursorPosition)
                        return true
                    }
                }
            }

            return false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            let markedRange = textView.markedRange()
            let isInMarkedTextMode = markedRange.location != NSNotFound && markedRange.length > 0

            if isInMarkedTextMode {
                return
            }

            let plainText = textView.string
            let cursorPosition = textView.selectedRange().location

            isUpdating = true
            parent.text = plainText
            isUpdating = false

            checkSlashCommand(in: textView, at: cursorPosition)

            currentEditingLineRange = getCurrentLineRange(in: textView, at: cursorPosition)
            lastText = plainText
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            currentEditingLineRange = nil
            renderTask?.cancel()
            renderMarkdown(in: textView, text: textView.string)
        }

        private func getCurrentLineRange(in textView: NSTextView, at position: Int) -> NSRange {
            let text = textView.string as NSString
            return text.lineRange(for: NSRange(location: position, length: 0))
        }

        func renderMarkdown(in textView: NSTextView, text: String, cursorPosition: Int? = nil) {
            guard let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let scrollView = textView.enclosingScrollView else { return }

            let savedScrollPosition = scrollView.contentView.bounds.origin
            let savedSelection = textView.selectedRange()

            layoutManager.allowsNonContiguousLayout = false

            textStorage.beginEditing()

            let attributedString = MarkdownRenderer.shared.render(text)
            textStorage.setAttributedString(attributedString)

            textStorage.endEditing()

            if let position = cursorPosition {
                let safePosition = min(position, textView.string.count)
                textView.setSelectedRange(NSRange(location: safePosition, length: 0))
            } else {
                textView.setSelectedRange(savedSelection)
            }

            layoutManager.ensureLayout(for: textView.textContainer!)
            scrollView.contentView.scrollToVisible(scrollView.contentView.bounds)
            scrollView.contentView.setBoundsOrigin(savedScrollPosition)

            applySearchHighlight(in: textView, query: lastSearchQuery, currentIndex: lastMatchIndex)
        }

        func applySearchHighlight(in textView: NSTextView, query: String, currentIndex: Int) {
            guard let textStorage = textView.textStorage else { return }

            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.removeAttribute(.backgroundColor, range: fullRange)

            guard !query.isEmpty else { return }

            let text = textView.string
            let lowerText = text.lowercased()
            let lowerQuery = query.lowercased()

            var matchIndex = 0
            var searchStart = lowerText.startIndex

            while let range = lowerText.range(of: lowerQuery, range: searchStart..<lowerText.endIndex) {
                let nsRange = NSRange(range, in: text)

                let bgColor: NSColor
                if matchIndex == currentIndex {
                    bgColor = NSColor(red: 0.486, green: 0.596, blue: 0.522, alpha: 0.4)
                } else {
                    bgColor = NSColor(red: 0.486, green: 0.596, blue: 0.522, alpha: 0.15)
                }

                textStorage.addAttribute(.backgroundColor, value: bgColor, range: nsRange)

                if matchIndex == currentIndex {
                    textView.scrollRangeToVisible(nsRange)
                }

                matchIndex += 1
                searchStart = range.upperBound
            }
        }

        func checkSlashCommand(in textView: NSTextView, at position: Int) {
            let text = textView.string as NSString
            let lineRange = text.lineRange(for: NSRange(location: position, length: 0))
            let lineText = text.substring(with: lineRange).trimmingCharacters(in: .newlines)

            let slashPattern = "^\\s*/[a-z0-9]*$"
            if let regex = try? NSRegularExpression(pattern: slashPattern, options: []),
               regex.firstMatch(in: lineText, range: NSRange(location: 0, length: lineText.count)) != nil {

                if let slashRange = lineText.range(of: "/") {
                    let slashIndex = lineText.distance(from: lineText.startIndex, to: slashRange.lowerBound)
                    let absoluteSlashPos = lineRange.location + slashIndex
                    slashCommandRange = NSRange(location: absoluteSlashPos, length: position - absoluteSlashPos)

                    let query = String(lineText[slashRange.lowerBound...].prefix(position - absoluteSlashPos))
                    parent.slashMenuQuery = query

                    let filteredCommands = SlashCommand.filter(by: query)
                    if filteredCommands.isEmpty {
                        closeSlashMenu()
                        return
                    }
                    parent.slashMenuSelectedIndex = min(parent.slashMenuSelectedIndex, max(0, filteredCommands.count - 1))

                    if let layoutManager = textView.layoutManager,
                       let textContainer = textView.textContainer {
                        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: position, length: 0), actualCharacterRange: nil)
                        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                        if let window = textView.window {
                            let textViewPoint = CGPoint(x: rect.minX, y: rect.maxY + 4)
                            let windowPoint = textView.convert(textViewPoint, to: nil)
                            let screenPoint = window.convertPoint(toScreen: windowPoint)
                            parent.slashMenuPosition = screenPoint
                        }
                    }

                    parent.showSlashMenu = true
                } else {
                    closeSlashMenu()
                }
            } else {
                closeSlashMenu()
            }
        }

        func insertSlashCommand(in textView: NSTextView, command: SlashCommand) {
            guard let range = slashCommandRange else { return }

            if command.needsLanguageSelector {
                closeSlashMenu()
                return
            }

            let cursorOffset = command.template.contains("text") || command.template.contains("url") ?
                command.template.distance(from: command.template.startIndex,
                                         to: command.template.range(of: "text")?.lowerBound ?? command.template.endIndex) :
                command.template.count

            if textView.shouldChangeText(in: range, replacementString: command.template) {
                textView.textStorage?.replaceCharacters(in: range, with: command.template)
                textView.didChangeText()

                let newPosition = range.location + cursorOffset
                textView.setSelectedRange(NSRange(location: newPosition, length: 0))
            }

            closeSlashMenu()
        }

        func insertCodeBlock(in textView: NSTextView, language: CodeLanguage) {
            guard let range = slashCommandRange else { return }

            let languageId = language.highlightIdentifier
            let template = languageId.isEmpty ? "```\n\n```" : "```\(languageId)\n\n```"
            let cursorOffset = languageId.isEmpty ? 4 : languageId.count + 5

            if textView.shouldChangeText(in: range, replacementString: template) {
                textView.textStorage?.replaceCharacters(in: range, with: template)
                textView.didChangeText()

                let newPosition = range.location + cursorOffset
                textView.setSelectedRange(NSRange(location: newPosition, length: 0))
            }

            slashCommandRange = nil
        }

        func closeSlashMenu() {
            parent.showSlashMenu = false
            parent.slashMenuQuery = ""
            parent.slashMenuSelectedIndex = 0
            slashCommandRange = nil
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            return true
        }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            if let codeBlockRange = findCodeBlockRange(in: view, at: charIndex) {
                let copyItem = NSMenuItem(
                    title: "复制代码",
                    action: #selector(copyCodeBlock(_:)),
                    keyEquivalent: ""
                )
                copyItem.target = self
                copyItem.representedObject = codeBlockRange
                menu.insertItem(copyItem, at: 0)
                menu.insertItem(NSMenuItem.separator(), at: 1)
            }
            return menu
        }

        @objc func copyCodeBlock(_ sender: NSMenuItem) {
            guard let range = sender.representedObject as? NSRange,
                  let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }

            let text = (textView.string as NSString).substring(with: range)
            let pattern = "```[a-z0-9]*\\n([\\s\\S]*?)\\n```"

            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: text.count)) {
                let codeRange = match.range(at: 1)
                let code = (text as NSString).substring(with: codeRange)

                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(code, forType: .string)
            }
        }

        private func findCodeBlockRange(in textView: NSTextView, at charIndex: Int) -> NSRange? {
            let text = textView.string as NSString
            let pattern = "```[a-z0-9]*\\n[\\s\\S]*?\\n```"

            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            let matches = regex.matches(in: textView.string, range: NSRange(location: 0, length: text.length))

            for match in matches {
                let range = match.range
                if charIndex >= range.location && charIndex <= range.location + range.length {
                    return range
                }
            }
            return nil
        }

        func findTaskCheckboxRange(in textView: NSTextView, at position: Int) -> NSRange? {
            let text = textView.string as NSString
            let lineRange = text.lineRange(for: NSRange(location: position, length: 0))
            let lineText = text.substring(with: lineRange)

            let pattern = "^(\\s*)([-*+])\\s+(\\[([ xX])\\])\\s+(.+)$"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }

            guard let match = regex.firstMatch(in: lineText, range: NSRange(location: 0, length: lineText.count)) else {
                return nil
            }

            let checkboxLocalRange = match.range(at: 3)
            let checkboxAbsoluteRange = NSRange(
                location: lineRange.location + checkboxLocalRange.location,
                length: checkboxLocalRange.length
            )

            return checkboxAbsoluteRange
        }

        func isPositionInCheckbox(_ position: Int, checkboxRange: NSRange) -> Bool {
            let tolerance = 2
            return position >= checkboxRange.location - tolerance &&
                   position <= checkboxRange.location + checkboxRange.length + tolerance
        }

        func toggleTaskStatus(in textView: NSTextView, at position: Int) {
            guard let checkboxRange = findTaskCheckboxRange(in: textView, at: position) else { return }

            let text = textView.string as NSString
            let checkboxText = text.substring(with: checkboxRange)

            let pattern = "\\[([ xX])\\]"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(in: checkboxText, range: NSRange(location: 0, length: checkboxText.count)) else {
                return
            }

            let checkboxCharRange = match.range(at: 1)
            let checkboxChar = (checkboxText as NSString).substring(with: checkboxCharRange)
            let newChar = (checkboxChar == " ") ? "x" : " "

            let absoluteCharRange = NSRange(
                location: checkboxRange.location + checkboxCharRange.location,
                length: checkboxCharRange.length
            )

            let savedSelection = textView.selectedRange()

            if textView.shouldChangeText(in: absoluteCharRange, replacementString: newChar) {
                textView.textStorage?.replaceCharacters(in: absoluteCharRange, with: newChar)
                textView.didChangeText()
                textView.setSelectedRange(savedSelection)
            }
        }

        func setupTrackingArea(for textView: NSTextView) {
            if let existingArea = trackingArea {
                textView.removeTrackingArea(existingArea)
            }

            let options: NSTrackingArea.Options = [
                .mouseMoved,
                .activeInActiveApp,
                .inVisibleRect
            ]

            let area = NSTrackingArea(
                rect: textView.bounds,
                options: options,
                owner: textView,
                userInfo: nil
            )

            textView.addTrackingArea(area)
            trackingArea = area
        }
    }
}

#Preview {
    @Previewable @State var text = """
# Heading 1
## Heading 2
### Heading 3

This is **bold** text and this is *italic* text.

Some `inline code` here.

## Task Lists
- [ ] Uncompleted task
- [x] Completed task
- [ ] Another uncompleted task

- List item 1
- List item 2

1. Numbered item
2. Another item

**Bold with `code` inside**
"""

    return MarkdownEditor(text: $text)
        .frame(width: 600, height: 400)
        .padding()
}
