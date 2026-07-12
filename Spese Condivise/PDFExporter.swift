import UIKit

enum PDFExporter {

    static func generate(for sheet: SharedSheet) -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            let margin: CGFloat = 44
            let contentWidth = pageRect.width - margin * 2
            var y: CGFloat = 0

            func newPage() {
                ctx.beginPage()
                y = margin
            }

            func checkPageBreak(needed: CGFloat) {
                if y + needed > pageRect.height - margin {
                    newPage()
                }
            }

            // MARK: - Color helpers
            let accentColor = UIColor.systemBlue
            let separatorColor = UIColor.separator
            let secondaryColor = UIColor.secondaryLabel

            // MARK: - Draw helpers

            func drawText(_ text: String,
                          x: CGFloat, y: CGFloat, width: CGFloat,
                          font: UIFont,
                          color: UIColor = .label,
                          alignment: NSTextAlignment = .left) {
                let para = NSMutableParagraphStyle()
                para.alignment = alignment
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: para
                ]
                let rect = CGRect(x: x, y: y, width: width, height: font.lineHeight * 2)
                text.draw(in: rect, withAttributes: attrs)
            }

            func textHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
                let para = NSMutableParagraphStyle()
                para.lineBreakMode = .byWordWrapping
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: para]
                let size = (text as NSString).boundingRect(
                    with: CGSize(width: width, height: 9999),
                    options: .usesLineFragmentOrigin,
                    attributes: attrs,
                    context: nil
                )
                return ceil(size.height)
            }

            func drawSectionHeader(_ title: String) {
                checkPageBreak(needed: 36)
                let font = UIFont.systemFont(ofSize: 10, weight: .semibold)
                drawText(title.uppercased(), x: margin, y: y, width: contentWidth, font: font, color: secondaryColor)
                y += 18
                let sepRect = CGRect(x: margin, y: y, width: contentWidth, height: 0.5)
                separatorColor.setFill()
                UIRectFill(sepRect)
                y += 8
            }

            // MARK: - Header

            newPage()

            // Blue banner
            let bannerHeight: CGFloat = 72
            let bannerRect = CGRect(x: 0, y: 0, width: pageRect.width, height: bannerHeight)
            accentColor.setFill()
            UIRectFill(bannerRect)

            let titleFont = UIFont.systemFont(ofSize: 22, weight: .bold)
            let sheetName = sheet.name ?? NSLocalizedString("sheet", comment: "")
            drawText(sheetName, x: margin, y: 14, width: contentWidth - 120,
                     font: titleFont, color: .white)

            let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)
            let subtitleFont = UIFont.systemFont(ofSize: 11, weight: .regular)
            drawText(dateStr, x: margin, y: 44, width: contentWidth,
                     font: subtitleFont, color: UIColor.white.withAlphaComponent(0.8))

            // Totale spese in alto a destra nel banner
            let totalAmount = sheet.activeExpensesArray.reduce(0) { $0 + $1.amount }
            let currency = sheet.currencyCode ?? "EUR"
            let totalStr = AmountFormatter.format(totalAmount, currencySymbol: currencySymbol(for: currency))
            let totalFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
            drawText(totalStr,
                     x: margin, y: 22,
                     width: contentWidth, font: totalFont,
                     color: UIColor.white.withAlphaComponent(0.95),
                     alignment: .right)

            y = bannerHeight + 24

            // MARK: - Saldi

            let balances = sheet.balancesPerPerson()
            if !balances.isEmpty {
                drawSectionHeader(NSLocalizedString("Persone", comment: "people"))

                let persons = sheet.personsArray
                let rowH: CGFloat = 26
                for person in persons {
                    checkPageBreak(needed: rowH)
                    let value = balances[person] ?? 0
                    let name = person.name ?? "—"
                    let nameFont = UIFont.systemFont(ofSize: 13, weight: .regular)
                    drawText(name, x: margin, y: y, width: contentWidth * 0.6, font: nameFont)

                    let balStr = AmountFormatter.format(abs(value), currencySymbol: currencySymbol(for: currency))
                    let prefix = value > 0.005 ? "+" : (value < -0.005 ? "−" : "")
                    let balColor: UIColor = value > 0.005 ? .systemGreen : (value < -0.005 ? .systemRed : .secondaryLabel)
                    let balFont = UIFont.systemFont(ofSize: 13, weight: .medium)
                    drawText(prefix + balStr,
                             x: margin, y: y, width: contentWidth,
                             font: balFont, color: balColor, alignment: .right)
                    y += rowH
                }
                y += 16
            }

            // MARK: - Rimborsi

            let transfers = sheet.suggestedTransfers()
            if !transfers.isEmpty {
                drawSectionHeader(NSLocalizedString("settle_who_pays_whom", comment: ""))

                let rowH: CGFloat = 26
                for t in transfers {
                    checkPageBreak(needed: rowH)
                    let from = t.from.name ?? "—"
                    let to   = t.to.name   ?? "—"
                    let rowFont = UIFont.systemFont(ofSize: 13, weight: .regular)
                    drawText("\(from)  →  \(to)", x: margin, y: y, width: contentWidth * 0.65, font: rowFont)
                    let amtFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
                    drawText(AmountFormatter.format(t.amount, currencySymbol: currencySymbol(for: currency)),
                             x: margin, y: y, width: contentWidth,
                             font: amtFont, color: accentColor, alignment: .right)
                    y += rowH
                }
                y += 16
            }

            // MARK: - Spese

            let expenses = sheet.activeExpensesArray
            if !expenses.isEmpty {
                let countStr = "\(NSLocalizedString("Spese", comment: "expenses")) (\(expenses.count))"
                drawSectionHeader(countStr)

                // Column widths
                let dateW:  CGFloat = 56
                let catW:   CGFloat = 72
                let amtW:   CGFloat = 72
                let payerW: CGFloat = 70
                let descW   = contentWidth - dateW - catW - amtW - payerW

                // Column headers
                let colFont = UIFont.systemFont(ofSize: 9, weight: .semibold)
                drawText(NSLocalizedString("Data", comment: "date"),
                         x: margin, y: y, width: dateW, font: colFont, color: secondaryColor)
                drawText(NSLocalizedString("category", comment: ""),
                         x: margin + dateW, y: y, width: catW, font: colFont, color: secondaryColor)
                drawText(NSLocalizedString("Descrizione", comment: "description"),
                         x: margin + dateW + catW, y: y, width: descW, font: colFont, color: secondaryColor)
                drawText(NSLocalizedString("paid by", comment: ""),
                         x: margin + dateW + catW + descW, y: y, width: payerW, font: colFont, color: secondaryColor)
                drawText(NSLocalizedString("amount_header", comment: ""),
                         x: margin, y: y, width: contentWidth, font: colFont, color: secondaryColor, alignment: .right)
                y += 16

                let sep2Rect = CGRect(x: margin, y: y, width: contentWidth, height: 0.5)
                separatorColor.setFill()
                UIRectFill(sep2Rect)
                y += 8

                let df = DateFormatter()
                df.dateFormat = "dd/MM"
                let rowFont = UIFont.systemFont(ofSize: 11, weight: .regular)
                let amtFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
                let minRowH: CGFloat = 20

                for expense in expenses {
                    let descText = expense.note?.isEmpty == false ? (expense.note ?? "—") : "—"
                    let descH = max(minRowH, textHeight(descText, width: descW, font: rowFont))
                    checkPageBreak(needed: descH + 6)

                    let dateText = df.string(from: expense.date ?? Date())
                    drawText(dateText, x: margin, y: y, width: dateW, font: rowFont, color: secondaryColor)

                    let cat = ExpenseCategory.from(expense.category)
                    drawText(cat.localizedName, x: margin + dateW, y: y, width: catW, font: rowFont)

                    let para = NSMutableParagraphStyle()
                    para.lineBreakMode = .byWordWrapping
                    let descAttrs: [NSAttributedString.Key: Any] = [.font: rowFont]
                    let descRect = CGRect(x: margin + dateW + catW, y: y, width: descW, height: descH)
                    descText.draw(in: descRect, withAttributes: descAttrs)

                    drawText(expense.paidBy?.name ?? "—",
                             x: margin + dateW + catW + descW, y: y, width: payerW, font: rowFont)

                    drawText(AmountFormatter.format(expense.amount, currencySymbol: currencySymbol(for: currency)),
                             x: margin, y: y, width: contentWidth,
                             font: amtFont, alignment: .right)

                    y += descH + 6
                }
            }

            // MARK: - Footer

            let footerFont = UIFont.systemFont(ofSize: 9, weight: .regular)
            let footerY = pageRect.height - 24
            drawText("Spese Condivise", x: margin, y: footerY, width: contentWidth,
                     font: footerFont, color: secondaryColor, alignment: .center)
        }

        let fileName = (sheet.name ?? "spese")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(fileName).pdf")
        try? data.write(to: url)
        return url
    }

    private static func currencySymbol(for code: String) -> String {
        AmountFormatter.symbol(for: code)
    }
}
