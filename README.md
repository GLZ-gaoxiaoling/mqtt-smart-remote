# MQTT Smart Remote

> 基于 Flutter 的跨平台 MQTT 物联网设备遥控器，轻松控制你的智能设备。

[![Flutter](https://img.shields.io/badge/Flutter-3.12+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Linux%20%7C%20Web-blue)]()

---

## ✨ 功能特性

- 🎛️ **开关模式** — 一键控制设备开/关，大按钮设计，操作直观
- 💬 **消息对话** — 实时收发 MQTT 消息，查看设备反馈
- ⚙️ **灵活配置** — 可视化设置 Broker、端口、Client ID、Topic
- 💾 **配置持久化** — 设置自动保存，启动即连接
- 🌓 **深色模式** — 跟随系统主题，护眼体验
- 📱 **跨平台** — 一套代码，多端运行

---

## 📸 界面预览

| 开关控制 | 消息对话 | 设置页面 |
| :---: | :---: | :---: |
| 一键发送 on/off | 实时消息收发 | 可视化 MQTT 配置 |

---

## 🚀 快速开始

### 前置要求

- Flutter SDK >= 3.12.0
- Dart SDK >= 3.12.0
- 一个可用的 MQTT Broker（如 [EMQX](https://www.emqx.io)、[Mosquitto](https://mosquitto.org) 等）

### 安装运行

```bash
# 克隆项目
git clone https://github.com/YOUR_USERNAME/mqtt-smart-remote.git
cd mqtt-smart-remote

# 安装依赖
flutter pub get

# 运行（选择你的目标平台）
flutter run
```

### 配置连接

1. 启动应用后，点击底部导航栏的 **设置**
2. 填入你的 MQTT Broker 信息：
   - **Broker 地址** — 如 `broker.emqx.io`
   - **端口** — 如 `1883`（TCP）或 `8883`（TLS）
   - **Client ID** — 客户端唯一标识
   - **Topic** — 订阅/发布的主题
3. 点击 **保存并重新连接**

---

## 🏗️ 项目结构

```
lib/
└── main.dart          # 应用入口 + 全部业务逻辑
    ├── MqttConfig     # MQTT 配置模型（持久化）
    ├── MqttService    # MQTT 连接管理服务
    ├── MainShell      # 主框架 + 底部导航
    ├── SwitchPage     # 开关控制页
    ├── ChatPage       # 消息对话页
    └── SettingsPage   # 设置页
```

---

## 📦 技术栈

| 技术 | 说明 |
|------|------|
| [Flutter](https://flutter.dev) | 跨平台 UI 框架 |
| [mqtt_client](https://pub.dev/packages/mqtt_client) | MQTT 协议客户端 |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | 本地配置持久化 |

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

---

## 📄 License

[MIT License](LICENSE)
