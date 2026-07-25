# brarchive-flutter

[![Build](https://github.com/wisebreeze/brarchive-flutter/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/wisebreeze/brarchive-flutter/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/wisebreeze/brarchive-flutter?include_prereleases)](https://github.com/wisebreeze/brarchive-flutter/releases)
[![License](https://img.shields.io/github/license/wisebreeze/brarchive-flutter?color=blue)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-stable-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)](#supported-platforms)

[English](README.md) | [简体中文](README.zh-CN.md)

A cross-platform GUI tool for converting between Minecraft Bedrock resource/behavior packs (`.zip` / `.mcpack`) and the `__brarchive` format used by the Bedrock engine. Built with Flutter and Material 3, it is the desktop companion to the [brarchive-go](https://github.com/wisebreeze/brarchive-go) CLI.

## Overview

Bedrock Edition packs ship as `.zip` or `.mcpack` archives. Internally, the engine can consume a compact binary container called `__brarchive` that bundles many small JSON/UI files into a single file with a fixed-size index. This tool performs both directions of that conversion without requiring a command line:

- **Pack** - extracts an archive, scans for target files (`.json`, `.json5`, `.ui`), serializes them into `__brarchive/*.brarchive`, removes the originals, and re-zips the result.
- **Unpack** - extracts an archive, locates every `__brarchive/*.brarchive`, restores the original files, removes the `__brarchive` folder, and re-zips the result.

The binary format is little-endian and consists of a 16-byte header (magic, entry count, version), a fixed-size descriptor table (247-byte name slot + offset + length per entry), and a contiguous content section. It is fully compatible with the output of `brarchive-go`.

## Features

- Material 3 design with dynamic color and expressive components
- Light, dark, and system theme modes
- English and Simplified Chinese, with a "follow system" option
- Native file and folder pickers on each platform (no third-party picker dependency)
- Live console output with timestamps during conversion
- Output directory defaults to the system Downloads folder
- Persistent user preferences via `shared_preferences`

## Supported Platforms

| Platform | Status | Artifact |
|----------|--------|----------|
| Android  | Stable | APK |
| iOS      | Unsigned (sideload required) | Runner.app |
| Windows  | Stable | ZIP |
| macOS    | Stable | ZIP |
| Linux    | Stable | tar.gz |

## Getting Started

### Prerequisites

- Flutter 3.27 or newer (stable channel)
- Android SDK 35+ for Android builds
- Visual Studio 2022 with the "Desktop development with C++" workload for Windows builds

### Build from Source

```bash
git clone https://github.com/wisebreeze/brarchive-flutter.git
cd brarchive-flutter
flutter pub get

# Android
flutter build apk --release

# Windows
flutter build windows --release
```

Pre-built binaries for every release are available on the [releases page](https://github.com/wisebreeze/brarchive-flutter/releases).

### Download

Download the latest APK or Windows archive from [GitHub Releases](https://github.com/wisebreeze/brarchive-flutter/releases). Artifacts are also attached to each successful workflow run on the `main` branch.

## Usage

1. Launch the app.
2. In the **Input file** row, tap the browse button and select a `.zip` or `.mcpack` file.
3. In the **Output directory** row, confirm or change the destination (defaults to your Downloads folder).
4. Click **Pack** to convert a normal pack into the `__brarchive` format, or **Unpack** to reverse it.
5. Watch the console panel for progress. The output archive is written to the chosen directory.

Use the overflow menu in the top-right corner to switch language or theme at any time. Selections are remembered across launches.

## How It Works

### Pack

1. The input archive is extracted in memory.
2. The converter walks the tree, skipping `textures`, `materials`, `texts`, and `sounds` directories, while descending into `subpacks`.
3. In each qualifying folder, files with `.json`, `.json5`, or `.ui` extensions are collected (excluding `ui/_global_variables.json`).
4. Those files are serialized into a single `.brarchive` blob placed under a new `__brarchive/` subfolder, and the originals are deleted.
5. Empty directories are pruned and the tree is re-zipped.

### Unpack

1. The input archive is extracted in memory.
2. Every `__brarchive/*.brarchive` file is located and deserialized.
3. The original files are written back to their parent directories.
4. The `__brarchive` folder is removed and the tree is re-zipped.

### Binary Format

```
Offset  Size  Field
0       8     Magic (0x267052A0B125277D, little-endian)
8       4     Entry count
12      4     Version (currently 1)

Per entry (repeated):
0       1     Name length (n)
1       247   Name (UTF-8, zero-padded)
248     4     Content offset (relative to content section)
252     4     Content length

Content section:
Concatenated file contents in descriptor order.
```

## Project Structure

```
lib/
  core/
    brarchive/        Binary codec and zip/mcpack converter
    file_picker/      Native method-channel file picker
    i18n/             JSON-backed localization
    settings/         Persisted preferences
    theme/            Material 3 theme definitions
  ui/
    screens/          Home screen
  app_state.dart      Root state (i18n + theme)
  main.dart           Entry point
assets/
  i18n/               en.json, zh.json
```

## Development

```bash
# Run unit tests
flutter test

# Static analysis
flutter analyze

# Run in debug mode
flutter run
```

## Related Projects

- [brarchive-go](https://github.com/wisebreeze/brarchive-go) - The reference CLI implementation in Go.

## License

This project is licensed under the Apache License, Version 2.0 - see the [LICENSE](LICENSE) file for details.
