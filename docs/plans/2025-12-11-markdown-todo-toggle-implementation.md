# Markdown Todo Toggle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add interactive todo list toggling in Markdown editor via mouse click and keyboard shortcut.

**Architecture:** Extend MarkdownEditor.Coordinator with NSTrackingArea for mouse detection, override mouseDown for clicks, and extend doCommandBy for Cmd+Enter shortcut. Regex-based checkbox detection, direct text replacement, preserving cursor position.

**Tech Stack:** Swift, AppKit (NSTextView, NSTrackingArea), SwiftUI (NSViewRepresentable)

---

## Task 1: Add Helper Method - Find Checkbox Range

**Files:**
- Modify: `open-sidenotes/Views/Components/MarkdownEditor.swift:106-398` (Coordinator class)

**Step 1: Add findTaskCheckboxRange method**

Add this method inside the `Coordinator` class, after the `findCodeBlockRange` method (around line 398):

```swift
private func findTaskCheckboxRange(in textView: NSTextView, at position: Int) -> NSRange? {
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
```

**Step 2: Manual test verification**

Run app in Xcode:
- Open a note
- Type: `- [ ] Test task`
- Expected: No change yet (helper added but not used)

**Step 3: Commit**

```bash
git add open-sidenotes/Views/Components/MarkdownEditor.swift
git commit -m "feat: add findTaskCheckboxRange helper method"
```

---

## Task 2: Add Helper Method - Check Position in Checkbox

**Files:**
- Modify: `open-sidenotes/Views/Components/MarkdownEditor.swift:106-398` (Coordinator class)

**Step 1: Add isPositionInCheckbox method**

Add this method right after `findTaskCheckboxRange`:

```swift
private func isPositionInCheckbox(_ position: Int, checkboxRange: NSRange) -> Bool {
    let tolerance = 2
    return position >= checkboxRange.location - tolerance &&
           position <= checkboxRange.location + checkboxRange.length + tolerance
}
```

**Step 2: Manual test verification**

Build app:
- Expected: Compiles successfully

**Step 3: Commit**

```bash
git add open-sidenotes/Views/Components/MarkdownEditor.swift
git commit -m "feat: add isPositionInCheckbox helper method"
```

---

## Task 3: Add Core Method - Toggle Task Status

**Files:**
- Modify: `open-sidenotes/Views/Components/MarkdownEditor.swift:106-398` (Coordinator class)

**Step 1: Add toggleTaskStatus method**

Add this method after `isPositionInCheckbox`:

```swift
private func toggleTaskStatus(in textView: NSTextView, at position: Int) {
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
```

**Step 2: Manual test verification**

Build app:
- Expected: Compiles successfully

**Step 3: Commit**

```bash
git add open-sidenotes/Views/Components/MarkdownEditor.swift
git commit -m "feat: add toggleTaskStatus core method"
```

---

## Task 4: Add Mouse Click Handler

**Files:**
- Modify: `open-sidenotes/Views/Components/MarkdownEditor.swift:106-398` (Coordinator class)

**Step 1: Add mouseDown override**

Add this method in the `Coordinator` class, before the `textView(_:menu:for:at:)` method (around line 350):

```swift
func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
    return true
}

override func mouseDown(with event: NSEvent) {
    guard let textView = event.window?.firstResponder as? NSTextView else {
        super.mouseDown(with: event)
        return
    }

    let point = textView.convert(event.locationInWindow, from: nil)
    let charIndex = textView.characterIndexForInsertion(at: point)

    if let checkboxRange = findTaskCheckboxRange(in: textView, at: charIndex),
       isPositionInCheckbox(charIndex, checkboxRange: checkboxRange) {
        toggleTaskStatus(in: textView, at: charIndex)
        return
    }

    super.mouseDown(with: event)
}
```

**Step 2: Manual test - Click toggle**

Run app in Xcode:
1. Create a note with: `- [ ] Click test`
2. Click on the `[ ]` area
3. Expected: Status toggles to `[x]`, text shows strikethrough
4. Click again
5. Expected: Status toggles back to `[ ]`, strikethrough removed

**Step 3: Commit**

```bash
git add open-sidenotes/Views/Components/MarkdownEditor.swift
git commit -m "feat: add mouse click toggle for todo checkboxes"
```

---

## Task 5: Add Mouse Tracking for Cursor Change

**Files:**
- Modify: `open-sidenotes/Views/Components/MarkdownEditor.swift:106-398` (Coordinator class)

**Step 1: Add tracking area property**

Add this property to the `Coordinator` class after `lastSelectedLanguage` (around line 116):

```swift
var trackingArea: NSTrackingArea?
```

**Step 2: Add setupTrackingArea method**

Add this method in the `Coordinator` class:

```swift
private func setupTrackingArea(for textView: NSTextView) {
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
        owner: self,
        userInfo: nil
    )

    textView.addTrackingArea(area)
    trackingArea = area
}
```

**Step 3: Add mouseMoved override**

Add this method in the `Coordinator` class:

```swift
override func mouseMoved(with event: NSEvent) {
    guard let textView = event.window?.firstResponder as? NSTextView else {
        NSCursor.iBeam.set()
        return
    }

    let point = textView.convert(event.locationInWindow, from: nil)
    let charIndex = textView.characterIndexForInsertion(at: point)

    if let checkboxRange = findTaskCheckboxRange(in: textView, at: charIndex),
       isPositionInCheckbox(charIndex, checkboxRange: checkboxRange) {
        NSCursor.pointingHand.set()
    } else {
        NSCursor.iBeam.set()
    }
}
```

**Step 4: Call setupTrackingArea from makeNSView**

Modify the `makeNSView` function in `MarkdownEditor` (around line 32-68) to add tracking setup. Add this line after `context.coordinator.renderMarkdown(in: textView, text: text)` (line 66):

```swift
context.coordinator.setupTrackingArea(for: textView)
```

**Step 5: Manual test - Cursor change**

Run app in Xcode:
1. Create a note with: `- [ ] Hover test`
2. Move mouse over the `[ ]` area
3. Expected: Cursor changes to pointing hand
4. Move mouse away from checkbox
5. Expected: Cursor returns to iBeam (text cursor)

**Step 6: Commit**

```bash
git add open-sidenotes/Views/Components/MarkdownEditor.swift
git commit -m "feat: add mouse tracking for cursor change on checkbox hover"
```

---

## Task 6: Add Keyboard Shortcut (Cmd+Enter)

**Files:**
- Modify: `open-sidenotes/Views/Components/MarkdownEditor.swift:122-151` (doCommandBy method)

**Step 1: Extend doCommandBy to handle Cmd+Enter**

Replace the existing `doCommandBy` method (lines 122-151) with this version that adds Cmd+Enter detection:

```swift
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

    // Handle Cmd+Enter for todo toggle
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
```

**Step 2: Manual test - Keyboard shortcut**

Run app in Xcode:
1. Create a note with: `- [ ] Keyboard test`
2. Place cursor anywhere on the line
3. Press Cmd+Enter
4. Expected: Status toggles to `[x]`
5. Press Cmd+Enter again
6. Expected: Status toggles back to `[ ]`
7. Try on a non-todo line and press Cmd+Enter
8. Expected: Nothing happens (newline inserted normally)

**Step 3: Commit**

```bash
git add open-sidenotes/Views/Components/MarkdownEditor.swift
git commit -m "feat: add Cmd+Enter keyboard shortcut for todo toggle"
```

---

## Task 7: Handle Edge Cases

**Files:**
- Modify: `open-sidenotes/Views/Components/MarkdownEditor.swift` (Coordinator class)

**Step 1: Improve toggleTaskStatus to prevent toggle during text selection**

Replace the `toggleTaskStatus` method with this improved version:

```swift
private func toggleTaskStatus(in textView: NSTextView, at position: Int) {
    // Prevent toggle if user is actively selecting text
    let selection = textView.selectedRange()
    if selection.length > 0 {
        return
    }

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

    // Normalize to lowercase 'x'
    let newChar = (checkboxChar.trimmingCharacters(in: .whitespaces).isEmpty) ? "x" : " "

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
```

**Step 2: Manual test - Edge cases**

Run app in Xcode:

Test 1 - Nested todos:
```
- [ ] Parent
  - [ ] Child
    - [ ] Grandchild
```
- Click each checkbox independently
- Expected: Each toggles independently

Test 2 - Mixed formatting:
```
- [ ] Task with **bold** and `code`
```
- Click checkbox
- Expected: Toggles correctly, formatting preserved

Test 3 - Case variants:
```
- [X] Uppercase
- [x] Lowercase
```
- Click each
- Expected: Both toggle to `[ ]`, then to `[x]` (lowercase)

Test 4 - Text selection:
```
- [ ] Select this text
```
- Select some text in the task
- Try to click checkbox while selection active
- Expected: No toggle (selection preserved)

Test 5 - Incomplete syntax:
```
- [] Missing space
- [ Missing bracket
```
- Hover over these
- Expected: No cursor change (not recognized as todos)

**Step 3: Commit**

```bash
git add open-sidenotes/Views/Components/MarkdownEditor.swift
git commit -m "feat: handle edge cases for todo toggle"
```

---

## Task 8: Final Integration Test

**Files:**
- None (testing only)

**Step 1: Comprehensive manual test**

Run app in Xcode and test:

1. **Basic toggle**: Click and keyboard work
2. **Auto-save**: Changes persist after 1 second
3. **Rendering**: Visual updates (strikethrough) apply immediately
4. **Cursor preservation**: Cursor stays in same position after toggle
5. **Mixed with other features**: Slash commands still work
6. **Undo/redo**: System undo correctly reverses toggles

**Step 2: Document test results**

Create test report in commit message.

**Step 3: Final commit**

```bash
git add .
git commit -m "test: verify todo toggle integration

All features working:
- Click toggle on checkbox
- Hover cursor change
- Cmd+Enter keyboard shortcut
- Edge cases handled correctly
- Auto-save triggered
- Undo/redo functional
"
```

---

## Task 9: Update Documentation

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update Task Lists section in CLAUDE.md**

Find the "Task Lists" section and update it:

```markdown
- **Task Lists**: Interactive visual rendering
  - Syntax: `- [ ]` for uncompleted, `- [x]` for completed tasks
  - Supports nested tasks with indentation (2 or 4 spaces)
  - Completed tasks show strikethrough and gray color
  - Checkbox markers `[ ]` and `[x]` shown in dimmed gray
  - **Click checkbox to toggle status** (new)
  - **Hover shows pointing hand cursor** (new)
  - **Cmd+Enter keyboard shortcut to toggle** (new)
```

**Step 2: Commit documentation**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with todo toggle feature"
```

---

## Verification Checklist

After completing all tasks, verify:

- [ ] Click on `[ ]` toggles to `[x]`
- [ ] Click on `[x]` toggles to `[ ]`
- [ ] Hover over checkbox shows pointing hand cursor
- [ ] Hover outside checkbox shows iBeam cursor
- [ ] Cmd+Enter on todo line toggles status
- [ ] Cmd+Enter on non-todo line inserts newline
- [ ] Cursor position preserved after toggle
- [ ] Auto-save triggers after toggle
- [ ] Visual rendering updates immediately
- [ ] Text selection prevents toggle
- [ ] Nested todos work independently
- [ ] Mixed formatting preserved
- [ ] Incomplete syntax ignored
- [ ] System undo/redo works

---

## Notes

- No external dependencies required
- All changes in single file: `MarkdownEditor.swift`
- Uses existing `MarkdownRenderer` for visual updates
- Leverages existing auto-save mechanism
- Minimal UI changes (cursor change only)
