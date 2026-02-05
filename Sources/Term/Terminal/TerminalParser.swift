import Foundation

// MARK: - Parser State

/// Parser state machine states
public enum ParserState {
    case ground
    case escape
    case escapeIntermediate
    case csiEntry
    case csiParam
    case csiIntermediate
    case csiIgnore
    case oscString
    case dcsEntry
    case dcsParam
    case dcsPassthrough
    case sosPmApcString
}

// MARK: - CSI Parameters

/// Parsed CSI parameters
public struct CSIParams {
    public var params: [Int]
    public var intermediates: [UInt8]
    public var finalByte: UInt8

    public init() {
        self.params = []
        self.intermediates = []
        self.finalByte = 0
    }

    /// Get parameter with default value
    public func param(_ index: Int, default defaultValue: Int) -> Int {
        if index < params.count && params[index] > 0 {
            return params[index]
        }
        return defaultValue
    }

    /// Check if parameter is present and non-zero
    public func hasParam(_ index: Int) -> Bool {
        return index < params.count && params[index] > 0
    }
}

// MARK: - Parser Events

/// Events emitted by parser
public enum ParserEvent {
    case print(Character)
    case execute(UInt8)           // C0/C1 control
    case csi(CSIParams)           // CSI sequence
    case esc(UInt8, [UInt8])      // ESC sequence
    case osc(Int, String)         // OSC sequence
    case dcs(String)              // DCS sequence
}

// MARK: - Terminal Parser

/// VT100/xterm escape sequence parser
public final class TerminalParser {
    public weak var delegate: TerminalParserDelegate?

    private var state: ParserState = .ground
    private var intermediates: [UInt8] = []
    private var params: [Int] = []
    private var currentParam: Int = 0
    private var oscBuffer: String = ""
    private var oscParam: Int = 0
    private var dcsBuffer: String = ""

    // UTF-8 decoding state
    private var utf8Buffer: [UInt8] = []
    private var utf8Remaining: Int = 0

    public init() {}

    // MARK: - Public API

    /// Parse input data
    public func parse(_ data: Data) {
        for byte in data {
            parseByte(byte)
        }
    }

    /// Parse input string
    public func parse(_ string: String) {
        parse(Data(string.utf8))
    }

    // MARK: - State Machine

    private func parseByte(_ byte: UInt8) {
        // Handle UTF-8 continuation
        if utf8Remaining > 0 {
            if byte & 0xC0 == 0x80 {
                utf8Buffer.append(byte)
                utf8Remaining -= 1
                if utf8Remaining == 0 {
                    if let string = String(bytes: utf8Buffer, encoding: .utf8),
                       let char = string.first {
                        delegate?.parser(self, print: char)
                    }
                    utf8Buffer.removeAll()
                }
                return
            } else {
                // Invalid UTF-8, reset
                utf8Buffer.removeAll()
                utf8Remaining = 0
            }
        }

        // Start of UTF-8 multibyte sequence
        if byte >= 0xC0 && byte < 0xFE {
            utf8Buffer = [byte]
            if byte < 0xE0 {
                utf8Remaining = 1
            } else if byte < 0xF0 {
                utf8Remaining = 2
            } else if byte < 0xF8 {
                utf8Remaining = 3
            } else {
                utf8Remaining = 0
                utf8Buffer.removeAll()
            }
            return
        }

        switch state {
        case .ground:
            handleGround(byte)
        case .escape:
            handleEscape(byte)
        case .escapeIntermediate:
            handleEscapeIntermediate(byte)
        case .csiEntry:
            handleCSIEntry(byte)
        case .csiParam:
            handleCSIParam(byte)
        case .csiIntermediate:
            handleCSIIntermediate(byte)
        case .csiIgnore:
            handleCSIIgnore(byte)
        case .oscString:
            handleOSCString(byte)
        case .dcsEntry:
            handleDCSEntry(byte)
        case .dcsParam:
            handleDCSParam(byte)
        case .dcsPassthrough:
            handleDCSPassthrough(byte)
        case .sosPmApcString:
            handleSOSPMAPC(byte)
        }
    }

    // MARK: - State Handlers

    private func handleGround(_ byte: UInt8) {
        switch byte {
        case 0x00...0x17, 0x19, 0x1C...0x1F:
            // C0 control (except ESC)
            delegate?.parser(self, execute: byte)

        case 0x1B:
            // ESC
            state = .escape
            intermediates.removeAll()

        case 0x20...0x7E:
            // Printable ASCII
            delegate?.parser(self, print: Character(UnicodeScalar(byte)))

        case 0x7F:
            // DEL - ignore
            break

        case 0x80...0x8F, 0x91...0x97, 0x99, 0x9A:
            // C1 controls
            delegate?.parser(self, execute: byte)

        case 0x90:
            // DCS
            state = .dcsEntry
            params.removeAll()
            currentParam = 0
            dcsBuffer = ""

        case 0x9B:
            // CSI
            state = .csiEntry
            params.removeAll()
            currentParam = 0
            intermediates.removeAll()

        case 0x9C:
            // ST - ignore outside sequence
            break

        case 0x9D:
            // OSC
            state = .oscString
            oscBuffer = ""
            oscParam = 0

        case 0x9E, 0x9F:
            // PM, APC
            state = .sosPmApcString

        default:
            break
        }
    }

    private func handleEscape(_ byte: UInt8) {
        switch byte {
        case 0x00...0x17, 0x19, 0x1C...0x1F:
            // Execute C0 control
            delegate?.parser(self, execute: byte)

        case 0x1B:
            // Another ESC - stay in escape
            break

        case 0x20...0x2F:
            // Intermediate
            intermediates.append(byte)
            state = .escapeIntermediate

        case 0x30...0x4F, 0x51...0x57, 0x59, 0x5A, 0x5C, 0x60...0x7E:
            // ESC final byte
            delegate?.parser(self, esc: byte, intermediates: intermediates)
            state = .ground

        case 0x50:
            // ESC P = DCS
            state = .dcsEntry
            params.removeAll()
            currentParam = 0
            dcsBuffer = ""

        case 0x58, 0x5E, 0x5F:
            // ESC X, ^, _ = SOS, PM, APC
            state = .sosPmApcString

        case 0x5B:
            // ESC [ = CSI
            state = .csiEntry
            params.removeAll()
            currentParam = 0
            intermediates.removeAll()

        case 0x5D:
            // ESC ] = OSC
            state = .oscString
            oscBuffer = ""
            oscParam = 0

        case 0x7F:
            // DEL - ignore
            break

        default:
            state = .ground
        }
    }

    private func handleEscapeIntermediate(_ byte: UInt8) {
        switch byte {
        case 0x00...0x17, 0x19, 0x1C...0x1F:
            delegate?.parser(self, execute: byte)

        case 0x1B:
            state = .escape
            intermediates.removeAll()

        case 0x20...0x2F:
            intermediates.append(byte)

        case 0x30...0x7E:
            delegate?.parser(self, esc: byte, intermediates: intermediates)
            state = .ground

        default:
            state = .ground
        }
    }

    private func handleCSIEntry(_ byte: UInt8) {
        switch byte {
        case 0x00...0x17, 0x19, 0x1C...0x1F:
            delegate?.parser(self, execute: byte)

        case 0x1B:
            state = .escape
            intermediates.removeAll()

        case 0x20...0x2F:
            intermediates.append(byte)
            state = .csiIntermediate

        case 0x30...0x39:
            // Digit
            currentParam = Int(byte - 0x30)
            state = .csiParam

        case 0x3A:
            // : - subparameter separator (ignore for now)
            state = .csiParam

        case 0x3B:
            // ; - parameter separator
            params.append(0)
            state = .csiParam

        case 0x3C...0x3F:
            // Private parameter prefix
            intermediates.append(byte)
            state = .csiParam

        case 0x40...0x7E:
            // Final byte
            dispatchCSI(byte)

        case 0x7F:
            // DEL - ignore
            break

        default:
            state = .ground
        }
    }

    private func handleCSIParam(_ byte: UInt8) {
        switch byte {
        case 0x00...0x17, 0x19, 0x1C...0x1F:
            delegate?.parser(self, execute: byte)

        case 0x1B:
            state = .escape
            intermediates.removeAll()

        case 0x20...0x2F:
            intermediates.append(byte)
            state = .csiIntermediate

        case 0x30...0x39:
            // Digit
            currentParam = currentParam * 10 + Int(byte - 0x30)

        case 0x3A:
            // : - subparameter (ignore)
            break

        case 0x3B:
            // ; - next parameter
            params.append(currentParam)
            currentParam = 0

        case 0x3C...0x3F:
            // Private prefix in wrong position - ignore
            state = .csiIgnore

        case 0x40...0x7E:
            // Final byte
            params.append(currentParam)
            dispatchCSI(byte)

        case 0x7F:
            break

        default:
            state = .csiIgnore
        }
    }

    private func handleCSIIntermediate(_ byte: UInt8) {
        switch byte {
        case 0x00...0x17, 0x19, 0x1C...0x1F:
            delegate?.parser(self, execute: byte)

        case 0x1B:
            state = .escape
            intermediates.removeAll()

        case 0x20...0x2F:
            intermediates.append(byte)

        case 0x30...0x3F:
            state = .csiIgnore

        case 0x40...0x7E:
            params.append(currentParam)
            dispatchCSI(byte)

        default:
            state = .csiIgnore
        }
    }

    private func handleCSIIgnore(_ byte: UInt8) {
        switch byte {
        case 0x1B:
            state = .escape
            intermediates.removeAll()

        case 0x40...0x7E:
            state = .ground

        default:
            break
        }
    }

    private func handleOSCString(_ byte: UInt8) {
        switch byte {
        case 0x07:
            // BEL terminates OSC
            dispatchOSC()
            state = .ground

        case 0x1B:
            // Might be ESC \ (ST)
            // For simplicity, terminate on ESC
            dispatchOSC()
            state = .escape

        case 0x9C:
            // ST terminates OSC
            dispatchOSC()
            state = .ground

        case 0x30...0x39:
            // Digit for OSC param
            if oscBuffer.isEmpty {
                oscParam = oscParam * 10 + Int(byte - 0x30)
            } else {
                oscBuffer.append(Character(UnicodeScalar(byte)))
            }

        case 0x3B:
            // ; separates param from string
            if oscBuffer.isEmpty {
                // First ; marks end of numeric param
            }
            oscBuffer.append(Character(UnicodeScalar(byte)))

        case 0x20...0x7E:
            oscBuffer.append(Character(UnicodeScalar(byte)))

        default:
            break
        }
    }

    private func handleDCSEntry(_ byte: UInt8) {
        switch byte {
        case 0x1B:
            state = .escape

        case 0x30...0x39, 0x3B:
            state = .dcsParam
            handleDCSParam(byte)

        case 0x40...0x7E:
            state = .dcsPassthrough

        default:
            break
        }
    }

    private func handleDCSParam(_ byte: UInt8) {
        switch byte {
        case 0x1B:
            state = .escape

        case 0x30...0x39:
            currentParam = currentParam * 10 + Int(byte - 0x30)

        case 0x3B:
            params.append(currentParam)
            currentParam = 0

        case 0x40...0x7E:
            params.append(currentParam)
            state = .dcsPassthrough

        default:
            break
        }
    }

    private func handleDCSPassthrough(_ byte: UInt8) {
        switch byte {
        case 0x1B:
            // ESC might terminate
            dispatchDCS()
            state = .escape

        case 0x9C:
            // ST
            dispatchDCS()
            state = .ground

        case 0x20...0x7E:
            dcsBuffer.append(Character(UnicodeScalar(byte)))

        default:
            break
        }
    }

    private func handleSOSPMAPC(_ byte: UInt8) {
        switch byte {
        case 0x1B:
            state = .escape

        case 0x9C:
            state = .ground

        default:
            // Ignore content
            break
        }
    }

    // MARK: - Dispatch

    private func dispatchCSI(_ finalByte: UInt8) {
        var csi = CSIParams()
        csi.params = params
        csi.intermediates = intermediates
        csi.finalByte = finalByte
        delegate?.parser(self, csi: csi)
        state = .ground
    }

    private func dispatchOSC() {
        // Remove leading ; from buffer if present
        var content = oscBuffer
        if content.hasPrefix(";") {
            content.removeFirst()
        }
        delegate?.parser(self, osc: oscParam, content: content)
    }

    private func dispatchDCS() {
        delegate?.parser(self, dcs: dcsBuffer)
    }

    // MARK: - Reset

    public func reset() {
        state = .ground
        intermediates.removeAll()
        params.removeAll()
        currentParam = 0
        oscBuffer = ""
        oscParam = 0
        dcsBuffer = ""
        utf8Buffer.removeAll()
        utf8Remaining = 0
    }
}

// MARK: - Parser Delegate

public protocol TerminalParserDelegate: AnyObject {
    func parser(_ parser: TerminalParser, print char: Character)
    func parser(_ parser: TerminalParser, execute control: UInt8)
    func parser(_ parser: TerminalParser, csi: CSIParams)
    func parser(_ parser: TerminalParser, esc: UInt8, intermediates: [UInt8])
    func parser(_ parser: TerminalParser, osc: Int, content: String)
    func parser(_ parser: TerminalParser, dcs: String)
}
