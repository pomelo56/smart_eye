# 音频生成工作流

> 慧眼 SmartEye — 所有 `assets/audio/` 下的语音素材都是 **程序自动生成** 的，不依赖真人录音。

## 工具

| 工具 | 作用 | 平台 |
|------|------|------|
| `say` | macOS 自带 TTS，将文本合成 AIFF | 仅 macOS |
| `afconvert` | macOS 自带音频转换工具 | 仅 macOS |

生成流程：`say` 输出 AIFF → `afconvert` 转成 MP4/AAC（扩展名仍为 `.mp3`）→ Android `MediaPlayer` 按文件头解析，**不会**因扩展名误判。

## 当前素材清单

`assets/audio/` 现有素材（截止 v0.6.0）：

| 文件名 | 内容 | 大小 | 用途 |
|--------|------|------|------|
| `num_0.mp3` ~ `num_9.mp3` | 零到九 | 5-8 KB | 数字播报 |
| `jing.mp3` | 井 | 4 KB | 取餐码 `#` 前缀 |
| `hao.mp3` | 号 | 4 KB | 数字后缀 |
| `meituan.mp3` | 美团外卖 | 5 KB | 平台名 |
| `eleme.mp3` | 饿了么 | 5 KB | 平台名 |
| `jd_waimai.mp3` | 京东外卖 | 5 KB | 平台名 |
| `taobao.mp3` | 淘宝闪购 | 5 KB | 平台名 |
| `popu.mp3` | 朴朴超市 | 5 KB | 平台名 |
| `prefix.mp3` | 取餐码是 | 5 KB | 播报前缀 |
| `none.mp3` | 没有识别到取餐码，请重新对准小票 | 11 KB | 失败提示 |
| `scanning.mp3` | 识别中，手机请稳一些 | 11 KB | 扫描提示 |
| `faxian_waimai.mp3` | 发现外卖 | 9 KB | v0.6.0 新增 |
| `shibiezhong.mp3` | 识别中 | 8 KB | v0.6.0 新增 |
| `please_steady.mp3` | 手机请稳一些 | 11 KB | v0.6.0 新增 |
| `tutorial.mp3` | 完整使用教程 | 30 KB | 首次启动 |
| `di_tigao.mp3` / `di_tidi.mp3` | 距离反馈 | 1 KB | 远近提示音 |
| `hist_1.mp3` ~ `hist_5.mp3` | 第1条 ~ 第5条 | 4 KB | 历史序号 |
| `help.mp3` | 下滑操作帮助 | 9 KB | 教学 |
| `none_long.mp3` | 长版未识别提示 | 14 KB | 长时间未识别 |
| `first_launch.mp3` | 首次启动欢迎语 | 6 KB | 启动 |

## 新增素材的标准流程

### 步骤 1：写文案

文案要短（单个素材 ≤ 5 秒），风格与现有素材保持一致：

- 单字或短语（"发现外卖"、"识别中"）
- 不带语气词
- 不带停顿（停顿由拼接顺序控制）

### 步骤 2：生成 AIFF

```bash
say -v Tingting -o /tmp/new_clip.aiff "你的文案"
```

可选 voice：
- `Tingting` — 普通话女声（推荐）
- `Sin-ji` — 粤语
- `Mei-Jia` — 普通话女声（替代音色）

试听：

```bash
afplay /tmp/new_clip.aiff
```

### 步骤 3：转换为 `.mp3` 容器

```bash
afconvert -f mp4f -d aac /tmp/new_clip.aiff assets/audio/new_clip.mp3
```

**关键**：`mp4f` 格式是 MP4/AAC 容器，文件头是 `ftypmp42`，**扩展名仍叫 `.mp3`**。这是项目历史约定，不要改成真的 MP3 或 `.m4a`，否则 `MainActivity.kt` 路径不一致。

### 步骤 4：验证文件头

```bash
head -c 16 assets/audio/new_clip.mp3 | xxd
```

应显示 `6674 7970 6d70 3432`（`ftypmp42`）。

### 步骤 5：注册到 TtsService

`lib/services/tts_service.dart` 中：

- 单段提示 → `speakXxx()` 方法，调用 `playAssets(['assets/audio/new_clip.mp3'])`
- 拼接提示 → `speakXxx()` 方法，按顺序传入多段路径

更新 `TtsService._mapTextToAssets()`（如适用），添加关键词 → 路径映射。

### 步骤 6：写单元测试

`test/unit/services/tts_service_test.dart` 中验证 `playAssets` 收到正确路径列表。

### 步骤 7：构建并听感验证

参考 `docs/无线调试安装APK.md` 一键部署到手机实际听一次，确认语速、音量、停顿符合预期。

## 批量生成脚本（推荐）

如需一次性生成多个素材，可封装为 `scripts/gen_audio.sh`：

```bash
#!/bin/bash
# 用法：./scripts/gen_audio.sh "发现外卖" "识别中" "手机请稳一些"
set -e
VOICE=${VOICE:-Tingting}
for text in "$@"; do
  filename=$(echo "$text" | tr -d '[:space:]' | tr -d '，、。')
  # 文件名规范化：拼音 / 英文
  case "$text" in
    "发现外卖") filename="faxian_waimai" ;;
    "识别中")   filename="shibiezhong" ;;
    "手机请稳一些") filename="please_steady" ;;
    *) filename=$(echo "$text" | tr -d '[:space:]') ;;
  esac
  say -v "$VOICE" -o "/tmp/$filename.aiff" "$text"
  afconvert -f mp4f -d aac "/tmp/$filename.aiff" "assets/audio/$filename.mp3"
  echo "generated: assets/audio/$filename.mp3"
done
```

## 文件名规范

| 类别 | 命名 | 示例 |
|------|------|------|
| 数字 | `num_<0-9>` | `num_3.mp3` |
| 单字 | 中文拼音 | `jing.mp3`, `hao.mp3` |
| 短语 | 拼音下划线 | `faxian_waimai.mp3` |
| 平台 | 拼音 | `meituan.mp3`, `eleme.mp3` |
| 教学 | 英文描述 | `tutorial.mp3`, `help.mp3` |
| 距离提示 | `di_tigao` / `di_tidi` | `di_tigao.mp3`（提高） |
| 历史 | `hist_<N>` | `hist_3.mp3` |

## 常见问题

### `say` 不支持中文

macOS 12+ 自带 `Tingting` 音色支持普通话。如果 voice 列表中没有：

```bash
# 打开系统设置 → 辅助功能 → 朗读内容 → 系统声音 → 自定
# 下载「普通话」音色
```

### 想要不同音色

目前所有素材用同一种 `Tingting` 音色。如果想多音色：

1. 在 `gen_audio.sh` 中指定不同 voice
2. 为同一句话生成多份 `xxx_v1.mp3`、`xxx_v2.mp3`
3. 在 `TtsService` 中通过设置项选择不同路径

详见 `docs/OPTIMIZATION_REVIEW_hermes.md` 的"音色扩展"建议。

### 想要真人录音

`afconvert` 只能生成 AI/TTS 语音。如需真人：

1. 录制 WAV/AIF（44.1kHz 单声道）
2. 转换为统一格式：`afconvert -f mp4f -d aac source.wav target.mp3`
3. 替换同名文件即可，`TtsService` 路径不变
