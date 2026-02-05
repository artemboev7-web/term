import AppKit

protocol SearchBarDelegate: AnyObject {
    func searchBar(_ searchBar: SearchBarView, didSearchFor query: String)
    func searchBarDidRequestNext(_ searchBar: SearchBarView)
    func searchBarDidRequestPrevious(_ searchBar: SearchBarView)
    func searchBarDidClose(_ searchBar: SearchBarView)
}

class SearchBarView: NSView {
    weak var delegate: SearchBarDelegate?

    private var searchField: NSTextField!
    private var resultsLabel: NSTextField!
    private var prevButton: NSButton!
    private var nextButton: NSButton!
    private var closeButton: NSButton!

    private(set) var currentQuery: String = ""
    private var matchCount: Int = 0
    private var currentMatch: Int = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.95).cgColor

        // Search field
        searchField = NSTextField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Find in terminal..."
        searchField.bezelStyle = .roundedBezel
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        searchField.delegate = self
        addSubview(searchField)

        // Results label
        resultsLabel = NSTextField(labelWithString: "")
        resultsLabel.translatesAutoresizingMaskIntoConstraints = false
        resultsLabel.font = NSFont.systemFont(ofSize: 11)
        resultsLabel.textColor = NSColor.secondaryLabelColor
        addSubview(resultsLabel)

        // Previous button
        prevButton = NSButton(image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous")!, target: self, action: #selector(prevClicked))
        prevButton.translatesAutoresizingMaskIntoConstraints = false
        prevButton.bezelStyle = .texturedRounded
        prevButton.isBordered = false
        addSubview(prevButton)

        // Next button
        nextButton = NSButton(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next")!, target: self, action: #selector(nextClicked))
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.bezelStyle = .texturedRounded
        nextButton.isBordered = false
        addSubview(nextButton)

        // Close button
        closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!, target: self, action: #selector(closeClicked))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .texturedRounded
        closeButton.isBordered = false
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            // Search field
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 200),

            // Results label
            resultsLabel.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            resultsLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Prev button
            prevButton.leadingAnchor.constraint(equalTo: resultsLabel.trailingAnchor, constant: 8),
            prevButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Next button
            nextButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 4),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Close button
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // MARK: - Public

    func focus() {
        window?.makeFirstResponder(searchField)
    }

    func updateResults(count: Int, current: Int) {
        matchCount = count
        currentMatch = current

        if count == 0 {
            resultsLabel.stringValue = currentQuery.isEmpty ? "" : "No results"
            resultsLabel.textColor = NSColor.systemRed
        } else {
            resultsLabel.stringValue = "\(current + 1) of \(count)"
            resultsLabel.textColor = NSColor.secondaryLabelColor
        }
    }

    // MARK: - Actions

    @objc private func searchFieldChanged() {
        let query = searchField.stringValue
        currentQuery = query
        delegate?.searchBar(self, didSearchFor: query)
    }

    @objc private func prevClicked() {
        delegate?.searchBarDidRequestPrevious(self)
    }

    @objc private func nextClicked() {
        delegate?.searchBarDidRequestNext(self)
    }

    @objc private func closeClicked() {
        delegate?.searchBarDidClose(self)
    }

    // Handle Escape key
    override func cancelOperation(_ sender: Any?) {
        delegate?.searchBarDidClose(self)
    }
}

// MARK: - NSTextFieldDelegate

extension SearchBarView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            // Enter = next match
            delegate?.searchBarDidRequestNext(self)
            return true
        } else if commandSelector == #selector(cancelOperation(_:)) {
            // Escape = close
            delegate?.searchBarDidClose(self)
            return true
        }
        return false
    }
}
