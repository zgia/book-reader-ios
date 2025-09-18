import Foundation

struct WordCountFormatter {
    static func string(from count: Int, locale: Locale = .current) -> String {
        if #available(iOS 16, *) {
            let formatted = count.formatted(
                .number
                    .notation(.compactName)  // 自动 K/M/B 或 万/亿
                    .locale(locale)
                    .precision(.fractionLength(0...1))  // 保留 0~1 位小数
            )
            return String(
                format: String(localized: "wordcount.format"),
                formatted
            )
        } else {
            return fallbackFormat(count, locale: locale)
        }
    }

    private static func fallbackFormat(_ count: Int, locale: Locale) -> String {
        let lang = locale.language.languageCode?.identifier ?? "en"

        let nf: NumberFormatter = {
            let f = NumberFormatter()
            f.locale = locale
            f.numberStyle = .decimal
            f.maximumFractionDigits = 1
            f.minimumFractionDigits = 0
            f.usesGroupingSeparator = false
            return f
        }()

        func fmt(_ value: Double) -> String {
            return nf.string(from: NSNumber(value: value))
                ?? String(format: "%.1f", value)
        }

        // 中文：万 / 亿
        if lang.starts(with: "zh") {
            if count >= 100_000_000 {
                let v = Double(count) / 100_000_000.0
                return String(
                    format: String(localized: "wordcount.format_yi"),
                    fmt(v)
                )
            } else if count >= 10_000 {
                let v = Double(count) / 10_000.0
                return String(
                    format: String(localized: "wordcount.format_wan"),
                    fmt(v)
                )
            } else {
                return String(
                    format: String(localized: "wordcount.plain_zh"),
                    count
                )
            }
        }

        // 其他语言：K / M / B
        if count >= 1_000_000_000 {
            let v = Double(count) / 1_000_000_000.0
            return String(
                format: String(localized: "wordcount.format_billion"),
                fmt(v)
            )
        } else if count >= 1_000_000 {
            let v = Double(count) / 1_000_000.0
            return String(
                format: String(localized: "wordcount.format_million"),
                fmt(v)
            )
        } else if count >= 1_000 {
            let v = Double(count) / 1_000.0
            return String(
                format: String(localized: "wordcount.format_thousand"),
                fmt(v)
            )
        } else {
            return String(
                format: String(localized: "wordcount.plain_en"),
                count
            )
        }
    }
}
