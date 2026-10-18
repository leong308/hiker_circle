// ManualSOS opens the app manual SOS flow from its WidgetKit timeline.
import WidgetKit
import SwiftUI

struct ManualSOSEntry: TimelineEntry {
  let date: Date
}

struct ManualSOSProvider: TimelineProvider {
  func placeholder(in context: Context) -> ManualSOSEntry {
    ManualSOSEntry(date: Date())
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (ManualSOSEntry) -> Void
  ) {
    completion(ManualSOSEntry(date: Date()))
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<ManualSOSEntry>) -> Void
  ) {
    completion(Timeline(entries: [ManualSOSEntry(date: Date())], policy: .never))
  }
}

struct ManualSOSEntryView: View {
  private let sosUrl = URL(string: "hikercircle://sos/instant?source=ios_widget")!

  let entry: ManualSOSEntry

  var body: some View {
    Link(destination: sosUrl) {
      VStack(alignment: .leading, spacing: 4) {
        Text("HikerCircle")
          .font(.caption2.bold())
          .foregroundStyle(.white)

        Spacer(minLength: 0)

        VStack(spacing: 4) {
          Text("SOS")
            .font(.system(size: 28, weight: .black, design: .rounded))
            .foregroundStyle(.white)

          Text("Instant")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 12))
      }
      .padding(4)
    }
    .hikerWidgetBackground {
      LinearGradient(
        colors: [
          Color(red: 0.37, green: 0.04, blue: 0.04),
          Color(red: 0.86, green: 0.15, blue: 0.15),
          Color(red: 1.00, green: 0.23, blue: 0.19)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
  }
}

struct ManualSOS: Widget {
  let kind = "ManualSOS"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ManualSOSProvider()) { entry in
      ManualSOSEntryView(entry: entry)
    }
    .configurationDisplayName("HikerCircle SOS")
    .description("Tap to trigger Instant SOS.")
    .supportedFamilies([.systemSmall])
  }
}
