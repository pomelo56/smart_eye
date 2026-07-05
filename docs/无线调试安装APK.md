# 无线调试安装 APK

> 慧眼 SmartEye — **APK 由 `flutter build` 程序构建**，**通过无线 ADB 安装**到手机。整个流程无需 USB 数据线、无需人工复制文件。

## 前提条件

- 手机和电脑连接同一个 WiFi 网络
- 手机已开启「开发者选项」和「USB 调试」
- 手机已开启「无线调试」
- 电脑已安装 `adb` 工具

## 操作步骤

### 1. 手机开启无线调试

1. 打开手机「设置 → 关于手机」
2. 连续点击「版本号」7 次，开启开发者选项
3. 打开「设置 → 系统 → 开发者选项」
4. 开启「USB 调试」
5. 开启「无线调试」

### 2. 获取手机 IP 和端口

在「无线调试」页面：
1. 点击「使用配对码配对设备」（首次需要）
2. 记下显示的 **IP 地址和端口**（如 `192.168.1.7:44953`）
3. 记下 **配对码**（6位数字）

### 3. 配对（仅首次需要）

```bash
adb pair 192.168.1.7:配对端口
# 输入配对码
```

### 4. 连接设备

```bash
adb connect 192.168.1.7:44953
```

验证连接：

```bash
adb devices
# 应显示：
# List of devices attached
# 192.168.1.7:44953    device
```

### 5. 安装 APK

```bash
# 进入项目目录
cd /Users/pomelo/Project/smart_eye

# 构建并安装（一步到位）
flutter build apk --debug && adb -s 192.168.1.7:44953 install -r build/app/outputs/flutter-apk/app-debug.apk

# 或仅安装（已构建好）
adb -s 192.168.1.7:44953 install -r build/app/outputs/flutter-apk/app-debug.apk
```

参数说明：
- `-s`：指定设备（多设备时必须）
- `-r`：覆盖安装，保留应用数据

### 6. 断开连接

```bash
adb disconnect 192.168.1.7:44953
```

## 常见问题

### 设备未找到

```bash
# 检查设备是否在线
adb devices

# 如果列表为空：
# 1. 确认手机和电脑在同一 WiFi
# 2. 确认无线调试已开启
# 3. 重新连接：adb connect IP:端口
# 4. 端口可能变了，查看手机无线调试页面的最新端口
```

### 端口变了

手机重启或无线调试关闭重开后，端口会变化。重新查看手机上的端口并重新 `adb connect`。

### 安装失败

```bash
# 卸载后重装
adb -s 192.168.1.7:44953 uninstall com.example.smart_eye
adb -s 192.168.1.7:44953 install build/app/outputs/flutter-apk/app-debug.apk
```

### 构建失败

```bash
# 清理缓存重新构建
flutter clean
flutter build apk --debug
```

## 快速命令（复制即用）

将以下 IP 和端口替换为你手机上显示的实际值：

```bash
# 一键构建+安装
IP=192.168.1.7 && PORT=44953 && flutter build apk --debug && adb -s $IP:$PORT install -r build/app/outputs/flutter-apk/app-debug.apk

# 仅安装
IP=192.168.1.7 && PORT=44953 && adb -s $IP:$PORT install -r build/app/outputs/flutter-apk/app-debug.apk

# 查看日志
adb -s 192.168.1.7:44953 logcat -s SmartEye
```

## 查看 App 日志

```bash
# 实时查看慧眼日志
adb -s 192.168.1.7:44953 logcat -s SmartEye

# 查看应用内日志文件（导出到电脑）
adb -s 192.168.1.7:44953 pull /data/data/com.example.smart_eye/files/smart_eye.log ~/Desktop/
```
