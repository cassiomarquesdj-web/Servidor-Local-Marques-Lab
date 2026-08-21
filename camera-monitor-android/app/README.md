# Android App Scaffold

## Target

Flutter Android tablet application. Landscape-first operation.

## Intended structure

```text
app/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── theme/
│   │   ├── networking/
│   │   └── diagnostics/
│   ├── domain/
│   │   ├── camera.dart
│   │   ├── camera_state.dart
│   │   ├── camera_command.dart
│   │   └── camera_capabilities.dart
│   ├── application/
│   │   ├── camera_session_controller.dart
│   │   └── camera_providers.dart
│   ├── infrastructure/
│   │   ├── protocols/
│   │   │   ├── gopro/
│   │   │   └── iphone/
│   │   └── preview/
│   └── presentation/
│       ├── screens/
│       │   ├── monitor_screen.dart
│       │   ├── single_camera_screen.dart
│       │   └── settings_screen.dart
│       └── widgets/
│           ├── camera_tile.dart
│           ├── camera_status_badge.dart
│           ├── recording_controls.dart
│           ├── preview_surface.dart
│           └── camera_strip.dart
├── test/
├── integration_test/
└── pubspec.yaml
```

## Design tokens

Centralize all visual constants under `core/theme/`.

Do not hardcode colors or spacing inside individual camera widgets.

## First implementation slice

Build the UI with a deterministic fake camera backend before integrating hardware. The fake backend must support:

- four cameras;
- state transitions;
- fake preview placeholders;
- command acknowledgements;
- offline/reconnect simulation.

This allows UX testing without pretending that real camera protocols are already available.

## Acceptance

The first compilable iteration must present the complete modern UI and pass widget tests for:

- Quad View;
- Single View;
- REC pending/confirmed;
- STOP pending/confirmed;
- offline state;
- reconnect action.
