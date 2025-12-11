import SwiftUI
import AppKit

class SelfSizingTextView: NSView {
    let scrollView: NSScrollView
    let textView: NSTextView

    override init(frame frameRect: NSRect) {
        scrollView = NSTextView.scrollableTextView()
        textView = scrollView.documentView as! NSTextView
        super.init(frame: frameRect)

        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? .zero
        let contentHeight = usedRect.size.height + usedRect.origin.y
        let height = max(contentHeight + 20, 40)

        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }
}

struct TextBlockEditor: NSViewRepresentable {
    @Binding var text: String
    let onTextChange: (String) -> Void
    let onDeletePreviousBlock: (() -> Bool)?
    @Binding var showSlashMenu: Bool
    @Binding var slashMenuPosition: CGPoint
    @Binding var slashMenuQuery: String
    @Binding var slashMenuSelectedIndex: Int
    @Binding var selectedLanguage: CodeLanguage?
    @Binding var showLanguageSelector: Bool

    func makeNSView(context: Context) -> SelfSizingTextView {
        print("🆕 [TextBlockEditor] makeNSView called")
        let containerView = SelfSizingTextView(frame: .zero)
        let textView = containerView.textView

        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 15, weight: .regular)
        textView.textColor = NSColor(red: 0.17, green: 0.17, blue: 0.17, alpha: 1.0)
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.delegate = context.coordinator
        print("🆕 [TextBlockEditor] TextView created and configured")

        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = 0
            textContainer.widthTracksTextView = true
            textContainer.heightTracksTextView = false
            textContainer.containerSize = NSSize(width: containerView.scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: NSColor(red: 0.17, green: 0.17, blue: 0.17, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]

        containerView.scrollView.borderType = .noBorder
        containerView.scrollView.hasVerticalScroller = false
        containerView.scrollView.hasHorizontalScroller = false
        containerView.scrollView.backgroundColor = .clear
        containerView.scrollView.drawsBackground = false

        context.coordinator.containerView = containerView
        context.coordinator.renderMarkdown(in: textView, text: text)

        print("🆕 [TextBlockEditor] Initial text length: \(text.count)")
        print("🆕 [TextBlockEditor] Initial text preview: '\(String(text.prefix(100)))'")

        return containerView
    }

    func updateNSView(_ containerView: SelfSizingTextView, context: Context) {
        let textView = containerView.textView

        context.coordinator.parent = self

        if textView.delegate == nil {
            textView.delegate = context.coordinator
        }

        if textView.string != text && !context.coordinator.isUpdating {
            print("🔄 [TextBlockEditor] updateNSView: text changed")
            print("🔄 [TextBlockEditor] Old text length: \(textView.string.count)")
            print("🔄 [TextBlockEditor] New text length: \(text.count)")
            print("🔄 [TextBlockEditor] New text preview: '\(String(text.prefix(100)))'")
            context.coordinator.renderMarkdown(in: textView, text: text)
        }

        if let language = selectedLanguage, context.coordinator.lastSelectedLanguage != language {
            print("🟣 [TextBlockEditor] updateNSView: selectedLanguage changed to \(language.displayName)")
            context.coordinator.lastSelectedLanguage = language
            context.coordinator.insertCodeBlock(in: textView, language: language)
            DispatchQueue.main.async {
                print("🟣 [TextBlockEditor] Clearing selectedLanguage")
                self.selectedLanguage = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextBlockEditor
        var isUpdating = false
        var slashCommandRange: NSRange?
        var lastSelectedLanguage: CodeLanguage?
        weak var containerView: SelfSizingTextView?

        init(_ parent: TextBlockEditor) {
            self.parent = parent
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                let cursorPosition = textView.selectedRange().location
                if cursorPosition == 0 && textView.string.isEmpty {
                    print("🗑️ [TextBlockEditor] Delete at beginning of empty block")
                    if let callback = parent.onDeletePreviousBlock, callback() {
                        print("✅ [TextBlockEditor] Previous block deleted")
                        return true
                    }
                }
            }

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
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            let plainText = textView.string
            let cursorPosition = textView.selectedRange().location

            isUpdating = true
            parent.onTextChange(plainText)
            isUpdating = false

            checkSlashCommand(in: textView, at: cursorPosition)

            DispatchQueue.main.async {
                self.containerView?.invalidateIntrinsicContentSize()
            }
        }

        func renderMarkdown(in textView: NSTextView, text: String) {
            let attributedString = MarkdownRenderer.shared.render(text)
            textView.textStorage?.setAttributedString(attributedString)

            DispatchQueue.main.async {
                self.containerView?.invalidateIntrinsicContentSize()
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
            print("🔵 [TextBlockEditor] insertSlashCommand called, command: \(command.trigger)")

            guard let range = slashCommandRange else {
                print("❌ [TextBlockEditor] slashCommandRange is nil!")
                return
            }

            print("✅ [TextBlockEditor] slashCommandRange exists: \(range)")

            if command.needsLanguageSelector {
                print("🟡 [TextBlockEditor] Command needs language selector")
                parent.showSlashMenu = false
                parent.slashMenuQuery = ""
                parent.slashMenuSelectedIndex = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.parent.showLanguageSelector = true
                }
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
            print("🟢 [TextBlockEditor] insertCodeBlock called, language: \(language.displayName)")

            guard let range = slashCommandRange else {
                print("❌ [TextBlockEditor] insertCodeBlock: slashCommandRange is nil!")
                return
            }

            print("✅ [TextBlockEditor] insertCodeBlock: slashCommandRange exists: \(range)")

            let languageId = language.highlightIdentifier
            let template = languageId.isEmpty ? "```\n\n```" : "```\(languageId)\n\n```"

            print("📝 [TextBlockEditor] Template to insert: '\(template)'")
            print("📍 [TextBlockEditor] Insert position: \(range.location), length: \(range.length)")

            if textView.shouldChangeText(in: range, replacementString: template) {
                print("✅ [TextBlockEditor] shouldChangeText returned true")
                textView.textStorage?.replaceCharacters(in: range, with: template)
                textView.didChangeText()
                print("✅ [TextBlockEditor] Text replaced and didChangeText called")
                print("📄 [TextBlockEditor] New text content: '\(textView.string)'")
            } else {
                print("❌ [TextBlockEditor] shouldChangeText returned false!")
            }

            slashCommandRange = nil
        }

        func closeSlashMenu() {
            parent.showSlashMenu = false
            parent.slashMenuQuery = ""
            parent.slashMenuSelectedIndex = 0
            slashCommandRange = nil
        }
    }
}
