import CoreText
import UIKit

/// Renders the waiver template as a paginated, unsigned PDF for the client to
/// sign and return. Text-only, so it uses Core Text pagination rather than
/// ReportExporter's single-page ImageRenderer.
enum WaiverPDFRenderer {
    static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)  // US Letter, like ReportExporter
    static let margin: CGFloat = 54
    /// Extra room at the bottom for the page footer.
    static let footerHeight: CGFloat = 24
    static let directory = FileManager.default.temporaryDirectory
        .appending(path: "Waivers", directoryHint: .isDirectory)

    /// Writes the PDF with complete file protection (it holds client PII).
    static func render(body: String, clientName: String, trainerName: String?, version: Int, date: Date) throws -> URL {
        removeAll()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "Waiver - \(sanitized(clientName)).pdf")
        let data = pdfData(body: body, clientName: clientName, trainerName: trainerName, version: version, date: date)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func pdfData(body: String, clientName: String, trainerName: String?, version: Int, date: Date) -> Data {
        let text = attributed(body: body, clientName: clientName, trainerName: trainerName, date: date)
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        // Core Text draws bottom-up, so the frame is laid out in the flipped space.
        let frameRect = CGRect(
            x: margin,
            y: margin + footerHeight,
            width: pageRect.width - margin * 2,
            height: pageRect.height - margin * 2 - footerHeight
        )
        return UIGraphicsPDFRenderer(bounds: pageRect).pdfData { ctx in
            var location = 0
            var page = 0
            repeat {
                ctx.beginPage()
                page += 1
                let cg = ctx.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: pageRect.height)
                cg.scaleBy(x: 1, y: -1)
                let frame = CTFramesetterCreateFrame(
                    framesetter, CFRange(location: location, length: 0), CGPath(rect: frameRect, transform: nil), nil
                )
                CTFrameDraw(frame, cg)
                cg.restoreGState()
                let visible = CTFrameGetVisibleStringRange(frame)
                location = visible.location + visible.length
                drawFooter(page: page, version: version)
                if visible.length == 0 { break }  // nothing fits; avoid an endless loop
            } while location < text.length
        }
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Private

    private static func drawFooter(page: Int, version: Int) {
        let footer = "Template v\(version) · Page \(page)" as NSString
        footer.draw(
            at: CGPoint(x: margin, y: pageRect.height - margin),
            withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.gray]
        )
    }

    /// Body syntax: `#` lines are hidden, ALL-CAPS lines are headings, and lines
    /// starting with `!! ` are bold (the conspicuous release paragraphs).
    static func attributed(body: String, clientName: String, trainerName: String?, date: Date) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let regular = UIFont.systemFont(ofSize: 10.5)
        let bold = UIFont.boldSystemFont(ofSize: 10.5)
        let heading = UIFont.boldSystemFont(ofSize: 12)
        let title = UIFont.boldSystemFont(ofSize: 16)

        func paragraph(spacingBefore: CGFloat, after: CGFloat = 4) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = spacingBefore
            style.paragraphSpacing = after
            return style
        }
        func append(_ string: String, font: UIFont, before: CGFloat = 0) {
            out.append(NSAttributedString(string: string + "\n", attributes: [
                .font: font, .foregroundColor: UIColor.black, .paragraphStyle: paragraph(spacingBefore: before),
            ]))
        }

        var lines = body.components(separatedBy: .newlines).filter { !$0.hasPrefix("#") }
        // The first non-empty line is the document title.
        if let firstIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            append(lines[firstIndex], font: title)
            lines.removeSubrange(...firstIndex)
        }
        append("Client: \(clientName)", font: regular, before: 6)
        append("Trainer: \(trainerName ?? "______________________")", font: regular)
        append("Prepared \(date.formatted(date: .abbreviated, time: .omitted))", font: regular)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("!! ") {
                append(String(trimmed.dropFirst(3)), font: bold, before: 2)
            } else if trimmed == trimmed.uppercased() && trimmed.contains(where: \.isLetter) && !trimmed.contains(":") {
                append(trimmed, font: heading, before: 10)
            } else {
                append(trimmed, font: regular, before: 2)
            }
        }
        return out
    }

    /// Same rule as ReportExporter: no path separators in file names.
    private static func sanitized(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }
}
