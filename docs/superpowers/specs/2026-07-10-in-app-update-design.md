# 应用内更新设计文档

> **目标**：让 慧眼 SmartEye 在 Wi-Fi 环境下每周自动检查一次 Gitee/GitHub Release，发现新版本后语音询问用户，用户确认后下载 APK 并调起系统安装器。

## 方案概述

- **检查频率**：每周最多一次，仅在 Wi-Fi 已连接时触发。
- **更新源**：Gitee Releases 为主，GitHub Releases 为兜底。
- **交互方式**：发现更新后语音播报“发现新版本 Vx.x.x，是否下载？上滑确认，下滑取消”；用户确认后下载；下载完成自动打开系统安装器。
- **失败处理**：任何网络/下载/安装异常都必须语音反馈，不能静默失败。

## 仓库信息

| 平台 | 仓库 | API 地址 |
|------|------|----------|
| Gitee | `free-style_2_0/smart_eye` | `https://gitee.com/api/v5/repos/free-style_2_0/smart_eye/releases/latest` |
| GitHub | `pomelo56/smart_eye` | `https://api.github.com/repos/pomelo56/smart_eye/releases/latest` |

APK 资源文件名固定为 `app-release.apk`，随 Release 上传。

## 组件设计

### 1. UpdateService

- `checkForUpdate()`：
  - 判断 Wi-Fi 是否连接、距上次检查是否超过 7 天。
  - 请求 Gitee API，失败则 fallback 到 GitHub API。
  - 解析最新 Release 的 `tag_name` 与 `versionCode`。
  - 比较远端 `versionCode` 与本地 `versionCode`（来自 `package_info_plus`）。
  - 返回 `UpdateInfo?`，包含新版本号、下载 URL、release notes。
- `markChecked()`：记录本次检查时间到 `SharedPreferences`。

### 2. DownloadService

- 使用 `dio` 下载 APK。
- 保存到应用私有外部缓存目录（`getExternalCacheDirectories()`），避免申请存储权限。
- 通过 `ValueNotifier` 或 Stream 上报进度；只播报“开始下载 / 下载完成 / 下载失败”，不报百分比，减少打扰。

### 3. InstallService

- 使用 `FileProvider` 生成 `content://` URI。
- 发送 `ACTION_VIEW` Intent 打开 APK，触发系统安装器。
- 处理 `REQUEST_INSTALL_PACKAGES` 权限：
  - 已授权：直接打开安装器。
  - 未授权：语音引导用户到设置开启，并提供返回后的重试逻辑。

### 4. UpdatePrompt（与 HomeScreen 集成）

- 在 `HomeScreen` 启动流程中，相机初始化完成后调用 `UpdateService.checkForUpdate()`。
- 发现更新时：
  - 暂停扫描，语音播报发现更新提示。
  - 临时接管手势：上滑确认下载，下滑取消，超时未操作视为取消。
- 下载/安装阶段：持续语音反馈状态。

## 新增依赖

- `dio`：HTTP 请求与 APK 下载。
- `package_info_plus`：读取本地版本号。
- `connectivity_plus`：判断 Wi-Fi 连接状态（也可原生判断，用此库更统一）。

## 新增权限与配置

- `android.permission.INTERNET`
- `android.permission.REQUEST_INSTALL_PACKAGES`
- `android:allowBackup="false"`（解决旧版缓存问题）
- `FileProvider` 配置（`androidx.core.content.FileProvider`）

## 新增语音素材

全部使用 `say + afconvert` 生成，文件名与内容如下：

| 文件名 | 内容 |
|--------|------|
| `update_available.mp3` | 发现新版本 |
| `confirm_download.mp3` | 是否下载？上滑确认，下滑取消 |
| `downloading.mp3` | 正在下载更新包 |
| `download_complete.mp3` | 下载完成，请确认安装 |
| `download_failed.mp3` | 下载失败，请检查网络后重试 |
| `install_prompt.mp3` | 请确认安装 |
| `install_permission_denied.mp3` | 未获得安装权限，请前往设置开启 |
| `wifi_only.mp3` | 请在 Wi-Fi 环境下检查更新 |

## 错误处理（NSF）

- 检查更新失败：记录日志，本次静默跳过，不语音打扰。
- 下载失败：语音播报 `download_failed.mp3`。
- 安装权限被拒：语音播报 `install_permission_denied.mp3`。
- 安装器打开失败：语音播报具体失败原因。

## 测试计划

- `UpdateService` 单元测试：版本号比较、Gitee/GitHub fallback、Wi-Fi/频率条件。
- `DownloadService` 单元测试：下载进度解析、文件保存路径、失败重试。
- `InstallService` 单元测试：URI 构造、权限状态映射。
- 集成测试：模拟新版本返回，验证语音提示与下载调用。
- 真机测试：旧版覆盖安装后 `versionCode` 生效。

## 变更文件清单

- `lib/services/update_service.dart`（新增）
- `lib/services/download_service.dart`（新增）
- `lib/services/install_service.dart`（新增）
- `lib/services/connectivity_service.dart`（新增或扩展现有）
- `lib/screens/home_screen.dart`（接入更新提示手势）
- `lib/services/tts_service.dart`（注册新音频素材映射）
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/res/xml/file_paths.xml`（新增）
- `pubspec.yaml`
- `assets/audio/*.mp3`（新增 8 个）
- `test/unit/services/update_service_test.dart`（新增）
- `test/unit/services/download_service_test.dart`（新增）
- `CHANGELOG.md`
