# Courvite ⚡

A privacy-friendly running tracker for Android. It's like Strava, but everything
stays on your phone. There's no account, no ads, no analytics and no cloud.

## Features

- **Live tracking** with GPS: distance, time, average and current pace (min/km),
  and per-km splits. It keeps recording with the screen off, through a foreground
  service, and you can pause and resume.
- **Run summary**: route map, splits, fastest km, elevation gain and loss.
- **Best efforts and medals**: the fastest continuous 1K, 2K, 5K and 10K of
  each run. The three fastest ever for each distance get gold, silver and bronze.
- **Activity**: your run history with route thumbnails, a daily chart for this
  week, and a monthly calendar where the colour intensity shows the distance run.
- **Backup and restore**: export everything to a `.courvite` file and import it
  on another phone.

## Privacy

- Runs are stored in a local SQLite database only.
- Location comes from the platform `LocationManager` (raw GNSS), not Google Play
  Services.
- The only network use is downloading map tiles from OpenStreetMap, which does
  reveal the area being viewed to the tile server.
- Fonts are bundled, so nothing is fetched from Google Fonts.

## Backup format

A `.courvite` file is gzip-compressed JSON (`gunzip -c backup.courvite` to read
it). It contains every run and its GPS points. Derived stats are recomputed on
import. See `lib/data/backup.dart` for the schema.

## Development

Requires Flutter (stable) and targets **Android 15+** (minSdk 35).

```sh
flutter pub get
flutter test
flutter run
```

Release builds are signed with the key described in `android/key.properties`
(not in the repository):

```properties
storePassword=…
keyPassword=…
keyAlias=courvite
storeFile=/path/to/courvite-release.jks
```

Without that file, `flutter build apk --release` signs with the debug key.

Code layout:

| Path | Contents |
| --- | --- |
| `lib/tracking/` | GPS recording, and stats (distance, splits, best efforts, elevation) |
| `lib/data/` | SQLite storage, weekly/monthly aggregation, backups |
| `lib/ui/` | Screens and widgets |
| `test/` | Unit tests for the stats, aggregation and backup logic |

Map data © OpenStreetMap contributors. Barlow fonts are under the SIL Open Font
License (`assets/fonts/OFL.txt`).

## License

Courvite is released under the [MIT License](LICENSE).
