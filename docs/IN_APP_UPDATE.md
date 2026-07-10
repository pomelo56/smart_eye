# 应用内更新机制

> 本文档记录慧眼 SmartEye 应用内更新的设计、实现与运维要求。

---

## 1. 设计目标

- 让视障用户无需手动下载 APK，在 Wi-Fi 环境下自动检测并提示更新。
- 优先使用国内源，避免 GitHub CDN 在国内访问慢/超时的问题。
- 所有异常路径必须有语音反馈，禁止静默失败。

---

## 2. 更新源优先级

**Gitee Releases 优先，GitHub Releases 兜底。**

| 优先级 | 源 | URL | 用途 |
|--------|-----|-----|------|
| 1 | Gitee | `https://gitee.com/api/v5/repos/free-style_2_0/smart_eye/releases/latest` | 国内主源，速度快 |
| 2 | GitHub | `https://api.github.com/repos/pomelo56/smart_eye/releases/latest` | Gitee 失败时使用 |

**运维要求**：每次发版必须同时发布到 Gitee 和 GitHub，且两个 Release 的 `versionCode` 必须一致。如果只发 GitHub，国内用户下载时可能因网络超时失败。

---

## 3. 触发条件

更新检查在应用启动后、相机权限检查之前执行（`HomeScreen._checkForUpdate`），满足以下条件才会真正请求网络：

1. 设备连接 Wi-Fi（通过 `ConnectivityService` 检测）。
2. 距离上次检查超过 7 天，或从未检查过（`last_update_check_millis`）。
3. 远程 `versionCode` 大于本地 `versionCode`。

---

## 4. 版本号解析

Release tag 或 body 中必须包含 `versionCode`。解析优先级：

1. tag 末尾的 `+NNN`（例如 `v0.8.3+17`）。
2. release body 中的 `versionCode: NNN`。

本地版本取 `package_info.buildNumber`（即 `pubspec.yaml` 中的 `+NNN`）。

---

## 5. 用户交互流程

```text
启动 → 检查更新（Wi-Fi + 7天节流）
        ↓ 有新版本
语音播报「发现新版本」+「上滑确认下载，下滑取消」
        ↓ 上滑
若缓存已存在 APK → 跳过下载，直接提示安装
若不存在        → 下载 APK（带进度日志）
        ↓ 下载完成
语音播报「下载完成，请按提示完成安装」
        ↓ 无安装权限
语音播报「需要允许安装未知应用权限，请前往设置开启」→ 打开设置
        ↓ 用户返回应用
自动重试安装
        ↓ 系统安装器
用户手动完成安装
```

---

## 6. 手势冲突说明

更新提示弹出期间，上下滑手势临时改为：

- 上滑：确认下载
- 下滑：取消更新

提示消失后立即恢复为原来的：

- 上滑：播报历史记录
- 下滑：播报操作帮助

---

## 7. 常见问题排查

| 现象 | 可能原因 | 排查方法 |
|------|---------|---------|
| 不提示更新 | 未连 Wi-Fi | 检查 `ConnectivityService` 日志 |
| 不提示更新 | 本地已是最新版 | 对比本地与远程 `versionCode` |
| 不提示更新 | 7 天内已检查过 | 清除 `last_update_check_millis` 或等待 7 天 |
| 提示更新但下载失败 | GitHub 访问慢/超时 | 确认 Gitee Release 已同步发布 |
| 未允许安装权限返回后无反应 | 旧版本 bug | 确保版本 >= v0.8.3 |
| 卸载重装后提示永久拒绝 | SharedPreferences 被备份恢复 | 确保版本 >= v0.8.3（使用 `noBackupFilesDir`） |

---

## 8. 发布 checklist

每次发版前必须完成：

- [ ] `pubspec.yaml` 版本号已更新（`versionName+versionCode`）。
- [ ] GitHub Release 已创建并上传 `app-release.apk`。
- [ ] Gitee Release 已创建并上传同一个 `app-release.apk`。
- [ ] Release tag 或 body 中包含 `versionCode: NNN`（如果 tag 不是 `vX.Y.Z+NNN` 格式）。
- [ ] 本地测试：安装旧版 APK，连接 Wi-Fi，确认能提示更新并下载安装。
