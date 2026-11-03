# hakwat

An offline workout logger for Android, built with Flutter. Data stays on the device in SQLite and can be exported to a JSON file.

#Features:
- - Gym specific workouts and exercises
  - Full export capability
  - Rest timers
    

## Commands

```sh
flutter run                              # debug build on a connected device
flutter test                             # all tests
flutter analyze

dart run build_runner build              # after changing lib/data/tables.dart or database.dart
dart run tool/generate_mock_data.dart    # rewrites assets/dev/mock_data.json
```

## Trying it with mock data

Debug builds have a **Dev tools** section in the drawer:

- **Load mock data** replaces everything in the app with `assets/dev/mock_data.json`.
- **Clear all data** returns the app to how a fresh install looks.

## Layout

| Path | Contents |
|---|---|
| `lib/app` | Theme, router, tab shell, Riverpod providers |
| `lib/data` | Drift tables, repositories, statistics, JSON export and restore |
| `lib/features` | One folder per area of the app |
| `lib/services` | Rest alert notifications |
| `docs/mockup` | The screenshots the UI is based on |

## Before trusting it with real data

A database structure change currently wipes all data, because migrations aren't written yet. Keep real workouts elsewhere until they are.
