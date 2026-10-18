// HikeHomeProvider reads shared hike/weather snapshots for next-hike and upcoming-hike widgets.
import SwiftUI
import WidgetKit

private let hikeWidgetGroup = "group.com.leongziqi.hikercircle.widgets"

struct HikeWidgetSnapshot: Decodable {
  let hikes: [HikeWidgetData]
}

struct HikeWidgetData: Decodable {
  let id: String
  let name: String
  let startPoint: String
  let distanceKm: Double
  let difficulty: String
  let departure: Double
  let returning: Double
  let expires: Double
  var gearDone: Int?
  var gearTotal: Int?
  var contactsReady: Bool?
  var sharingReady: Bool?
  var battery: Int?
  var weather: HikeWidgetWeather?
  var weatherStatus: String?
}

struct HikeWidgetWeather: Decodable {
  let updated: Double
  let covered: Bool
  var minTemp: Double?
  var maxTemp: Double?
  var rain: Double?
  let daylight: String
}

struct HikeHomeEntry: TimelineEntry {
  let date: Date
  let hike: HikeWidgetData?
  var hikes: [HikeWidgetData] = []
}

struct HikeHomeProvider: TimelineProvider {
  func placeholder(in context: Context) -> HikeHomeEntry { sample() }

  func getSnapshot(in context: Context, completion: @escaping (HikeHomeEntry) -> Void) {
    completion(context.isPreview ? sample() : entry(at: Date(), hikes: load()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<HikeHomeEntry>) -> Void) {
    let now = Date()
    let hikes = load()
    // Schedule boundaries update context/countdown without waiting for the
    // next regular entry; these are planned times, not live tracking status.
    var dates = (0...16).map { now.addingTimeInterval(Double($0) * 900) }
    dates += hikes.flatMap { hike in
      [hike.departure, hike.returning, hike.expires + 1].map { Date(timeIntervalSince1970: $0) }
    }
      .filter { $0 > now && $0 < now.addingTimeInterval(14400) }
    dates.sort()
    completion(Timeline(entries: dates.map { entry(at: $0, hikes: hikes) },
      policy: .after(now.addingTimeInterval(14400))))
  }

  private func load() -> [HikeWidgetData] {
    guard let json = UserDefaults(suiteName: hikeWidgetGroup)?.string(forKey: "hikeWidgetSnapshot"),
          let data = json.data(using: .utf8),
          let snapshot = try? JSONDecoder().decode(HikeWidgetSnapshot.self, from: data) else { return [] }
    return snapshot.hikes.sorted { $0.departure < $1.departure }
  }

  private func entry(at date: Date, hikes: [HikeWidgetData]) -> HikeHomeEntry {
    let visible = hikes.filter { $0.expires > date.timeIntervalSince1970 }
    return HikeHomeEntry(date: date, hike: visible.first, hikes: visible)
  }

  private func sample() -> HikeHomeEntry {
    let now = Date()
    let sample = HikeHomeEntry(date: now, hike: HikeWidgetData(id: "preview", name: "Penang Hill Heritage Trail",
      startPoint: "Heritage trailhead", distanceKm: 5.2, difficulty: "Moderate",
      departure: now.addingTimeInterval(7200).timeIntervalSince1970,
      returning: now.addingTimeInterval(19800).timeIntervalSince1970,
      expires: now.addingTimeInterval(20700).timeIntervalSince1970,
      gearDone: 18, gearTotal: 24, contactsReady: true, sharingReady: true, battery: 82,
      weather: HikeWidgetWeather(updated: now.timeIntervalSince1970, covered: true,
        minTemp: 24, maxTemp: 28, rain: 65, daylight: "Check daylight in app")))
    let names = ["Penang Hill Heritage Trail", "Forest Loop", "Riverside Trail", "Summit Trail"]
    let hikes = (0..<4).map { index in
      let departure = now.addingTimeInterval(7200 + Double(index) * 86400)
      return HikeWidgetData(id: "preview-\(index)", name: names[index], startPoint: "Trailhead", distanceKm: 5.2 + Double(index), difficulty: "Moderate", departure: departure.timeIntervalSince1970, returning: departure.addingTimeInterval(14400).timeIntervalSince1970, expires: departure.addingTimeInterval(15300).timeIntervalSince1970)
    }
    return HikeHomeEntry(date: now, hike: sample.hike, hikes: hikes)
  }
}

struct HikeHomeWidgetView: View {
  let entry: HikeHomeEntry
  let showsWeather: Bool
  @Environment(\.widgetFamily) private var family
  private var accent: Color { showsWeather ? .cyan : .green }

  var body: some View {
    VStack(alignment: .leading, spacing: showsWeather ? 4 : 5) {
      VStack(alignment: .leading, spacing: 2) {
        Label(showsWeather ? "HIKE WEATHER" : "NEXT HIKE",
          systemImage: showsWeather ? "cloud.sun.fill" : "figure.hiking")
          .font(.caption2.bold()).foregroundStyle(accent)
        if showsWeather, let hike = entry.hike {
          Text(weatherContext(hike))
            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            .lineLimit(1).minimumScaleFactor(0.8)
        }
      }
      if let hike = entry.hike {
        Text(hike.name).font(.headline).lineLimit(family == .systemSmall ? 2 : 1).minimumScaleFactor(0.85)
        if showsWeather { weather(hike) } else { briefing(hike) }
      } else {
        Spacer(minLength: 0)
        Text("Plan your next hike").font(.headline)
        Text(showsWeather ? "Schedule a hike in HikerCircle to see its forecast." : "Your next route and departure appear here.")
          .font(.caption).foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Text("Open HikerCircle →").font(.caption2.bold()).foregroundStyle(accent)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .hikerWidgetBackground { Color(.secondarySystemBackground) }
    .widgetURL(URL(string: showsWeather ? "hikercircle://hike/weather" : "hikercircle://hike/briefing"))
  }

  @ViewBuilder private func briefing(_ hike: HikeWidgetData) -> some View {
    let departure = Date(timeIntervalSince1970: hike.departure)
    if family != .systemSmall {
      Text(String(format: "%.1f km · %@", hike.distanceKm, hike.difficulty))
        .font(.caption).foregroundStyle(.secondary)
    }
    HStack(spacing: 4) {
      Image(systemName: "timer").font(.system(size: 14)).fixedSize()
      if departure > entry.date {
        if family == .systemSmall {
          Text(timerInterval: entry.date...departure, countsDown: true, showsHours: true)
            .monospacedDigit().layoutPriority(1)
            .minimumScaleFactor(0.65)
        } else {
          Text(departure, style: .relative).monospacedDigit().layoutPriority(1)
        }
        Text("to go").font(.system(size: family == .systemSmall ? 9 : 11, weight: .medium))
          .fixedSize()
      } else { Text("Departure time reached") }
    }.font(.subheadline.bold()).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.7)
    HStack {
      Text(departure, format: .dateTime.day().month(.abbreviated).hour().minute())
      if family != .systemSmall {
        Text("→")
        Text(Date(timeIntervalSince1970: hike.returning), format: .dateTime.day().month(.abbreviated).hour().minute())
      }
    }.font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
    Spacer(minLength: 0)
    if let done = hike.gearDone, let total = hike.gearTotal, total > 0 {
      Text("Gear checklist \(done)/\(total)").font(.caption2)
      ProgressView(value: min(1, max(0, Double(done) / Double(total)))).tint(accent)
    } else { Text("Tap to review preparation").font(.caption2).foregroundStyle(.secondary) }
  }

  private func weatherContext(_ hike: HikeWidgetData) -> String {
    let time = entry.date.timeIntervalSince1970
    if time < hike.departure { return "Upcoming hike" }
    if time < hike.returning { return "Scheduled hike window" }
    return "Past hike window"
  }

  @ViewBuilder private func weather(_ hike: HikeWidgetData) -> some View {
    if let forecast = hike.weather, forecast.covered {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          if let low = forecast.minTemp, let high = forecast.maxTemp {
            Text("\(Int(low.rounded()))–\(Int(high.rounded()))°").font(.title2.bold()).minimumScaleFactor(0.7)
          } else { Text("—").font(.title2.bold()) }
          Text("Temperature").font(.caption2).foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 2) {
          if let rain = forecast.rain { Text("\(Int(rain.rounded()))%").font(.title2.bold()).foregroundStyle(accent) }
          else { Text("—").font(.title2.bold()) }
          Text("Peak chance").font(.caption2).foregroundStyle(.secondary)
        }
      }.lineLimit(1).minimumScaleFactor(0.7)
      if family != .systemSmall {
        Text("Departure to return · \(forecast.daylight)").font(.caption2).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      HStack(spacing: 3) {
        Text(entry.date.timeIntervalSince1970 - forecast.updated >= 14400 ? "Outdated ·" : "Updated")
        Text(Date(timeIntervalSince1970: forecast.updated), style: .time)
        if family != .systemSmall { Text("· Open-Meteo") }
      }.font(.caption2).foregroundStyle(.secondary)
    } else {
      Spacer(minLength: 0)
      Text(hike.weatherStatus == "beyondRange" || hike.weatherStatus == "incomplete"
        ? "Forecast available closer to departure"
        : hike.weatherStatus == "unavailable" ? "Forecast unavailable" : "Open app to refresh forecast")
        .font(.subheadline.bold())
      Text(hike.weatherStatus == "beyondRange" ? "Forecasts cover up to 16 days ahead."
        : hike.weatherStatus == "unavailable" ? "Tap to retry in HikerCircle."
        : "Weather for your scheduled hiking window.").font(.caption2).foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
  }
}

struct NextHikeHomeWidget: Widget {
  let kind = "NextHikeHomeWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: HikeHomeProvider()) {
      HikeHomeWidgetView(entry: $0, showsWeather: false)
    }
    .configurationDisplayName("Next Hike")
    .description("Your next departure, route and gear checklist.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct HikeWeatherHomeWidget: Widget {
  let kind = "HikeWeatherHomeWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: HikeHomeProvider()) {
      HikeHomeWidgetView(entry: $0, showsWeather: true)
    }
    .configurationDisplayName("Hike Weather")
    .description("Temperature and peak rain chance for your planned hike.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}


struct UpcomingHikesHomeWidget: Widget {
  let kind = "UpcomingHikesHomeWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: HikeHomeProvider()) {
      UpcomingHikesWidgetView(entry: $0)
    }
    .configurationDisplayName("Upcoming Hikes")
    .description("Your next four hikes, with dates, departure times and distances.")
    .supportedFamilies([.systemLarge])
  }
}

struct UpcomingHikesWidgetView: View {
  let entry: HikeHomeEntry
  private var hikes: [HikeWidgetData] { entry.hikes.isEmpty ? entry.hike.map { [$0] } ?? [] : entry.hikes }
  private func link(_ hike: HikeWidgetData) -> URL {
    var url = URLComponents(string: "hikercircle://upcoming-hike/view")!
    url.queryItems = [URLQueryItem(name: "upcomingHikeId", value: hike.id)]
    return url.url!
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Label("UPCOMING HIKES", systemImage: "calendar").font(.caption.bold()).foregroundStyle(.green)
        Spacer()
        Text("\(hikes.count) planned").font(.caption2).foregroundStyle(.secondary)
      }
      if hikes.isEmpty {
        Spacer()
        Image(systemName: "figure.hiking").font(.largeTitle).foregroundStyle(.green)
        Text("Room for your next adventure").font(.headline)
        Text("Schedule hikes in HikerCircle to see them here.").font(.caption).foregroundStyle(.secondary)
        Spacer()
      } else {
        ForEach(Array(hikes.prefix(4).enumerated()), id: \.element.id) { index, hike in
          Link(destination: link(hike)) {
            HStack(spacing: 12) {
              VStack(spacing: 1) {
                Text(Date(timeIntervalSince1970: hike.departure), format: .dateTime.month(.abbreviated)).font(.system(size: 10, weight: .semibold))
                Text(Date(timeIntervalSince1970: hike.departure), format: .dateTime.day()).font(.title3.bold())
              }
              .frame(width: 42, height: 46).background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
              .foregroundStyle(.green)
              VStack(alignment: .leading, spacing: 4) {
                Text(hike.name).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.85)
                HStack(spacing: 5) {
                  Image(systemName: "timer")
                  Text(Date(timeIntervalSince1970: hike.departure), format: .dateTime.hour().minute())
                  Text(String(format: "· %.1f km", hike.distanceKm))
                }.font(.caption2).foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
              Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }
          }.buttonStyle(.plain)
          if index < min(hikes.count, 4) - 1 { Divider() }
        }
        Spacer(minLength: 0)
      }
      Text(hikes.count > 4 ? "+\(hikes.count - 4) more · Open your hiking plans →" : "Tap a hike to review preparation →")
        .font(.caption2).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .hikerWidgetBackground { Color(.secondarySystemBackground) }
    .widgetURL(URL(string: "hikercircle://hike/briefing"))
  }
}
