// ManualSOSBundle registers hike, weather, SOS, and Live Activity widgets.
import WidgetKit
import SwiftUI

@main
struct ManualSOSBundle: WidgetBundle {
  var body: some Widget {
    NextHikeHomeWidget()
    HikeWeatherHomeWidget()
    UpcomingHikesHomeWidget()
    ManualSOS()
    ManualSOSActions()
    ManualHikeLiveActivity()
  }
}
