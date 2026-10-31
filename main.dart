import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TuktukiApp());
}

String iqd(int n) =>
    '${n.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} د.ع';

class TuktukiApp extends StatelessWidget {
  const TuktukiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تكتكي',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          secondary: Color(0xFFF59E0B),
          surface: Color(0xFF1E293B),
        ),
      ),
      builder: (ctx, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  List> _obs = [];
  List> _logs = [];
  final _incCtrl = TextEditingController();
  final _expCtrl = TextEditingController();
  final Map<String, bool> _checked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final obStr = p.getString('obs');
    final lgStr = p.getString('logs');
    setState(() {
      _obs = obStr != null
          ? List>.from(jsonDecode(obStr))
          : [
              {'id': '1', 'title': 'تبديل دهن وصيانة', 'target': 15000, 'saved': 0, 'days': 10, 'remDays': 10, 'skip': 0},
              {'id': '2', 'title': 'السلفة الشهرية', 'target': 150000, 'saved': 0, 'days': 30, 'remDays': 30, 'skip': 0},
              {'id': '3', 'title': 'احتياطي عطلات', 'target': 50000, 'saved': 0, 'days': 25, 'remDays': 25, 'skip': 0},
            ];
      if (lgStr != null) _logs = List>.from(jsonDecode(lgStr));
      for (var o in _obs) {
        _checked[o['id']] = true;
      }
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('obs', jsonEncode(_obs));
    await p.setString('logs', jsonEncode(_logs));
  }

  int _remAmt(Map o) => ((o['target'] as int) - (o['saved'] as int)).clamp(0, 999999999);
  int _safeDays(Map o) => (o['remDays'] as int) <= 0 ? 1 : (o['remDays'] as int);
  int _daily(Map o) => _remAmt(o) <= 0 ? 0 : (_remAmt(o) / _safeDays(o)).ceil();
  int _nextIfSkipped(Map o) =>
      _remAmt(o) <= 0 ? 0 : (_remAmt(o) / ((_safeDays(o) - 1) <= 0 ? 1 : (_safeDays(o) - 1))).ceil();

  void _saveDay() {
    final inc = int.tryParse(_incCtrl.text.trim()) ?? 0;
    final exp = int.tryParse(_expCtrl.text.trim()) ?? 0;
    if (inc <= 0) return;
    int allocated = 0;
    List<String> notes = [];

    setState(() {
      for (var o in _obs) {
        if (_remAmt(o) <= 0) continue;
        final pay = _checked[o['id']] ?? true;
        final share = _daily(o);
        if (pay && share > 0) {
          o['saved'] = ((o['saved'] as int) + share).clamp(0, o['target'] as int);
          o['remDays'] = ((o['remDays'] as int) - 1).clamp(1, 365);
          allocated += share;
          notes.add('${o['title']}: ${iqd(share)}');
        } else {
          o['remDays'] = ((o['remDays'] as int) - 1).clamp(1, 365);
          o['skip'] = (o['skip'] as int) + 1;
          notes.add('${o['title']}: تأجل (زاد القسط الجاي)');
        }
      }
      final now = DateTime.now();
      _logs.insert(0, {
        'date': '${now.year}/${now.month}/${now.day}',
        'inc': inc,
        'exp': exp,
        'alloc': allocated,
        'net': inc - exp - allocated,
        'notes': notes,
      });
      _incCtrl.clear();
      _expCtrl.clear();
      for (var o in _obs) {
        _checked[o['id']] = true;
      }
    });
    _save();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('عاشت إيدك! انحفظت يومية اليوم بالسجل.'), backgroundColor: Color(0xFF10B981)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        centerTitle: true,
        title: const Text('تكتكي - الإدارة المالية', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: [_buildToday(), _buildObs(), _buildLogs()][_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: const Color(0xFF1E293B),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calculate), label: 'حساب اليوم'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: 'الالتزامات'),
          NavigationDestination(icon: Icon(Icons.history), label: 'السجل'),
        ],
      ),
    );
  }

  Widget _buildToday() {
    final inc = int.tryParse(_incCtrl.text.trim()) ?? 0;
    final exp = int.tryParse(_expCtrl.text.trim()) ?? 0;
    final active = _obs.where((o) => _remAmt(o) > 0).toList();
    final reqToday = active.fold<int>(0, (s, o) => s + ((_checked[o['id']] ?? true) ? _daily(o) : 0));
    final net = inc - exp - reqToday;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFF1E293B),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                TextField(
                  controller: _incCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'شكد اشتغلت اليوم؟ (د.ع)', prefixIcon: Icon(Icons.payments)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _expCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'بانزين ومصرف (د.ع)', prefixIcon: Icon(Icons.local_gas_station)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text('حصص الالتزامات اليوم (طفي الصح إذا ما خليتله اليوم):', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...active.map((o) {
          final isOn = _checked[o['id']] ?? true;
          return Card(
            color: const Color(0xFF1E293B),
            child: CheckboxListTile(
              value: isOn,
              activeColor: const Color(0xFF10B981),
              onChanged: (v) => setState(() => _checked[o['id']] = v ?? true),
              title: Text('${o['title']} (باقي ${o['remDays']} يوم)', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                isOn
                    ? 'المطلوب اليوم: ${iqd(_daily(o))} | باقي الكلي: ${iqd(_remAmt(o))}'
                    : 'تأجل اليوم! راح يصير القسط الجاي: ${iqd(_nextIfSkipped(o))} لقرب الديدلاين',
                style: TextStyle(color: isOn ? const Color(0xFF10B981) : Colors.orangeAccent),
              ),
            ),
          );
        }),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF065F46), borderRadius: BorderRadius.circular(14)),
          child: Column(
            children: [
              Text('مجموع ينضم للالتزامات: ${iqd(reqToday)}'),
              const SizedBox(height: 6),
              Text('الصافي بجيبك اليوم: ${iqd(net)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _saveDay,
                icon: const Icon(Icons.save),
                label: const Text('حفظ يومية اليوم بالسجل'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildObs() {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addObDialog,
        label: const Text('التزام جديد'),
        icon: const Icon(Icons.add),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _obs.length,
        itemBuilder: (ctx, i) {
          final o = _obs[i];
          return Card(
            color: const Color(0xFF1E293B),
            child: ListTile(
              title: Text('${o['title']} (الهدف: ${iqd(o['target'])})', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('المضموم: ${iqd(o['saved'])} | باقي: ${o['remDays']} يوم | القسط: ${iqd(_daily(o))}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Color(0xFF10B981)),
                    onPressed: () {
                      setState(() {
                        o['saved'] = 0;
                        o['remDays'] = o['days'];
                        o['skip'] = 0;
                      });
                      _save();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () {
                      setState(() => _obs.removeAt(i));
                      _save();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLogs() {
    if (_logs.isEmpty) return const Center(child: Text('السجل فارغ حالياً'));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _logs.length,
      itemBuilder: (ctx, i) {
        final l = _logs[i];
        return Card(
          color: const Color(0xFF1E293B),
          child: ExpansionTile(
            title: Text('الصافي: ${iqd(l['net'])} (${l['date']})', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
            subtitle: Text('الشغل: ${iqd(l['inc'])} | بانزين: ${iqd(l['exp'])} | للالتزامات: ${iqd(l['alloc'])}'),
            children: (l['notes'] as List).map((n) => ListTile(dense: true, title: Text('• $n'))).toList(),
          ),
        );
      },
    );
  }

  void _addObDialog() {
    final tCtrl = TextEditingController(), aCtrl = TextEditingController(), dCtrl = TextEditingController(text: '10');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة التزام جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: tCtrl, decoration: const InputDecoration(labelText: 'اسم الالتزام (دهن، سلفة...)')),
            TextField(controller: aCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ الكلي (د.ع)')),
            TextField(controller: dCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الأيام (الديدلاين)')),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              final amt = int.tryParse(aCtrl.text) ?? 0;
              final days = int.tryParse(dCtrl.text) ?? 10;
              if (tCtrl.text.isNotEmpty && amt > 0) {
                setState(() {
                  final id = DateTime.now().millisecondsSinceEpoch.toString();
                  _obs.add({'id': id, 'title': tCtrl.text, 'target': amt, 'saved': 0, 'days': days, 'remDays': days, 'skip': 0});
                  _checked[id] = true;
                });
                _save();
                Navigator.pop(ctx);
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }
}
