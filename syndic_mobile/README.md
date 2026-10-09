# Syndic Mobile

Flutter dashboard for the Smart Syndic AI project. It provides Firebase sign-in, residence selection, resident and ticket management, history, analytics, and push notifications.

See the [project README](../README.md) for backend setup and the complete data/privacy notes.

## Setup

1. Install Flutter and configure Firebase for your own application. Add platform Firebase files locally; they are excluded from Git.
2. From this directory, run `flutter pub get`.
3. Start the FastAPI service and run the app with its reachable API address:

```bash
flutter run --dart-define=API_BASE_URL=https://your-api-host
```

The API base URL can also be set in the Flutter build using the `API_BASE_URL` compile-time define. The project’s local data and generated build output are not included in the repository.
