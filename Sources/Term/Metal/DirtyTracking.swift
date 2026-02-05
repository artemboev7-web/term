import Foundation

/// Tracks dirty regions for partial updates
final class DirtyTracker {
    // MARK: - Types

    struct DirtyRegion: Equatable {
        let startRow: Int
        let endRow: Int
        let startCol: Int
        let endCol: Int

        var rowCount: Int { endRow - startRow + 1 }
        var colCount: Int { endCol - startCol + 1 }
        var cellCount: Int { rowCount * colCount }

        func contains(row: Int, col: Int) -> Bool {
            return row >= startRow && row <= endRow && col >= startCol && col <= endCol
        }

        func merged(with other: DirtyRegion) -> DirtyRegion {
            return DirtyRegion(
                startRow: min(startRow, other.startRow),
                endRow: max(endRow, other.endRow),
                startCol: min(startCol, other.startCol),
                endCol: max(endCol, other.endCol)
            )
        }
    }

    enum DirtyState {
        case clean
        case partiallyDirty([DirtyRegion])
        case fullyDirty
    }

    // MARK: - Properties

    private var dirtyRows: Set<Int> = []
    private var dirtyRegions: [DirtyRegion] = []
    private var isFullyDirty: Bool = true

    private let rows: Int
    private let cols: Int

    // Threshold for switching to full redraw
    private let fullRedrawThreshold: Double = 0.5  // 50% dirty = full redraw

    // MARK: - Initialization

    init(rows: Int, cols: Int) {
        self.rows = rows
        self.cols = cols
    }

    // MARK: - Marking Dirty

    func markDirty(row: Int) {
        guard row >= 0 && row < rows else { return }
        dirtyRows.insert(row)
        checkThreshold()
    }

    func markDirty(rows range: Range<Int>) {
        for row in range where row >= 0 && row < rows {
            dirtyRows.insert(row)
        }
        checkThreshold()
    }

    func markDirty(region: DirtyRegion) {
        dirtyRegions.append(region)
        checkThreshold()
    }

    func markFullyDirty() {
        isFullyDirty = true
        dirtyRows.removeAll()
        dirtyRegions.removeAll()
    }

    func markClean() {
        isFullyDirty = false
        dirtyRows.removeAll()
        dirtyRegions.removeAll()
    }

    // MARK: - Querying

    var state: DirtyState {
        if isFullyDirty {
            return .fullyDirty
        }
        if dirtyRows.isEmpty && dirtyRegions.isEmpty {
            return .clean
        }
        return .partiallyDirty(computeRegions())
    }

    var isDirty: Bool {
        return isFullyDirty || !dirtyRows.isEmpty || !dirtyRegions.isEmpty
    }

    func isRowDirty(_ row: Int) -> Bool {
        if isFullyDirty { return true }
        if dirtyRows.contains(row) { return true }
        return dirtyRegions.contains { $0.contains(row: row, col: 0) }
    }

    // MARK: - Private

    private func checkThreshold() {
        // If too many rows are dirty, switch to full redraw
        let dirtyRatio = Double(dirtyRows.count) / Double(rows)
        if dirtyRatio >= fullRedrawThreshold {
            markFullyDirty()
        }
    }

    private func computeRegions() -> [DirtyRegion] {
        // Convert dirty rows to regions
        var regions: [DirtyRegion] = []

        // Sort dirty rows and merge consecutive
        let sortedRows = dirtyRows.sorted()
        var currentStart: Int?
        var currentEnd: Int?

        for row in sortedRows {
            if let start = currentStart, let end = currentEnd {
                if row == end + 1 {
                    // Extend current region
                    currentEnd = row
                } else {
                    // Close current region and start new
                    regions.append(DirtyRegion(
                        startRow: start,
                        endRow: end,
                        startCol: 0,
                        endCol: cols - 1
                    ))
                    currentStart = row
                    currentEnd = row
                }
            } else {
                // Start first region
                currentStart = row
                currentEnd = row
            }
        }

        // Close last region
        if let start = currentStart, let end = currentEnd {
            regions.append(DirtyRegion(
                startRow: start,
                endRow: end,
                startCol: 0,
                endCol: cols - 1
            ))
        }

        // Add explicit regions
        regions.append(contentsOf: dirtyRegions)

        // Merge overlapping regions
        return mergeRegions(regions)
    }

    private func mergeRegions(_ regions: [DirtyRegion]) -> [DirtyRegion] {
        guard regions.count > 1 else { return regions }

        var merged: [DirtyRegion] = []
        var sorted = regions.sorted { $0.startRow < $1.startRow }

        var current = sorted.removeFirst()

        for region in sorted {
            // Check if regions overlap or are adjacent
            if region.startRow <= current.endRow + 1 {
                current = current.merged(with: region)
            } else {
                merged.append(current)
                current = region
            }
        }
        merged.append(current)

        return merged
    }

    // MARK: - Resize

    func resize(rows: Int, cols: Int) -> DirtyTracker {
        // Create new tracker with new dimensions
        let newTracker = DirtyTracker(rows: rows, cols: cols)
        newTracker.markFullyDirty()  // Full redraw after resize
        return newTracker
    }
}

// MARK: - Scroll Region Tracking

extension DirtyTracker {
    /// Mark scroll region as dirty (common terminal operation)
    func markScrollRegion(top: Int, bottom: Int, scrolled: Int) {
        if scrolled == 0 { return }

        // When scrolling, the entire scroll region is potentially dirty
        // but we can optimize by only marking the newly revealed lines
        if abs(scrolled) >= (bottom - top + 1) {
            // Full scroll region is dirty
            markDirty(rows: top..<(bottom + 1))
        } else if scrolled > 0 {
            // Scrolled up: bottom lines are newly revealed
            markDirty(rows: (bottom - scrolled + 1)..<(bottom + 1))
        } else {
            // Scrolled down: top lines are newly revealed
            markDirty(rows: top..<(top - scrolled))
        }
    }

    /// Mark line edit as dirty (insert/delete characters)
    func markLineEdit(row: Int, startCol: Int) {
        markDirty(region: DirtyRegion(
            startRow: row,
            endRow: row,
            startCol: startCol,
            endCol: cols - 1
        ))
    }
}
