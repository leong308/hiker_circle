# Weather on route preview maps

## What is implemented

Normal route previews have a cloud button at the top left. Choose **Rain**, **Wind speed**, **Temperature**, or **Off**. The overlay covers a fixed **50 km radius** around the trail coordinate. It follows geographic coordinates when panning, zooming and tilting, without fetching more weather for the new camera view. A compact legend, opacity slider, load time and manual refresh button appear above the scale bar. Default opacity is 85% (adjustable up to 100%). Rain pixels receive a 3× alpha boost; wind and temperature receive 2×. Colors representing weather values stay intact, and fully transparent pixels remain transparent. This is labeled as enhanced visibility. Weather sits below map labels and route annotations, preserving the blue route.

Weather is off initially. FPV never installs a weather tile source; its right column instead shows **Rain · date/time**, using the trail's cached hourly forecast at simulated arrival (departure plus estimated hiking elapsed time). Departure follows the day/time selected in Conditions and Safety, defaulting to the start of the FPV preview when no time is selected. Playback speed changes how quickly the preview runs, not the hiking ETA. The FPV display samples an interpolated hourly probability trend every **10 simulated hiking minutes**, labeled **Rain est.** The label shows the sample time; tapping the row explains the estimate. These are not native 10-minute forecasts or probabilities for a 10-minute rainfall window. Open-Meteo also interpolates finer-interval data for Malaysia. No extra API calls are made. Missing adjacent hours are not bridged and no values are extrapolated beyond coverage. Conditions-and-Safety continues to use the original hourly data. This uses the trail's regional forecast, not separate API samples at every checkpoint. Missing, invalid, future-dated or at-least-four-hour-old forecasts display **Unavailable**, not 0%. The daily peak is not substituted for a missing hour.

The colored layers show regional weather conditions. They are not trail-resolution measurements. Zooming out reveals more regional context. This implementation does not animate wind streamlines or supply a forecast timeline; the free Maps 1.0 tiles do not provide the wind-vector field needed for that animation. Rain tiles indicate precipitation, while the FPV percentage is precipitation probability.

## Provider choice and free allowance

Checked 14 September 2026:

| Provider | Published free allowance | Suitability |
| --- | --- | --- |
| OpenWeather | 1,000,000 calls/month; 60/minute | Weather Maps 1.0 includes worldwide precipitation, wind speed and temperature layers. API key required. Selected for normal maps. |
| Open-Meteo | 300,000 calls/month; 10,000/day | Free access is noncommercial. Already supplies the app's cached point forecasts; retained for FPV probability. |
| RainViewer | No firm monthly allocation stated on its API page | Primarily personal/educational use, past radar only in its current Maps specification, maximum tile zoom 7. Does not provide a matching wind/temperature map. |

Sources: [OpenWeather detailed pricing](https://openweathermap.org/full-price), [Maps 1.0 documentation](https://docs.openweather.co.uk/api/weathermaps), [provider palette](https://docs.openweather.co.uk/map_legend), [Open-Meteo pricing](https://open-meteo.com/en/pricing), [RainViewer terms](https://www.rainviewer.com/api.html), [RainViewer Maps API](https://www.rainviewer.com/api/weather-maps-api.html).

OpenWeather's free plan allows commercial use with visible attribution. The app includes a visible OpenWeather credit/link. Its free weather maps update approximately every three hours; no live observation timestamp is invented. The Open-Meteo free-access restriction still applies to the existing forecast integration if the app becomes commercial.

## Enable the overlay

1. Create a free OpenWeather account and obtain a key from [API keys](https://home.openweathermap.org/api_keys). Use the Free plan with Weather Maps 1.0; One Call and Maps 2.0 are unnecessary for this feature.
2. Add `OPENWEATHER_API_KEY=your_key` to the existing local `.env`. `.env.example` contains the empty setting. Alternatively supply `--dart-define=OPENWEATHER_API_KEY=your_key` when building; that takes precedence.
3. Fully restart/rebuild the app after changing configuration.
4. Open a trail's normal route preview, tap the cloud icon, and choose a layer. Zoom out to see weather differences across the region.

The key follows the app's existing build/environment configuration method. It is not written to trail documents. A key bundled in a mobile app is extractable; account-wide throttling or keeping it server-side would require a backend tile proxy for a larger public deployment.

## Requests and failures

The app fetches a fixed set of 256-pixel tiles at zoom 8 from:

```text
https://tile.openweathermap.org/map/{layer}/{z}/{x}/{y}.png?appid={key}
```

Only one weather layer is active. Turning it off removes both the style layer and its source. Selecting another layer replaces them; changing the base-map style reinstalls the selection on the new map. Async style operations are serialized to avoid duplicate sources and outdated selections. Weather errors turn the overlay off and show a retry message; base-map errors are handled separately. Missing configuration displays an availability message without requests.

`WeatherAreaService` composites the tiles and clips them to a geodesic 50 km circle. At Malaysian latitudes the area requires at most four tiles per selected layer. Mapbox receives the resulting PNG as an `ImageSource` with geographic corners; **it receives no weather tile URL**, so zooming and panning cannot trigger weather API calls. Areas beyond the circle have no weather overlay. Base-map imagery still uses Mapbox normally.

An in-memory cache keeps up to 16 area/layer images for three hours and shares in-flight downloads. Reopening the same area/layer within that period or changing base style reuses its image. Cache expiry is checked on the next load/selection, not camera motion. The refresh button explicitly downloads the area again. Restarting the app clears this memory cache. Only the selected weather layer is fetched, rather than loading all three automatically.

Each tile request consumes allowance; one map opening is not one API call. The 60/minute account limit remains relevant across simultaneous users. This controls request volume but does not enforce an account-wide quota. FPV adds no API calls: it reuses Firebase weather already delivered with the trail.

## Related code

| File | Responsibility |
| --- | --- |
| `lib/core/services/weather_map_service.dart` | Key lookup, Maps 1.0 URLs, layer definitions, arrival-hour rain selection and freshness validation. |
| `lib/core/services/weather_area_service.dart` | Fixed extent/zoom, circular clipping, visibility boost, PNG compositing, shared downloads and area cache. |
| `lib/core/widgets/weather_map_overlay.dart` | Normal map selector, Mapbox source/layer lifecycle, opacity, palette, attribution and failures. |
| `lib/core/widgets/route_preview_map.dart` | Connects normal-map overlay and map error events; adds the FPV rain row. |
| `functions/trail_weather.js` | Existing Open-Meteo forecast fetching and shared Firebase cache. |
| `lib/trail/Model/trail_models.dart` | Existing `TrailWeather.forecastData` and legacy hourly forecast storage. |
| `.env.example` | Optional OpenWeather configuration. |
| `test/core/weather_map_service_test.dart` | Hour selection, missing/stale data, legacy compatibility and API template checks. |
| `test/core/weather_area_service_test.dart` | Area bounds, request counts/cache reuse, opacity boost, clipping and failed-download handling. |
| `test/core/weather_map_overlay_test.dart` | Selector, small-map layout, missing-key and source-error behavior. |

No route geometry or checkpoint storage changes are needed for weather.

## Validation

Twelve targeted unit/widget tests pass, including area caching, clipping, increased alpha, missing-data handling and UI controls; static analysis is clean. A live Penang download passed for rain, wind and temperature: four HTTP calls per layer, zero extra calls on cached reload. Generated PNGs were saved under `output/weather-verification/`. Native iOS/Android terrain/route stacking and visual playback still need a rebuilt app check.
