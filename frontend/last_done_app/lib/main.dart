import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const LastDoneApp());
}

class LastDoneApp extends StatelessWidget {
  const LastDoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Last Done',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A9A8A)),
        useMaterial3: true,
      ),
      home: const BootPage(),
    );
  }
}

class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:7071/api',
  );

  static const familyCodeHeader = 'X-Family-Code';
  static const userNameHeader = 'X-User-Name';
}

class BootPage extends StatefulWidget {
  const BootPage({super.key});

  @override
  State<BootPage> createState() => _BootPageState();
}

class _BootPageState extends State<BootPage> {
  late final Future<UserContext?> _future;

  @override
  void initState() {
    super.initState();
    _future = LocalAuthStore.read();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserContext?>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final contextData = snapshot.data;
        if (contextData == null) {
          return const SetupPage();
        }

        return HomePage(initialContext: contextData);
      },
    );
  }
}

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _familyCode = TextEditingController();
  final _userName = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _familyCode.dispose();
    _userName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);
    final contextData = UserContext(
      familyCode: _familyCode.text.trim().toUpperCase(),
      userName: _userName.text.trim(),
    );
    await LocalAuthStore.save(contextData);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomePage(initialContext: contextData)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('初期設定')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _familyCode,
                decoration: const InputDecoration(
                  labelText: '家族コード（6桁英数字）',
                  border: OutlineInputBorder(),
                ),
                maxLength: 6,
                textCapitalization: TextCapitalization.characters,
                validator: (v) {
                  final value = (v ?? '').trim();
                  final regex = RegExp(r'^[A-Za-z0-9]{6}$');
                  return regex.hasMatch(value) ? null : '6桁の英数字を入力してください';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _userName,
                decoration: const InputDecoration(
                  labelText: 'ユーザー名',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  return (v ?? '').trim().isEmpty ? 'ユーザー名を入力してください' : null;
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存して開始'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.initialContext});

  final UserContext initialContext;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late UserContext _contextData;
  late ApiClient _api;
  final _newTextController = TextEditingController();

  bool _loading = true;
  bool _adding = false;
  String? _error;
  List<DailyItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _contextData = widget.initialContext;
    _api = ApiClient(_contextData);
    _loadItems();
  }

  @override
  void dispose() {
    _newTextController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _api.getItems();
      setState(() => _items = items);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _addItem() async {
    final text = _newTextController.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() => _adding = true);
    try {
      await _api.createItem(text);
      _newTextController.clear();
      await _loadItems();
    } catch (e) {
      _showSnackBar('追加に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _refreshItem(DailyItem item) async {
    try {
      await _api.refreshItem(item.id);
      await _loadItems();
    } catch (e) {
      _showSnackBar('更新に失敗しました: $e');
    }
  }

  Future<void> _resetSetup() async {
    await LocalAuthStore.clear();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SetupPage()),
      (_) => false,
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('やったこと (${_contextData.userName})'),
        actions: [
          IconButton(
            tooltip: '初期設定をやり直す',
            onPressed: _resetSetup,
            icon: const Icon(Icons.manage_accounts_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newTextController,
                    decoration: const InputDecoration(
                      labelText: 'やったことを追加',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addItem(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _adding ? null : _addItem,
                  child: _adding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('追加'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                color: Colors.red.shade50,
                child: Text(
                  '読み込みエラー: $_error',
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadItems,
                child: ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.text, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text('最終実施: ${item.updatedDate} / ${item.updatedBy}'),
                            Text('作成: ${item.createdDate} / ${item.createdBy}'),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton(
                                onPressed: () => _refreshItem(item),
                                child: const Text('更新'),
                              ),
                            ),
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: const Text('履歴'),
                              children: [
                                if (item.history.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 12),
                                    child: Text('履歴なし'),
                                  ),
                                for (final h in item.history)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(h.doneDate),
                                    trailing: Text(h.userName),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LocalAuthStore {
  static const _keyFamilyCode = 'familyCode';
  static const _keyUserName = 'userName';

  static Future<UserContext?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final familyCode = prefs.getString(_keyFamilyCode)?.trim();
    final userName = prefs.getString(_keyUserName)?.trim();

    if (familyCode == null || familyCode.isEmpty || userName == null || userName.isEmpty) {
      return null;
    }

    return UserContext(familyCode: familyCode, userName: userName);
  }

  static Future<void> save(UserContext contextData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFamilyCode, contextData.familyCode);
    await prefs.setString(_keyUserName, contextData.userName);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFamilyCode);
    await prefs.remove(_keyUserName);
  }
}

class UserContext {
  const UserContext({required this.familyCode, required this.userName});

  final String familyCode;
  final String userName;
}

class ApiClient {
  ApiClient(this._contextData);

  final UserContext _contextData;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        AppConfig.familyCodeHeader: _contextData.familyCode,
        AppConfig.userNameHeader: _contextData.userName,
      };

  Future<List<DailyItem>> getItems() async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/daily-items');
    final response = await http.get(uri, headers: _headers);
    _ensureSuccess(response);

    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .map((x) => DailyItem.fromJson(x as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> createItem(String text) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/daily-items');
    final response = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode({'text': text}),
    );
    _ensureSuccess(response);
  }

  Future<void> refreshItem(String id) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/daily-items/$id/refresh');
    final response = await http.post(uri, headers: _headers);
    _ensureSuccess(response);
  }

  static void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    throw Exception('HTTP ${response.statusCode}: ${response.body}');
  }
}

class DailyItem {
  const DailyItem({
    required this.id,
    required this.text,
    required this.createdDate,
    required this.createdBy,
    required this.updatedDate,
    required this.updatedBy,
    required this.history,
  });

  final String id;
  final String text;
  final String createdDate;
  final String createdBy;
  final String updatedDate;
  final String updatedBy;
  final List<HistoryRecord> history;

  factory DailyItem.fromJson(Map<String, dynamic> json) {
    final rawHistory = json['history'] as List<dynamic>? ?? const [];
    return DailyItem(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      createdDate: json['createdDate'] as String? ?? '',
      createdBy: json['createdBy'] as String? ?? '',
      updatedDate: json['updatedDate'] as String? ?? '',
      updatedBy: json['updatedBy'] as String? ?? '',
      history: rawHistory
          .map((x) => HistoryRecord.fromJson(x as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class HistoryRecord {
  const HistoryRecord({required this.doneDate, required this.userName});

  final String doneDate;
  final String userName;

  factory HistoryRecord.fromJson(Map<String, dynamic> json) {
    return HistoryRecord(
      doneDate: json['doneDate'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
    );
  }
}
