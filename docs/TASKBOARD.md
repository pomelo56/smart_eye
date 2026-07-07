# TASKBOARD — 慧眼 SmartEye

> 多 Agent 协作的任务追踪看板。
> 单一事实源（Single Source of Truth）：所有 Agent 接手时先读本文件，再读 AGENTS.md / PROJECT.md / HANDOVER.md。
> 更新规则：每次任务状态变更（开始 / 完成 / 阻塞）必须立即同步本文件，不允许只更新代码或 commit 信息。

---

## 使用约定

- **状态语义**：
  - `[ ]` 待办
  - `[~]` 进行中（同时只能有一项，标明 owner）
  - `[x]` 已完成（保留 1 个月内用于回溯）
  - `[!]` 阻塞（必须写明阻塞原因 + 解除条件）
- **优先级**：
  - **P0** — 阻塞发版 / 安全 / 隐私红线
  - **P1** — 用户可感知的核心功能
  - **P2** — 体验优化 / 工程债务
  - **P3** — 锦上添花 / 远期规划
- **版本关联**：每条任务标注目标版本（v0.X.0）。跨版本任务须拆分。
- **完成定义（DoD）**：
  1. `flutter analyze` 零警告
  2. `flutter test` 全绿（含新增测试）
  3. 私有 `test/.../xxx_test.dart` 覆盖新逻辑
  4. `CHANGELOG.md` / `VERSION.md` 同步
  5. 涉及用户面变更的，语音反馈已录制并注册到 `TtsService._mapTextToAssets`

---

## 1. 当前冲刺（v0.7.0 — 体积与设置页基础）

> 目标：APK 体积 < 25 MB；为后续 LLM API Key 预留设置入口；首次开源发版可对外发布。

### 1.1 进行中

| 任务 | 优先级 | Owner | 目标版本 | 备注 |
|------|--------|-------|----------|------|
| 启用 R8 代码压缩（`minifyEnabled true` + `shrinkResources true`） | P1 | dev-agent | v0.7.0 | 预期 release APK 再省 5-10 MB（31.6 → 22-25 MB） |
| `proguard-rules.pro` 补充 keep 规则 + 写 build_config 单测断言 | P1 | dev-agent | v0.7.0 | ML Kit 已有 keep 规则，需补 Kotlin / Flutter 反射相关 |
| 建 `docs/TASKBOARD.md`（本文件） | P2 | dev-agent | v0.7.0 | 已完成 |

### 1.2 待开发

| 任务 | 优先级 | 目标版本 | 备注 |
|------|--------|----------|------|
| 设置页面（双击右上角唤出，API Key 配置等） | P1 | v0.7.0 | ROADMAP 中 v0.7.0 主目标；本期只做入口壳 + API Key 输入框 |
| TalkBack 焦点兼容性测试 | P2 | v0.7.0 | 在设置页加 Semantics 后用 TalkBack 走一遍 |
| `ProjectStructure` 文档同步：补充 `test/build_config_test.dart` | P3 | v0.7.0 | — |

### 1.3 待修复（Bug）

| ID | 严重 | 任务 | 备注 |
|----|------|------|------|
| KI-001 | 🔴 | 音频叠加 — `speak()` 是 fire-and-forget | PROJECT.md 已知；规范要求所有 `speak()` 前 `await stop()` |
| KI-002 | 🟡 | OPPO/ColorOS 相机首次冷启动超时 | 3 次重试，间隔 2s/4s；`HomeScreen._initCameraWithRetry()` |
| KI-003 | 🟡 | 手写文字识别率低 | ML Kit 固有限制，文档化即可；真实小票为印刷体不受影响 |
| KI-004 | 🟡 | `flutter_assets/` 路径陷阱 | `MainActivity.kt` 已处理；新接入原生层时需注意 |
| KI-005 | 🟢 | 无线 ADB 多设备干扰 | `adb disconnect` 后重连；`docs/无线调试安装APK.md` 已记录 |

### 1.4 待验证

| 项 | 优先级 | 验证方法 | 当前状态 |
|----|--------|---------|----------|
| R8 启用后真机启动不崩 | P0 | 真机 install + 启动 + 完整功能走查 | 待验证 |
| R8 启用后 ML Kit 中文识别仍可用 | P0 | 真机识别带"美团"字样小票 | 待验证 |
| R8 启用后预录音频仍可播放 | P0 | 真机首次启动听到完整教程 | 待验证 |
| 真实外卖小票（美团热敏打印）OCR 识别 | P1 | 拍照后 5 秒内播报 | ⚠️ 待验证 |
| 日志导出功能在真机可用 | P2 | 双击手势 → 文件出现在下载目录 | ⚠️ 待验证 |

### 1.5 技术债务

| 债务项 | 优先级 | 说明 | 解决版本 |
|--------|--------|------|----------|
| 调试日志覆盖层 | P1 | 顶部 8 行绿色日志应可开关（长按/特定手势） | v0.8.0 |
| AudioService 集成测试 | P2 | 单测覆盖初始化/停止（MethodChannel mock），缺真机集成测试 | v0.8.0 |
| 日志导出 Scoped Storage 适配 | P2 | Android 10+ 不再需要 `WRITE_EXTERNAL_STORAGE` 权限 | v0.8.0 |
| 双机种适配 | P3 | 仅 OPPO A96 验证过；华为/小米/三星待测 | v1.0.0 |
| 平台名称语音播报 | P3 | 当前仅日志记录平台名；需录制"美团外卖""饿了么"等音频 | v0.7.1 |
| 各平台小票实测 | P3 | 美团已验证，饿了么/京东/淘宝闪购/朴朴超市需真实小票测试 | v0.7.1 |

---

## 2. 未来冲刺（v0.8.0 — v2.0.0 远期）

### 2.1 v0.8.0 — 差分帧检测 / 体验优化

- [ ] Phase B 差分帧检测：前后两帧对比判断小票移出方向
- [ ] 距离估算：文字大小变化 → "再近一点" / "再远一点"
- [ ] 调试日志开关手势
- [ ] AudioService 集成测试
- [ ] Scoped Storage 适配

### 2.2 v0.7.1 — 平台播报

- [ ] 录制"美团外卖""饿了么""京东外卖""淘宝闪购""朴朴超市"音频
- [ ] `TtsService` 在播报取餐码前先播平台名
- [ ] 各平台小票实测（至少 3 个真实小票）

### 2.3 v1.0.0 — 云端 LLM + 系统 TTS（Phase 2）

- [ ] `AiParser` 服务：HTTP 调用 qwen-turbo，解析 JSON
- [ ] 已知平台走本地正则（零成本）；未知格式调云端
- [ ] API Key 配置页（v0.7.0 入口已建好）
- [ ] `TtsSystemService`：系统 TTS 优先，失败 fallback 到音频拼接
- [ ] 网络异常 / 额度耗尽的降级策略
- [ ] 隐私：不上传原图，只传 OCR 文本

### 2.4 v1.1.0 — 系统 TTS 完善

- [ ] TTS 引擎自动检测与切换
- [ ] 平台名 / 位置词 / 任意文字均可用系统 TTS 朗读
- [ ] 音频素材仅保留高频短词（"井""号"等）

### 2.5 v2.0.0 — 多模态云端理解（Phase 3）

- [ ] 跳过 OCR，直接调用 VLM（智谱 GLM-4V-Flash）
- [ ] 识别非文字物品（药盒 / 遥控器 / 商品标签 / 门牌号）
- [ ] 描述物体位置
- [ ] 阅读复杂文本（信件 / 说明书 / 菜单）
- [ ] 高级功能开关（默认 Phase 2 文本方案）

---

## 3. 已完成（最近 1 个月）

> 保留最近一个月用于回溯。超过一个月的归档到 `docs/CHANGELOG.md`。

### v0.6.2 (2026-07-06)

- [x] Debug APK 体积优化 237 MB → 89 MB（-62%）
- [x] `docs/APK_SIZE_OPTIMIZATION.md` 更新

### v0.6.1 (2026-07-06)

- [x] Release APK 体积优化 65 MB → 31.6 MB（-51%）
- [x] ABI 单架构（`ndk.abiFilters "arm64-v8a"`）
- [x] 清理孤儿音频 `closer.mp3` / `farther.mp3`
- [x] `audio_assets_inventory_test.dart` 防止未来孤儿
- [x] `docs/APK_SIZE_OPTIMIZATION.md` 首次记录

### v0.6.0 (2026-07-05)

- [x] 「发现外卖」语音提示
- [x] `OcrService.hasPlatformKeyword()` 平台关键词检测
- [x] `TtsService.speakDetectedTakeout()` 拼接 3 段音频
- [x] 5 秒冷却防止手机抖动反复触发
- [x] `ocr_platform_keyword_test.dart` 9 个测试

### v0.5.1 (2026-07-05)

- [x] `AudioService._isInitialized` 真实检测（不再硬编码 true）
- [x] `stop()` 返回 bool，让调用者感知失败
- [x] `_log()` 不再触发 `setState`（改 ValueListenableBuilder）
- [x] `OcrService._cooldownMap` 自动清理过期条目（修内存泄漏）
- [x] `MethodChannel` handler 只注册一次

---

## 4. 协作规则（多 Agent）

1. **任务领取**：从「待开发」中认领，改状态为 `[~]` 并在 Owner 列写明 Agent 名
2. **任务完成**：改 `[x]`，并在 CHANGELOG.md 加条目；如有架构变更同步更新 PROJECT.md ADR
3. **任务阻塞**：改 `[!]`，写明原因 + 解除条件；在 PR/issue 中 @owner
4. **新发现任务**：直接加入对应优先级区块，跨版本加版本标签
5. **冲突解决**：同一文件多 Agent 同时改时，按"先来先服务"原则在文件中加 TODO 标记，下一个 Agent 接手时合并
6. **每日站会**：每个 Agent 在本文件底部「Agent 日志」追加当日工作摘要

---

## 5. Agent 日志

> 每个 Agent 每日追加。格式：`### YYYY-MM-DD HH:MM — <Agent 名>`

### 2026-07-07 — dev-agent

- 建 `docs/TASKBOARD.md`（v0.7.0 任务看板）
- 启动 v0.7.0 R8 压缩 worktree (`feat/v0.7.0-prep`)
