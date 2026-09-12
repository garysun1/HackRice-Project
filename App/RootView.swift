import SwiftUI

enum AppTab: String {
    case timeline, trends, briefing, connections
}

struct RootView: View {
    @State private var selection: AppTab = {
        // `-openTab briefing` jumps straight to a tab (screenshot loop + demo staging).
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-openTab"), index + 1 < args.count,
           let tab = AppTab(rawValue: args[index + 1]) {
            return tab
        }
        return .timeline
    }()

    var body: some View {
        TabView(selection: $selection) {
            TimelineView()
                .tabItem { Label("Timeline", systemImage: "list.bullet.rectangle.portrait") }
                .tag(AppTab.timeline)
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.trends)
            BriefingView()
                .tabItem { Label("Briefing", systemImage: "doc.text.magnifyingglass") }
                .tag(AppTab.briefing)
            ConnectionsView()
                .tabItem { Label("Connections", systemImage: "link") }
                .tag(AppTab.connections)
        }
    }
}

struct PlaceholderScreen: View {
    let title: String
    let note: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.brandTeal)
                Text(note)
                    .font(.rounded(.callout))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle(title)
            .background(Color.appBackground)
        }
    }
}

#Preview {
    RootView()
}
