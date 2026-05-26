import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

// ======================== MQTT 配置模型 ========================

class MqttConfig {
  String broker;
  int port;
  String clientId;
  String topic;

  MqttConfig({
    this.broker = "",
    this.port = 1883,
    this.clientId = "",
    this.topic = "",
  });

  MqttConfig copyWith({
    String? broker,
    int? port,
    String? clientId,
    String? topic,
  }) {
    return MqttConfig(
      broker: broker ?? this.broker,
      port: port ?? this.port,
      clientId: clientId ?? this.clientId,
      topic: topic ?? this.topic,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mqtt_broker', broker);
    await prefs.setInt('mqtt_port', port);
    await prefs.setString('mqtt_client_id', clientId);
    await prefs.setString('mqtt_topic', topic);
  }

  static Future<MqttConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return MqttConfig(
      broker: prefs.getString('mqtt_broker') ?? "",
      port: prefs.getInt('mqtt_port') ?? 1883,
      clientId: prefs.getString('mqtt_client_id') ?? "",
      topic: prefs.getString('mqtt_topic') ?? "",
    );
  }
}

// ======================== MQTT 服务 ========================

class MqttService extends ChangeNotifier {
  MqttConfig config = MqttConfig();
  MqttServerClient? _client;
  bool isConnected = false;
  String connectionStatus = "未连接";
  final List<MqttMessage> messages = [];

  bool get isInitialized => _client != null;

  Future<void> loadConfig() async {
    config = await MqttConfig.load();
    notifyListeners();
  }

  Future<void> updateConfig(MqttConfig newConfig) async {
    final wasConnected = isConnected;
    if (wasConnected) {
      disconnect();
    }
    config = newConfig;
    await config.save();
    _client = null;
    notifyListeners();
    await connect();
  }

  Future<void> connect() async {
    if (config.broker.isEmpty || config.clientId.isEmpty) {
      connectionStatus = "配置不完整";
      notifyListeners();
      return;
    }

    try {
      disconnect();

      _client = MqttServerClient(config.broker, config.clientId);
      _client!.port = config.port;
      _client!.keepAlivePeriod = 20;
      _client!.logging(on: false);
      _client!.autoReconnect = true;
      _client!.resubscribeOnAutoReconnect = true;
      _client!.onConnected = _onConnected;
      _client!.onDisconnected = _onDisconnected;
      _client!.onSubscribed = _onSubscribed;

      connectionStatus = "正在连接...";
      notifyListeners();

      final result = await _client!
          .connect()
          .timeout(const Duration(seconds: 10), onTimeout: () => null);

      if (result == null) {
        connectionStatus = "连接超时";
        _addMessage(MqttMessage(
          topic: "系统",
          payload: "连接超时，请检查 Broker 地址和端口",
          timestamp: DateTime.now(),
          isOutgoing: false,
        ));
        notifyListeners();
        return;
      }

      if (config.topic.isNotEmpty) {
        _client!.subscribe(config.topic, mqtt.MqttQos.atMostOnce);
      }

      _client!.updates!.listen(
          (List<mqtt.MqttReceivedMessage<mqtt.MqttMessage>> c) {
        for (var msg in c) {
          final mqtt.MqttPublishMessage recMess =
              msg.payload as mqtt.MqttPublishMessage;
          final String pt = utf8.decode(recMess.payload.message);

          if (pt == "rexit") {
            _addMessage(MqttMessage(
              topic: msg.topic,
              payload: "收到退出命令",
              timestamp: DateTime.now(),
              isOutgoing: false,
            ));
            disconnect();
          } else {
            _addMessage(MqttMessage(
              topic: msg.topic,
              payload: pt,
              timestamp: DateTime.now(),
              isOutgoing: false,
            ));
          }
        }
      });
    } catch (e) {
      connectionStatus = "连接失败";
      _addMessage(MqttMessage(
        topic: "系统",
        payload: "连接失败: $e",
        timestamp: DateTime.now(),
        isOutgoing: false,
      ));
      notifyListeners();
    }
  }

  void disconnect() {
    _client?.disconnect();
    _client = null;
  }

  void publish(String payload, {bool isSet = true}) {
    if (!isConnected || _client == null) {
      _addMessage(MqttMessage(
        topic: "系统",
        payload: "未连接，无法发送消息",
        timestamp: DateTime.now(),
        isOutgoing: true,
      ));
      return;
    }

    final String publishTopic =
        isSet ? "${config.topic}/set" : "${config.topic}/up";
    final mqtt.MqttClientPayloadBuilder builder =
        mqtt.MqttClientPayloadBuilder();
    builder.addString(payload);

    _client!.publishMessage(
        publishTopic, mqtt.MqttQos.atMostOnce, builder.payload!);

    _addMessage(MqttMessage(
      topic: publishTopic,
      payload: payload,
      timestamp: DateTime.now(),
      isOutgoing: true,
    ));
  }

  void _onConnected() {
    isConnected = true;
    connectionStatus = "已连接";
    _addMessage(MqttMessage(
      topic: "系统",
      payload: "成功连接到 Broker",
      timestamp: DateTime.now(),
      isOutgoing: false,
    ));
    notifyListeners();
  }

  void _onDisconnected() {
    isConnected = false;
    connectionStatus = "已断开连接";
    _addMessage(MqttMessage(
      topic: "系统",
      payload: "已断开连接",
      timestamp: DateTime.now(),
      isOutgoing: false,
    ));
    notifyListeners();
  }

  void _onSubscribed(String topic) {
    _addMessage(MqttMessage(
      topic: "系统",
      payload: "已订阅主题: $topic",
      timestamp: DateTime.now(),
      isOutgoing: false,
    ));
  }

  void _addMessage(MqttMessage message) {
    messages.add(message);
    notifyListeners();
  }

  void clearMessages() {
    messages.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

// ======================== 消息模型 ========================

class MqttMessage {
  final String topic;
  final String payload;
  final DateTime timestamp;
  final bool isOutgoing;

  MqttMessage({
    required this.topic,
    required this.payload,
    required this.timestamp,
    required this.isOutgoing,
  });
}

// ======================== App 入口 ========================

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '远程智能灯控',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const MainShell(),
    );
  }
}

// ======================== 主框架 + 底部导航 ========================

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final MqttService _service = MqttService();
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    await _service.loadConfig();
    await _service.connect();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final pages = <Widget>[
          SwitchPage(service: _service),
          ChatPage(service: _service),
          SettingsPage(service: _service),
        ];

        return Scaffold(
          body: pages[_currentIndex],
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() => _currentIndex = index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.toggle_on_outlined),
                selectedIcon: Icon(Icons.toggle_on),
                label: '开关',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_outlined),
                selectedIcon: Icon(Icons.chat),
                label: '对话',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        );
      },
    );
  }
}

// ======================== 连接状态指示器 ========================

class ConnectionChip extends StatelessWidget {
  final MqttService service;
  const ConnectionChip({super.key, required this.service});

  Future<void> _showDisconnectDialog(BuildContext context) async {
    if (!service.isConnected) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('断开连接'),
        content: const Text('确定要断开 MQTT 连接吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('断开'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      service.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDisconnectDialog(context),
      child: Chip(
        avatar: Icon(
          service.isConnected ? Icons.check_circle : Icons.cancel,
          size: 16,
          color: service.isConnected ? Colors.green : Colors.red,
        ),
        label: Text(
          service.connectionStatus,
          style: TextStyle(
            color: service.isConnected ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        backgroundColor: service.isConnected
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.red.withValues(alpha: 0.15),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}

// ======================== 开关模式页面 ========================

class SwitchPage extends StatelessWidget {
  final MqttService service;
  const SwitchPage({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('开关控制'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: ConnectionChip(service: service)),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 灯泡图标
              Icon(
                service.isConnected
                    ? Icons.lightbulb_outline
                    : Icons.lightbulb_outline,
                size: 80,
                color: service.isConnected
                    ? theme.colorScheme.primary.withValues(alpha: 0.6)
                    : theme.colorScheme.outline.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                service.isConnected ? "已连接 - 可控制" : "未连接",
                style: theme.textTheme.titleMedium?.copyWith(
                  color: service.isConnected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 48),
              // 开 / 关 按钮
              Row(
                children: [
                  Expanded(
                    child: _buildPowerButton(
                      context,
                      label: "开",
                      icon: Icons.power_settings_new,
                      color: Colors.green,
                      onPressed: service.isConnected
                          ? () => service.publish("on")
                          : null,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _buildPowerButton(
                      context,
                      label: "关",
                      icon: Icons.power_off,
                      color: Colors.red,
                      onPressed: service.isConnected
                          ? () => service.publish("off")
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              if (!service.isConnected)
                FilledButton.tonalIcon(
                  onPressed: () => service.connect(),
                  icon: const Icon(Icons.refresh),
                  label: const Text("重新连接"),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPowerButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onPressed,
  }) {
    final isEnabled = onPressed != null;

    return SizedBox(
      height: 140,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isEnabled ? color.withValues(alpha: 0.15) : null,
          foregroundColor: isEnabled ? color : null,
          elevation: isEnabled ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isEnabled
                  ? color.withValues(alpha: 0.5)
                  : Colors.grey.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================== 对话模式页面 ========================

class ChatPage extends StatefulWidget {
  final MqttService service;
  const ChatPage({super.key, required this.service});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息对话'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: ConnectionChip(service: widget.service)),
          ),
          if (widget.service.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空消息',
              onPressed: () => widget.service.clearMessages(),
            ),
        ],
      ),
      body: Column(
        children: [
          // 提醒横幅
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.6),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "注意，此为 MQTT 协议消息通道，仅做调试用途，不应作为聊天软件使用",
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.service.messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.message_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 16),
                        Text(
                          "暂无消息",
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.service.messages.length,
                    itemBuilder: (context, index) {
                      final message = widget.service.messages[
                          widget.service.messages.length - 1 - index];
                      return _buildMessageBubble(context, message);
                    },
                  ),
          ),
          const Divider(height: 1),
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: "输入消息内容...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      enabled: widget.service.isConnected,
                    ),
                    enabled: widget.service.isConnected,
                    maxLines: null,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: widget.service.isConnected ? _sendMessage : null,
                  icon: const Icon(Icons.send),
                  label: const Text("发送"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isNotEmpty) {
      widget.service.publish(message);
      _messageController.clear();
    }
  }

  Widget _buildMessageBubble(BuildContext context, MqttMessage message) {
    final isOutgoing = message.isOutgoing;
    final isSystem = message.topic == "系统";
    final theme = Theme.of(context);

    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              message.payload,
              style: theme.textTheme.labelSmall,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment:
            isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isOutgoing
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: isOutgoing
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    message.topic,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isOutgoing
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message.payload,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isOutgoing
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.timestamp),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isOutgoing
                          ? theme.colorScheme.onPrimary
                              .withValues(alpha: 0.7)
                          : theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    return "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}";
  }
}

// ======================== 设置页面 ========================

class SettingsPage extends StatefulWidget {
  final MqttService service;
  const SettingsPage({super.key, required this.service});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _brokerController;
  late TextEditingController _portController;
  late TextEditingController _clientIdController;
  late TextEditingController _topicController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final cfg = widget.service.config;
    _brokerController = TextEditingController(text: cfg.broker);
    _portController = TextEditingController(text: cfg.port.toString());
    _clientIdController = TextEditingController(text: cfg.clientId);
    _topicController = TextEditingController(text: cfg.topic);
  }

  @override
  void dispose() {
    _brokerController.dispose();
    _portController.dispose();
    _clientIdController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _saveAndReconnect() async {
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("端口号无效，请输入 1-65535 的数字")),
        );
      }
      return;
    }

    setState(() => _isSaving = true);

    final newConfig = MqttConfig(
      broker: _brokerController.text.trim(),
      port: port,
      clientId: _clientIdController.text.trim(),
      topic: _topicController.text.trim(),
    );

    await widget.service.updateConfig(newConfig);

    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("设置已保存并重新连接"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MQTT 设置'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: ConnectionChip(service: widget.service)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "服务器配置",
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _brokerController,
              label: "Broker 地址",
              hint: "例如 mqtt.bemfa.com",
              icon: Icons.dns_outlined,
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _portController,
              label: "端口",
              hint: "例如 9501",
              icon: Icons.lan_outlined,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            Text(
              "客户端配置",
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _clientIdController,
              label: "Client ID",
              hint: "客户端唯一标识",
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _topicController,
              label: "Topic 主题",
              hint: "例如 light002",
              icon: Icons.topic_outlined,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveAndReconnect,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? "正在保存..." : "保存并重新连接"),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => widget.service.connect(),
                icon: const Icon(Icons.refresh),
                label: const Text("仅重新连接（不修改配置）"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
