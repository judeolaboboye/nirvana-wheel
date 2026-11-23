import SwiftUI

/// Small, safe expression evaluator: + - * / % ^, brackets, decimals, unary minus.
/// Written by hand so bad input can never crash the app (NSExpression can).
struct Calc {
    enum Failure: Error, Equatable { case bad, divideByZero }

    static func evaluate(_ text: String) throws -> Double {
        var p = Parser(Array(text.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ",", with: "")
            .filter { !$0.isWhitespace }))
        let v = try p.expression()
        guard p.atEnd, v.isFinite else { throw Failure.bad }
        return v
    }

    static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        let f = NumberFormatter()
        f.maximumFractionDigits = 10
        f.minimumFractionDigits = 0
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private struct Parser {
        let c: [Character]
        var i = 0
        init(_ c: [Character]) { self.c = c }
        var atEnd: Bool { i >= c.count }
        func peek() -> Character? { i < c.count ? c[i] : nil }

        mutating func expression() throws -> Double {
            var v = try term()
            while let ch = peek(), ch == "+" || ch == "-" {
                i += 1
                let r = try term()
                v = ch == "+" ? v + r : v - r
            }
            return v
        }
        mutating func term() throws -> Double {
            var v = try power()
            while let ch = peek(), ch == "*" || ch == "/" || ch == "%" {
                i += 1
                let r = try power()
                switch ch {
                case "*": v *= r
                case "/": guard r != 0 else { throw Failure.divideByZero }; v /= r
                default: guard r != 0 else { throw Failure.divideByZero }; v = v.truncatingRemainder(dividingBy: r)
                }
            }
            return v
        }
        mutating func power() throws -> Double {
            let base = try unary()
            if peek() == "^" { i += 1; return pow(base, try power()) } // right-associative
            return base
        }
        mutating func unary() throws -> Double {
            if peek() == "-" { i += 1; return -(try unary()) }
            if peek() == "+" { i += 1; return try unary() }
            return try primary()
        }
        mutating func primary() throws -> Double {
            if peek() == "(" {
                i += 1
                let v = try expression()
                guard peek() == ")" else { throw Failure.bad }
                i += 1
                return v
            }
            let start = i
            while let ch = peek(), ch.isNumber || ch == "." { i += 1 }
            guard i > start, let v = Double(String(c[start..<i])) else { throw Failure.bad }
            return v
        }
    }
}

struct CalculatorView: View {
    @State private var input = ""
    @State private var history: [(String, String)] = []
    @FocusState private var focused: Bool

    private var preview: String {
        guard !input.isEmpty else { return " " }
        do { return "= " + Calc.format(try Calc.evaluate(input)) }
        catch Calc.Failure.divideByZero { return "can't divide by 0" }
        catch { return " " }
    }

    var body: some View {
        MiniCard {
            TextField("2 * (3 + 4)", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .focused($focused)
                .onSubmit(commit)
            Text(preview)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(ringAccent)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(history.enumerated().reversed()), id: \.offset) { _, row in
                        Button { copyToClipboard(row.1) } label: {
                            HStack {
                                Text(row.0).foregroundStyle(.secondary)
                                Spacer()
                                Text(row.1).bold()
                            }.font(.system(.body, design: .monospaced))
                        }.buttonStyle(.plain).help("Copy result")
                    }
                }
            }
            Text("Return keeps the result · click a line to copy it").font(.caption).foregroundStyle(.tertiary)
        }
        .onAppear { focused = true }
    }

    private func commit() {
        guard let v = try? Calc.evaluate(input) else { return }
        let r = Calc.format(v)
        history.append((input, r))
        copyToClipboard(r)
        input = r
    }
}
