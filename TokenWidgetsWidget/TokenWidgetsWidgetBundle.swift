import WidgetKit
import SwiftUI

struct TokenWidgetsWidget: Widget {
    let kind = "TokenWidgetsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TokenWidgetsWidgetView(snapshot: entry.snapshot)
                .padding(9)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Token Usage")
        .description("Shows Claude and ChatGPT/Codex usage.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct TokenWidgetsWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenWidgetsWidget()
    }
}
