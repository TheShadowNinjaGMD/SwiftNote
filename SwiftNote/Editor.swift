//
//  Editor.swift
//  SwiftNote — the text editor (NSTextView), formatting actions, Markdown preview,
//  dictation controls.
//

import SwiftUI
import AppKit

// MARK: - Formatting controller (talks to the NSTextView)
@MainActor
final class EditorController: ObservableObject {
    weak var textView: NSTextView?

    func focus() {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
    }

    /// Wraps the selection (or the word at the caret) in Markdown markers; unwraps when already wrapped.
    func wrap(_ open: String, _ close: String? = nil) {
        guard let tv = textView else { return }
        let close = close ?? open
        let ns = tv.string as NSString
        var range = tv.selectedRange()
        guard range.location != NSNotFound else { return }

        if range.length == 0 {
            let word = tv.selectionRange(forProposedRange: range, granularity: .selectByWord)
            if word.length > 0 { range = word }
        }

        let replacement: String
        var caretInside = false
        if range.length == 0 {
            replacement = open + close
            caretInside = true
        } else {
            let selected = ns.substring(with: range)
            if selected.hasPrefix(open), selected.hasSuffix(close), selected.count >= open.count + close.count {
                replacement = String(selected.dropFirst(open.count).dropLast(close.count))
            } else {
                replacement = open + selected + close
            }
        }

        guard tv.shouldChangeText(in: range, replacementString: replacement) else { return }
        tv.replaceCharacters(in: range, with: replacement)
        tv.didChangeText()
        if caretInside {
            tv.setSelectedRange(NSRange(location: range.location + (open as NSString).length, length: 0))
        } else {
            tv.setSelectedRange(NSRange(location: range.location, length: (replacement as NSString).length))
        }
        focus()
    }

    /// Adds (or removes) a prefix such as "- " or "# " on every selected line.
    func prefixLines(_ prefix: String) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let lineRange = ns.lineRange(for: tv.selectedRange())
        let block = ns.substring(with: lineRange)
        var lines = block.components(separatedBy: "\n")
        let hadTrailingNewline = block.hasSuffix("\n")
        if hadTrailingNewline { lines.removeLast() }

        let allPrefixed = !lines.isEmpty && lines.allSatisfy { $0.hasPrefix(prefix) }
        let converted = lines.map { allPrefixed ? String($0.dropFirst(prefix.count)) : prefix + $0 }
        let replacement = converted.joined(separator: "\n") + (hadTrailingNewline ? "\n" : "")

        guard tv.shouldChangeText(in: lineRange, replacementString: replacement) else { return }
        tv.replaceCharacters(in: lineRange, with: replacement)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: lineRange.location, length: (replacement as NSString).length - (hadTrailingNewline ? 1 : 0)))
        focus()
    }
}


// MARK: - Live Markdown styling (markers stay visible but dimmed; content is actually bold / italic / underlined…)
@MainActor
enum MarkdownStyler {
    private static func rx(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Patterns are constants, so a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let heading = rx("^(#{1,6})[ \\t]+(.*)$", [.anchorsMatchLines])
    private static let boldItalic = rx("\\*\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*\\*")
    private static let bold = rx("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italicStar = rx("(?<![\\*\\w])\\*(?=[^\\s\\*])([^\\*\\n]+?)(?<=[^\\s\\*])\\*(?![\\*\\w])")
    private static let italicUnder = rx("(?<![_\\w])_(?=[^\\s_])([^_\\n]+?)(?<=[^\\s_])_(?![_\\w])")
    private static let strike = rx("~~(?=\\S)(.+?)(?<=\\S)~~")
    private static let underline = rx("<u>(.+?)</u>", [.caseInsensitive])
    private static let code = rx("`([^`\\n]+)`")
    private static let quote = rx("^(>[ \\t]?)(.*)$", [.anchorsMatchLines])
    private static let bullet = rx("^([ \\t]*(?:[-*+]|\\d+\\.)[ \\t]+)", [.anchorsMatchLines])
    private static let link = rx("\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)")

    static func apply(to tv: NSTextView, baseFont: NSFont, paragraph: NSParagraphStyle, accent: NSColor) {
        guard let storage = tv.textStorage, storage.length > 0, !tv.hasMarkedText() else { return }
        let text = storage.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        let dim = NSColor.tertiaryLabelColor
        let fm = NSFontManager.shared

        let savedSelection = tv.selectedRanges
        storage.beginEditing()
        // Reset to the plain look first.
        storage.setAttributes([.font: baseFont, .paragraphStyle: paragraph, .foregroundColor: NSColor.labelColor], range: full)

        func trait(_ t: NSFontTraitMask, _ range: NSRange) {
            guard range.length > 0 else { return }
            storage.enumerateAttribute(.font, in: range) { value, r, _ in
                let f = (value as? NSFont) ?? baseFont
                storage.addAttribute(.font, value: fm.convert(f, toHaveTrait: t), range: r)
            }
        }
        func scale(_ factor: CGFloat, _ range: NSRange) {
            guard range.length > 0 else { return }
            storage.enumerateAttribute(.font, in: range) { value, r, _ in
                let f = (value as? NSFont) ?? baseFont
                storage.addAttribute(.font, value: fm.convert(f, toSize: baseFont.pointSize * factor), range: r)
            }
        }
        func dimMarkers(_ whole: NSRange, content: NSRange) {
            let before = NSRange(location: whole.location, length: content.location - whole.location)
            let afterStart = content.location + content.length
            let after = NSRange(location: afterStart, length: whole.location + whole.length - afterStart)
            if before.length > 0 { storage.addAttribute(.foregroundColor, value: dim, range: before) }
            if after.length > 0 { storage.addAttribute(.foregroundColor, value: dim, range: after) }
        }
        func each(_ regex: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            regex.enumerateMatches(in: text, options: [], range: full) { m, _, _ in if let m = m { body(m) } }
        }

        // Block level
        each(heading) { m in
            let level = m.range(at: 1).length
            let factors: [CGFloat] = [1.6, 1.4, 1.25, 1.15, 1.08, 1.0]
            scale(factors[min(level, 6) - 1], m.range)
            trait(.boldFontMask, m.range)
            storage.addAttribute(.foregroundColor, value: dim, range: m.range(at: 1))
        }
        each(quote) { m in
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range(at: 2))
            storage.addAttribute(.foregroundColor, value: dim, range: m.range(at: 1))
            trait(.italicFontMask, m.range(at: 2))
        }
        each(bullet) { m in
            storage.addAttribute(.foregroundColor, value: accent, range: m.range(at: 1))
        }

        // Inline
        each(boldItalic) { m in
            trait(.boldFontMask, m.range(at: 1)); trait(.italicFontMask, m.range(at: 1))
            dimMarkers(m.range, content: m.range(at: 1))
        }
        each(bold) { m in
            trait(.boldFontMask, m.range(at: 2))
            dimMarkers(m.range, content: m.range(at: 2))
        }
        each(italicStar) { m in
            trait(.italicFontMask, m.range(at: 1)); dimMarkers(m.range, content: m.range(at: 1))
        }
        each(italicUnder) { m in
            trait(.italicFontMask, m.range(at: 1)); dimMarkers(m.range, content: m.range(at: 1))
        }
        each(strike) { m in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1))
            dimMarkers(m.range, content: m.range(at: 1))
        }
        each(underline) { m in
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1))
            dimMarkers(m.range, content: m.range(at: 1))
        }
        each(code) { m in
            let mono = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.92, weight: .regular)
            storage.addAttribute(.font, value: mono, range: m.range(at: 1))
            storage.addAttribute(.backgroundColor, value: NSColor.labelColor.withAlphaComponent(0.09), range: m.range(at: 1))
            dimMarkers(m.range, content: m.range(at: 1))
        }
        each(link) { m in
            storage.addAttribute(.foregroundColor, value: accent, range: m.range(at: 1))
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1))
            storage.addAttribute(.foregroundColor, value: dim, range: m.range(at: 2))
        }
        storage.endEditing()
        if tv.selectedRanges != savedSelection { tv.selectedRanges = savedSelection }

        // Text typed next should use the plain look, not whatever styling the character before it has.
        tv.typingAttributes = [.font: baseFont, .paragraphStyle: paragraph, .foregroundColor: NSColor.labelColor]
    }
}

// MARK: - NSTextView wrapper
struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    var controller: EditorController? = nil
    var listensForFocus = false
    var forceLight = false
    @ObservedObject private var settings = AppSettings.shared

    init(text: Binding<String>, controller: EditorController? = nil, listensForFocus: Bool = false, forceLight: Bool = false) {
        self._text = text
        self.controller = controller
        self.listensForFocus = listensForFocus
        self.forceLight = forceLight
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.textContainerInset = NSSize(width: 12, height: 14)
        tv.string = text
        context.coordinator.lastSent = text
        if forceLight { tv.appearance = NSAppearance(named: .aqua) }

        controller?.textView = tv
        context.coordinator.attach(to: tv)
        applyStyle(tv, coordinator: context.coordinator, force: true)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        controller?.textView = tv

        // The text view is the source of truth while the user types: never overwrite it with the
        // value we just sent up (SwiftUI may deliver it a beat later), or the caret jumps.
        let isOwnEcho = (text == context.coordinator.lastSent)
        if tv.string != text && !isOwnEcho {
            context.coordinator.lastSent = text
            let selection = tv.selectedRange()
            let oldLength = (tv.string as NSString).length
            tv.string = text
            let newLength = (text as NSString).length
            let isTyping = tv.window?.firstResponder === tv
            let wasAtEnd = !isTyping && selection.location >= oldLength
            let location = wasAtEnd ? newLength : min(selection.location, newLength)
            tv.setSelectedRange(NSRange(location: location, length: 0))
            applyStyle(tv, coordinator: context.coordinator, force: true)
            if !isTyping { tv.scrollRangeToVisible(tv.selectedRange()) }
        } else {
            applyStyle(tv, coordinator: context.coordinator, force: false)
        }
    }

    // MARK: Styling
    /// Re-applies live Markdown styling after an edit.
    func restyle(_ tv: NSTextView) {
        guard settings.liveMarkdown else { return }
        let font = Self.font(size: CGFloat(settings.fontSize), design: settings.editorFontDesign)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = CGFloat(settings.lineSpacing)
        MarkdownStyler.apply(to: tv, baseFont: font, paragraph: paragraph, accent: NSColor(settings.accentColor))
    }

    static func font(size: CGFloat, design: String) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        switch EditorFontDesign(rawValue: design) ?? .standard {
        case .standard: return base
        case .mono:     return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .serif:
            if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { return f }
            return base
        case .rounded:
            if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
            return base
        }
    }

    private func applyStyle(_ tv: NSTextView, coordinator: Coordinator, force: Bool) {
        let key = "\(settings.fontSize)|\(settings.lineSpacing)|\(settings.editorFontDesign)|\(settings.spellCheck)|\(settings.smartQuotes)|\(settings.autoCorrect)|\(settings.liveMarkdown)|\(settings.accentHex)"
        guard force || key != coordinator.styleKey else { return }
        coordinator.styleKey = key

        let font = Self.font(size: CGFloat(settings.fontSize), design: settings.editorFontDesign)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = CGFloat(settings.lineSpacing)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.labelColor
        ]
        tv.font = font
        tv.defaultParagraphStyle = paragraph
        tv.typingAttributes = attributes
        if settings.liveMarkdown {
            MarkdownStyler.apply(to: tv, baseFont: font, paragraph: paragraph, accent: NSColor(settings.accentColor))
        } else if let storage = tv.textStorage, storage.length > 0 {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
        tv.isContinuousSpellCheckingEnabled = settings.spellCheck
        tv.isAutomaticSpellingCorrectionEnabled = settings.autoCorrect
        tv.isAutomaticQuoteSubstitutionEnabled = settings.smartQuotes
    }

    // MARK: Coordinator
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextEditor
        var styleKey = ""
        var lastSent = ""
        private var observer: NSObjectProtocol?

        init(_ parent: NoteTextEditor) { self.parent = parent }

        func attach(to textView: NSTextView) {
            guard parent.listensForFocus else { return }
            observer = NotificationCenter.default.addObserver(forName: .focusEditor, object: nil, queue: .main) { [weak textView] _ in
                guard let tv = textView else { return }
                tv.window?.makeFirstResponder(tv)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            lastSent = tv.string
            if parent.text != tv.string { parent.text = tv.string }
            parent.restyle(tv)
            if !DictationManager.shared.isRecording { SoundManager.shared.play(.keyTap) }
        }
    }
}

// MARK: - Markdown preview
struct MarkdownPreviewView: View {
    let text: String
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                row(line.trimmingCharacters(in: .whitespaces))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func row(_ line: String) -> some View {
        if line.hasPrefix("### ") {
            inline(String(line.dropFirst(4))).font(.system(size: 15, weight: .semibold)).padding(.top, 4)
        } else if line.hasPrefix("## ") {
            inline(String(line.dropFirst(3))).font(.system(size: 17, weight: .bold)).padding(.top, 6)
        } else if line.hasPrefix("# ") {
            inline(String(line.dropFirst(2))).font(.system(size: 20, weight: .heavy)).padding(.top, 8)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(Color.primary.opacity(0.6)).frame(width: 5, height: 5).padding(.top, 7)
                inline(String(line.dropFirst(2)))
            }
        } else if line.hasPrefix("> ") {
            HStack(spacing: 8) {
                Rectangle().fill(settings.accentColor).frame(width: 3)
                inline(String(line.dropFirst(2))).foregroundStyle(.secondary)
            }
        } else if line.hasPrefix("---") {
            Divider().padding(.vertical, 4)
        } else if line.isEmpty {
            Spacer().frame(height: 4)
        } else {
            inline(line)
        }
    }

    private func parse(_ raw: String) -> AttributedString {
        (try? AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(raw)
    }

    /// Markdown inline styles plus <u>underline</u>.
    private func inline(_ raw: String) -> Text {
        let parts = raw.components(separatedBy: "<u>")
        var result = Text(parse(parts[0]))
        for part in parts.dropFirst() {
            let pieces = part.components(separatedBy: "</u>")
            result = result + Text(parse(pieces[0])).underline()
            if pieces.count > 1 { result = result + Text(parse(pieces.dropFirst().joined(separator: "</u>"))) }
        }
        return result
    }
}

// MARK: - Dictation controls (mic button, level meter, save / cancel)
struct DictationControls: View {
    var getText: (() -> String)? = nil
    var setText: ((String) -> Void)? = nil

    @ObservedObject private var dictation = DictationManager.shared
    @ObservedObject private var settings = AppSettings.shared

    private var elapsedText: String {
        let total = Int(dictation.elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        HStack(spacing: 8) {
            if !settings.dictationEnabled {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .frame(width: 28, height: 24)
                    .help("Dictation is turned off in Settings")
            } else {
                Button(action: toggle) {
                    Group {
                        if dictation.isRecording {
                            WaveformView(levels: Array(dictation.levels.suffix(18)), width: 70, height: 22)
                        } else if dictation.isTranscribing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "mic.fill").font(.system(size: 14))
                        }
                    }
                    .frame(width: dictation.isRecording ? 70 : 28, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(dictation.isRecording ? Color.red : settings.accentColor)
                .help(helpText)

                if dictation.isRecording {
                    Text(elapsedText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button { dictation.stopAndSave() } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(SoftButtonStyle(tint: .green))
                    .help("Stop and save the dictation as a .md file")

                    Button { dictation.stop() } label: {
                        Image(systemName: "stop.circle.fill").font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.red)
                    .help("Stop dictation and keep the text in the note (no file is written)")
                } else if dictation.isTranscribing {
                    Text("Transcribing…").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize()
    }

    private var helpText: String {
        dictation.isRecording ? "Stop dictation" : "Start dictation (\(settings.dictationEngine.shortTitle))"
    }

    private func toggle() {
        if dictation.isRecording {
            dictation.stop()
        } else {
            dictation.start(into: getText, set: setText)
        }
    }
}
