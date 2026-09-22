import UIKit

enum PDFExporter {

    // Colori fissi, non dinamici: con UIColor.label & co. un telefono in
    // modalità scura disegnava date e importi in bianco su foglio bianco.
    private static let ink = UIColor(white: 0.10, alpha: 1)
    private static let muted = UIColor(white: 0.42, alpha: 1)
    private static let rule = UIColor(white: 0.82, alpha: 1)
    private static let stripe = UIColor(white: 0.955, alpha: 1)
    private static let accent = UIColor(red: 0.00, green: 0.44, blue: 0.90, alpha: 1)
    private static let positive = UIColor(red: 0.10, green: 0.55, blue: 0.27, alpha: 1)
    private static let negative = UIColor(red: 0.80, green: 0.18, blue: 0.18, alpha: 1)

    static func generate(for sheet: SharedSheet) -> URL {
        var data = Data()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            data = render(sheet)
        }
        let fileName = (sheet.name ?? "spese")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(fileName).pdf")
        try? data.write(to: url)
        return url
    }

    private static func render(_ sheet: SharedSheet) -> Data {
        // A4 orizzontale: la tabella spese ha bisogno di larghezza, non di altezza.
        let page = CGRect(x: 0, y: 0, width: 841.8, height: 595.2)
        let margin: CGFloat = 36
        let contentWidth = page.width - margin * 2
        let bottomLimit = page.height - margin - 14
        let currency = AmountFormatter.symbol(for: sheet.currencyCode ?? "EUR")
        let sheetName = sheet.name ?? NSLocalizedString("sheet", comment: "")

        return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            var y: CGFloat = 0
            var pageNumber = 0

            /// Sempre una riga sola: se il testo non ci sta viene accorciato con "…".
            func text(_ s: String, x: CGFloat, y: CGFloat, width: CGFloat, font: UIFont,
                      color: UIColor = ink, align: NSTextAlignment = .left) {
                let para = NSMutableParagraphStyle()
                para.alignment = align
                para.lineBreakMode = .byTruncatingTail
                (s as NSString).draw(
                    in: CGRect(x: x, y: y, width: width, height: ceil(font.lineHeight)),
                    withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
            }

            func fill(_ rect: CGRect, _ color: UIColor) {
                color.setFill()
                UIRectFill(rect)
            }

            func money(_ value: Double) -> String {
                AmountFormatter.format(value, currencySymbol: currency)
            }

            func newPage() {
                ctx.beginPage()
                pageNumber += 1
                y = margin
                let footer = UIFont.systemFont(ofSize: 7.5)
                text("\(sheetName) · Spese Condivise", x: margin, y: page.height - margin + 6,
                     width: contentWidth / 2, font: footer, color: muted)
                text(String(format: NSLocalizedString("pdf_page", comment: ""), pageNumber),
                     x: margin, y: page.height - margin + 6, width: contentWidth,
                     font: footer, color: muted, align: .right)
            }

            func ensure(_ needed: CGFloat, onNewPage: () -> Void = {}) {
                if y + needed > bottomLimit {
                    newPage()
                    onNewPage()
                }
            }

            func sectionHeader(_ title: String, x: CGFloat, width: CGFloat) {
                text(title.uppercased(), x: x, y: y, width: width,
                     font: .systemFont(ofSize: 8, weight: .semibold), color: muted)
                fill(CGRect(x: x, y: y + 13, width: width, height: 0.5), rule)
            }

            // MARK: Intestazione

            newPage()
            let bannerH: CGFloat = 54
            fill(CGRect(x: 0, y: 0, width: page.width, height: bannerH), accent)
            text(sheetName, x: margin, y: 11, width: contentWidth * 0.65,
                 font: .systemFont(ofSize: 18, weight: .bold), color: .white)
            text(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none),
                 x: margin, y: 33, width: contentWidth * 0.65,
                 font: .systemFont(ofSize: 9), color: UIColor.white.withAlphaComponent(0.85))
            let total = sheet.activeExpensesArray.reduce(0) { $0 + $1.amount }
            text(NSLocalizedString("pdf_total", comment: ""), x: margin, y: 12, width: contentWidth,
                 font: .systemFont(ofSize: 8, weight: .medium),
                 color: UIColor.white.withAlphaComponent(0.85), align: .right)
            text(money(total), x: margin, y: 24, width: contentWidth,
                 font: .systemFont(ofSize: 16, weight: .semibold), color: .white, align: .right)
            y = bannerH + 18

            // MARK: Saldi e rimborsi, affiancati

            let balances = sheet.balancesPerPerson()
            let transfers = sheet.suggestedTransfers()
            let colGap: CGFloat = 32
            let colW = (contentWidth - colGap) / 2
            let rightX = margin + colW + colGap
            let rowH: CGFloat = 15
            let rowFont = UIFont.systemFont(ofSize: 9)
            let rowBold = UIFont.systemFont(ofSize: 9, weight: .semibold)
            let top = y

            if !balances.isEmpty {
                sectionHeader(NSLocalizedString("Persone", comment: "people"), x: margin, width: colW)
                var ly = top + 20
                for person in sheet.personsArray {
                    let v = balances[person] ?? 0
                    let sign = v > 0.005 ? "+" : (v < -0.005 ? "−" : "")
                    let color = v > 0.005 ? positive : (v < -0.005 ? negative : muted)
                    text(person.name ?? "—", x: margin, y: ly, width: colW * 0.6, font: rowFont)
                    text(sign + money(abs(v)), x: margin, y: ly, width: colW, font: rowBold,
                         color: color, align: .right)
                    ly += rowH
                }
                y = max(y, ly)
            }
            if !transfers.isEmpty {
                let saved = y
                y = top
                sectionHeader(NSLocalizedString("settle_who_pays_whom", comment: ""), x: rightX, width: colW)
                var ry = top + 20
                for t in transfers {
                    text("\(t.from.name ?? "—")  →  \(t.to.name ?? "—")", x: rightX, y: ry,
                         width: colW * 0.7, font: rowFont)
                    text(money(t.amount), x: rightX, y: ry, width: colW, font: rowBold,
                         color: accent, align: .right)
                    ry += rowH
                }
                y = max(saved, ry)
            }
            y += 18

            // MARK: Spese

            let expenses = sheet.activeExpensesArray
            guard !expenses.isEmpty else { return }

            let dateW: CGFloat = 58, catW: CGFloat = 92, payerW: CGFloat = 96, amtW: CGFloat = 84
            let descW = contentWidth - dateW - catW - payerW - amtW
            let catX = margin + dateW, descX = catX + catW, payerX = descX + descW
            let pad: CGFloat = 6

            func tableHeader() {
                let f = UIFont.systemFont(ofSize: 7.5, weight: .semibold)
                text(NSLocalizedString("Data", comment: "date").uppercased(), x: margin + pad, y: y, width: dateW, font: f, color: muted)
                text(NSLocalizedString("category", comment: "").uppercased(), x: catX, y: y, width: catW, font: f, color: muted)
                text(NSLocalizedString("Descrizione", comment: "description").uppercased(), x: descX, y: y, width: descW, font: f, color: muted)
                text(NSLocalizedString("paid by", comment: "").uppercased(), x: payerX, y: y, width: payerW, font: f, color: muted)
                text(NSLocalizedString("amount_header", comment: "").uppercased(), x: margin, y: y,
                     width: contentWidth - pad, font: f, color: muted, align: .right)
                y += 12
                fill(CGRect(x: margin, y: y, width: contentWidth, height: 0.5), rule)
                y += 3
            }

            ensure(40)
            text("\(NSLocalizedString("Spese", comment: "expenses")) (\(expenses.count))".uppercased(),
                 x: margin, y: y, width: contentWidth, font: .systemFont(ofSize: 8, weight: .semibold), color: muted)
            y += 16
            tableHeader()

            let df = DateFormatter()
            df.dateFormat = "dd/MM/yy"
            let lineH: CGFloat = 14
            for (i, e) in expenses.enumerated() {
                ensure(lineH, onNewPage: tableHeader)
                if i % 2 == 1 {
                    fill(CGRect(x: margin, y: y, width: contentWidth, height: lineH), stripe)
                }
                let ty = y + (lineH - ceil(rowFont.lineHeight)) / 2
                let note = (e.note?.isEmpty == false ? e.note! : "—")
                    .replacingOccurrences(of: "\n", with: " ")
                text(df.string(from: e.date ?? Date()), x: margin + pad, y: ty, width: dateW - pad, font: rowFont, color: muted)
                text(ExpenseCategory.from(e.category).localizedName, x: catX, y: ty, width: catW - pad, font: rowFont)
                text(note, x: descX, y: ty, width: descW - pad * 2, font: rowFont)
                text(e.paidBy?.name ?? "—", x: payerX, y: ty, width: payerW - pad, font: rowFont)
                text(money(e.amount), x: margin, y: ty, width: contentWidth - pad, font: rowBold, align: .right)
                y += lineH
            }
            fill(CGRect(x: margin, y: y, width: contentWidth, height: 0.5), rule)
            y += 5
            text(money(total), x: margin, y: y, width: contentWidth - pad, font: rowBold, align: .right)
            text(NSLocalizedString("pdf_total", comment: ""), x: payerX, y: y, width: payerW, font: rowBold)
        }
    }
}
