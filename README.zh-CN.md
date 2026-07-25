# brarchive-flutter

[![Build](https://github.com/wisebreeze/brarchive-flutter/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/wisebreeze/brarchive-flutter/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/wisebreeze/brarchive-flutter?include_prereleases)](https://github.com/wisebreeze/brarchive-flutter/releases)
[![License](https://img.shields.io/github/license/wisebreeze/brarchive-flutter?color=blue)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-stable-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows-lightgrey)](#支持平台)

[English](README.md) | [简体中文](README.zh-CN.md)

一个跨平台图形界面工具，用于在 Minecraft 基岩版资源/行为包（`.zip` / `.mcpack`）与基岩引擎使用的 `__brarchive` 格式之间相互转换。基于 Flutter 与 Material 3 构建，是 [brarchive-go](https://github.com/wisebreeze/brarchive-go) 命令行工具的桌面端配套版本。

## 简介

基岩版的附加包以 `.zip` 或 `.mcpack` 压缩包形式分发。引擎内部可以读取一种名为 `__brarchive` 的紧凑二进制容器，它将大量零散的 JSON/UI 文件打包成单个文件，并使用固定大小的索引表。本工具在不依赖命令行的前提下完成两个方向的转换：

- **打包（Pack）** - 解压压缩包，扫描目标文件（`.json`、`.json5`、`.ui`），将其序列化为 `__brarchive/*.brarchive`，删除原始文件后重新打包。
- **解包（Unpack）** - 解压压缩包，定位所有 `__brarchive/*.brarchive`，还原原始文件，移除 `__brarchive` 文件夹后重新打包。

该二进制格式采用小端序，由 16 字节头部（魔数、条目数、版本号）、固定大小的描述符表（每个条目 247 字节名称槽 + 偏移量 + 长度）和连续的内容区组成，与 `brarchive-go` 的输出完全兼容。

## 功能特性

- Material 3 设计语言，动态取色与表现力组件
- 浅色、深色、跟随系统三种主题模式
- 英文与简体中文，支持"跟随系统"语言选项
- 各平台原生文件/目录选择器，不依赖第三方选择器插件
- 转换过程中带时间戳的实时控制台输出
- 输出目录默认为系统下载文件夹
- 通过 `shared_preferences` 持久化用户偏好设置

## 支持平台

| 平台 | 状态 |
|------|------|
| Android | 稳定 |
| Windows | 稳定 |

## 快速开始

### 环境要求

- Flutter 3.27 或更高版本（stable 通道）
- Android SDK 35 及以上（用于 Android 构建）
- Visual Studio 2022 并勾选"使用 C++ 的桌面开发"工作负载（用于 Windows 构建）

### 从源码构建

```bash
git clone https://github.com/wisebreeze/brarchive-flutter.git
cd brarchive-flutter
flutter pub get

# Android
flutter build apk --release

# Windows
flutter build windows --release
```

每个版本的预编译产物可在 [发布页面](https://github.com/wisebreeze/brarchive-flutter/releases) 下载。

### 下载

从 [GitHub Releases](https://github.com/wisebreeze/brarchive-flutter/releases) 下载最新的 APK 或 Windows 压缩包。`main` 分支上每次成功的构建运行也会附带相应产物。

## 使用方法

1. 启动应用。
2. 在"输入文件"一行，点击右侧的选择按钮，选中一个 `.zip` 或 `.mcpack` 文件。
3. 在"输出目录"一行，确认或修改目标路径（默认为系统下载目录）。
4. 点击"打包"将普通附加包转换为 `__brarchive` 格式，或点击"解包"执行逆向操作。
5. 在控制台面板查看处理进度，输出压缩包将写入所选目录。

点击右上角的更多菜单可随时切换语言或主题，选择会被记忆并在下次启动时恢复。

## 工作原理

### 打包

1. 将输入压缩包读入内存并解压。
2. 转换器遍历目录树，跳过 `textures`、`materials`、`texts`、`sounds` 目录，同时递归进入 `subpacks`。
3. 在每个符合条件的文件夹中，收集扩展名为 `.json`、`.json5`、`.ui` 的文件（排除 `ui/_global_variables.json`）。
4. 将这些文件序列化为单个 `.brarchive` 二进制，放入新建的 `__brarchive/` 子目录，并删除原始文件。
5. 清理空目录后重新打包。

### 解包

1. 将输入压缩包读入内存并解压。
2. 定位所有 `__brarchive/*.brarchive` 文件并反序列化。
3. 将原始文件写回其父目录。
4. 移除 `__brarchive` 文件夹后重新打包。

### 二进制格式

```
偏移   长度  字段
0      8     魔数（0x267052A0B125277D，小端序）
8      4     条目数
12     4     版本号（当前为 1）

每个条目（重复）：
0      1     名称长度（n）
1      247   名称（UTF-8，零填充）
248    4     内容偏移（相对于内容区起始）
252    4     内容长度

内容区：
按描述符顺序拼接的文件内容。
```

## 项目结构

```
lib/
  core/
    brarchive/        二进制编解码与 zip/mcpack 转换器
    file_picker/      基于 method channel 的原生文件选择器
    i18n/             基于 JSON 的本地化
    settings/         持久化偏好设置
    theme/            Material 3 主题定义
  ui/
    screens/          主界面
  app_state.dart      根状态（i18n 与主题）
  main.dart           入口
assets/
  i18n/               en.json, zh.json
```

## 开发

```bash
# 运行单元测试
flutter test

# 静态分析
flutter analyze

# 调试模式运行
flutter run
```

## 相关项目

- [brarchive-go](https://github.com/wisebreeze/brarchive-go) - Go 语言版本的参考命令行实现。

## 许可证

本项目基于 Apache License, Version 2.0 许可证，详见 [LICENSE](LICENSE) 文件。
