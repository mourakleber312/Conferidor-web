import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isEmpty || key.isEmpty) {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Configure SUPABASE_URL e SUPABASE_ANON_KEY no build.')))));
    return;
  }
  await Supabase.initialize(url: url, anonKey: key);
  runApp(const FinanceApp());
}

final db = Supabase.instance.client;
final brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
String dateText(dynamic raw) {
  final date = DateTime.tryParse('${raw ?? ''}');
  return date == null ? '—' : DateFormat('dd/MM/yyyy').format(date);
}
String iso(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
DateTime monthShift(DateTime base, int months) {
  final monthIndex = base.year * 12 + base.month - 1 + months;
  final year = monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, base.day > last ? last : base.day);
}
String errorText(Object error) {
  if (error is AuthException) return error.message;
  if (error is PostgrestException) return error.message;
  return error.toString();
}

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Conferidor Web',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1769aa)), useMaterial3: true),
    home: const AuthGate(),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}
class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    db.auth.onAuthStateChange.listen((_) { if (mounted) setState(() {}); });
  }
  @override
  Widget build(BuildContext context) => db.auth.currentUser == null ? const LoginPage() : const HomePage();
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  Future<void> submit({required bool signup}) async {
    setState(() => loading = true);
    try {
      if (signup) {
        await db.auth.signUp(email: email.text.trim(), password: password.text);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cadastro enviado. Confirme seu e-mail, se solicitado, e entre.')));
      } else {
        await db.auth.signInWithPassword(email: email.text.trim(), password: password.text);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 420),
    child: Card(margin: const EdgeInsets.all(20), child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.account_balance_wallet_outlined, size: 48),
      const SizedBox(height: 10),
      const Text('Conferidor de Faturas Web', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail')),
      TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Senha (mínimo 6 caracteres)')),
      const SizedBox(height: 22),
      FilledButton(onPressed: loading ? null : () => submit(signup: false), child: const Text('Entrar')),
      TextButton(onPressed: loading ? null : () => submit(signup: true), child: const Text('Criar conta')),
    ]))))));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> expenses = [];
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> households = [];
  bool loading = true;
  String view = 'Todas';
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String? selectedHousehold;
  @override
  void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    setState(() => loading = true);
    try {
      final h = await db.from('households').select('id,name').order('created_at');
      final c = await db.from('categories').select('id,name,household_id').order('name');
      final e = await db.from('expenses').select('id,description,amount,scope,owner_id,household_id,category_id,payment_method,installment_number,installment_count,due_date,purchase_date,paid,recurrence_group_id').order('due_date', ascending: false);
      if (!mounted) return;
      setState(() {
        households = List<Map<String, dynamic>>.from(h);
        categories = List<Map<String, dynamic>>.from(c);
        expenses = List<Map<String, dynamic>>.from(e);
        if (selectedHousehold != null && !households.any((x) => x['id'] == selectedHousehold)) selectedHousehold = null;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar: ${errorText(e)}')));
    } finally { if (mounted) setState(() => loading = false); }
  }
  String categoryName(dynamic id) {
    for (final c in categories) { if (c['id'] == id) return '${c['name']}'; }
    return 'Sem classificação';
  }
  Future<void> openExpense() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => ExpenseDialog(categories: categories, households: households));
    if (ok == true) await refresh();
  }
  Future<void> addCategory() async {
    final controller = TextEditingController();
    String scope = 'individual';
    String? household = households.isEmpty ? null : '${households.first['id']}';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
      title: const Text('Nova classificação'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: controller, decoration: const InputDecoration(labelText: 'Nome')),
        DropdownButtonFormField<String>(initialValue: scope, items: const [DropdownMenuItem(value: 'individual', child: Text('Só minha')), DropdownMenuItem(value: 'compartilhada', child: Text('Compartilhada'))], onChanged: (v) => update(() => scope = v!)),
        if (scope == 'compartilhada') DropdownButtonFormField<String>(initialValue: household, decoration: const InputDecoration(labelText: 'Grupo'), items: households.map((h) => DropdownMenuItem(value: '${h['id']}', child: Text('${h['name']}'))).toList(), onChanged: (v) => update(() => household = v)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar'))],
    )));
    if (ok != true || controller.text.trim().isEmpty) return;
    try {
      if (scope == 'compartilhada' && household == null) throw Exception('Crie ou entre em um grupo antes de criar categorias compartilhadas.');
      await db.from('categories').insert({'name': controller.text.trim(), 'owner_id': db.auth.currentUser!.id, 'household_id': scope == 'compartilhada' ? household : null});
      await refresh();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e)))); }
  }
  Future<void> createGroup() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Criar grupo compartilhado'),
      content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Nome do grupo (ex.: Família)')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Criar'))],
    ));
    if (ok != true || controller.text.trim().isEmpty) return;
    try {
      await db.rpc('create_household', params: {'p_name': controller.text.trim()});
      await refresh();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e)))); }
  }
  Future<void> joinGroup() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Entrar em grupo'),
      content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Código de convite recebido')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Entrar'))],
    ));
    if (ok != true) return;
    try { await db.rpc('join_household', params: {'p_code': controller.text.trim()}); await refresh(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e)))); }
  }
  Future<void> showInvite() async {
    try {
      final list = await db.from('households').select('name,invite_code');
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: const Text('Códigos dos meus grupos'), content: Column(mainAxisSize: MainAxisSize.min, children: [for (final h in list) ListTile(title: Text('${h['name']}'), subtitle: Text('${h['invite_code']}'), trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () { Clipboard.setData(ClipboardData(text: '${h['invite_code']}')); ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Código copiado'))); }))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))]));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e)))); }
  }
  Future<void> togglePaid(Map<String, dynamic> e) async {
    try { await db.from('expenses').update({'paid': e['paid'] != true}).eq('id', e['id']); await refresh(); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(error)))); }
  }
  Future<void> deleteExpense(Map<String, dynamic> e) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Excluir lançamento?'), content: const Text('Apenas esta parcela/ocorrência será excluída.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir'))]));
    if (yes != true) return;
    try { await db.from('expenses').delete().eq('id', e['id']); await refresh(); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(error)))); }
  }
  @override
  Widget build(BuildContext context) {
    final shown = expenses.where((e) {
      final d = DateTime.tryParse('${e['due_date']}');
      return d != null && d.year == month.year && d.month == month.month &&
        (view == 'Todas' || (view == 'Individuais' && e['scope'] == 'individual') || (view == 'Compartilhadas' && e['scope'] == 'shared'));
    }).toList();
    final total = shown.fold<double>(0, (s, e) => s + (e['amount'] as num).toDouble());
    final pending = shown.where((e) => e['paid'] != true).fold<double>(0, (s, e) => s + (e['amount'] as num).toDouble());
    return Scaffold(
      appBar: AppBar(title: const Text('Conferidor Web'), actions: [IconButton(tooltip: 'Atualizar', onPressed: refresh, icon: const Icon(Icons.refresh)), IconButton(tooltip: 'Sair', onPressed: () => db.auth.signOut(), icon: const Icon(Icons.logout))]),
      body: loading ? const Center(child: CircularProgressIndicator()) : Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000), child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Conta: ${db.auth.currentUser?.email ?? ''}', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: openExpense, icon: const Icon(Icons.add), label: const Text('Nova despesa')),
          OutlinedButton.icon(onPressed: addCategory, icon: const Icon(Icons.category_outlined), label: const Text('Nova classificação')),
          OutlinedButton.icon(onPressed: createGroup, icon: const Icon(Icons.group_add), label: const Text('Criar grupo')),
          OutlinedButton.icon(onPressed: joinGroup, icon: const Icon(Icons.login), label: const Text('Entrar em grupo')),
          OutlinedButton.icon(onPressed: showInvite, icon: const Icon(Icons.key), label: const Text('Ver convite')),
        ]),
        const SizedBox(height: 16),
        Row(children: [IconButton(onPressed: () => setState(() => month = monthShift(month, -1)), icon: const Icon(Icons.chevron_left)), Expanded(child: Center(child: Text(DateFormat('MMMM yyyy', 'pt_BR').format(month), style: Theme.of(context).textTheme.titleMedium))), IconButton(onPressed: () => setState(() => month = monthShift(month, 1)), icon: const Icon(Icons.chevron_right))]),
        DropdownButtonFormField<String>(initialValue: view, decoration: const InputDecoration(labelText: 'Visualização'), items: ['Todas', 'Individuais', 'Compartilhadas'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), onChanged: (v) => setState(() => view = v!)),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Total do mês'), Text(brl.format(total), style: Theme.of(context).textTheme.headlineSmall)]))), Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Pendente'), Text(brl.format(pending), style: Theme.of(context).textTheme.headlineSmall)])))]),
        const SizedBox(height: 12),
        if (shown.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Nenhuma despesa neste mês.')),
        for (final e in shown) Card(child: ListTile(
          leading: Icon(e['scope'] == 'shared' ? Icons.people_outline : Icons.lock_outline),
          title: Text('${e['description']} — ${brl.format(e['amount'])}'),
          subtitle: Text('${categoryName(e['category_id'])} • ${dateText(e['due_date'])} • ${e['payment_method']} • ${e['installment_number']}/${e['installment_count']} • ${e['paid'] == true ? 'Pago' : 'Pendente'}'),
          trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'paid') togglePaid(e); if (v == 'delete') deleteExpense(e); }, itemBuilder: (_) => [PopupMenuItem(value: 'paid', child: Text(e['paid'] == true ? 'Marcar pendente' : 'Marcar pago')), const PopupMenuItem(value: 'delete', child: Text('Excluir ocorrência'))]),
        )),
        const SizedBox(height: 12),
        const Text('Privacidade: despesas individuais são visíveis somente ao proprietário; compartilhadas são acessíveis aos integrantes do grupo.', style: TextStyle(fontSize: 12)),
      ]))),
    );
  }
}

class ExpenseDialog extends StatefulWidget {
  const ExpenseDialog({super.key, required this.categories, required this.households});
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> households;
  @override
  State<ExpenseDialog> createState() => _ExpenseDialogState();
}
class _ExpenseDialogState extends State<ExpenseDialog> {
  final description = TextEditingController();
  final amount = TextEditingController();
  String scope = 'individual';
  String method = 'credito';
  String condition = 'vista';
  String recurrence = 'unica';
  int installments = 1;
  int months = 12;
  bool paid = false;
  String? category;
  String? household;
  DateTime purchase = DateTime.now();
  DateTime due = DateTime.now();
  bool saving = false;
  @override
  void initState() {
    super.initState();
    if (widget.households.isNotEmpty) household = '${widget.households.first['id']}';
  }
  Future<void> pickDate(bool isPurchase) async {
    final current = isPurchase ? purchase : due;
    final selected = await showDatePicker(context: context, initialDate: current, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (selected != null) setState(() { if (isPurchase) { purchase = selected; } else { due = selected; } });
  }
  Future<void> save() async {
    if (description.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe a descrição.'))); return; }
    final value = double.tryParse(amount.text.trim().replaceAll('.', '').replaceAll(',', '.'));
    if (value == null || value <= 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe um valor válido (ex.: 1200,50).'))); return; }
    if (scope == 'shared' && household == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Crie ou entre em um grupo para compartilhar despesas.'))); return; }
    final count = recurrence == 'mensal' ? months : (condition == 'parcelado' ? installments : 1);
    final totalCents = (value * 100).round();
    final groupId = const Uuid().v4();
    final userId = db.auth.currentUser!.id;
    final records = <Map<String, dynamic>>[];
    for (var i = 0; i < count; i++) {
      final cents = recurrence == 'mensal' ? totalCents : totalCents ~/ count + (i < totalCents % count ? 1 : 0);
      records.add({
        'description': description.text.trim(), 'amount': cents / 100,
        'scope': scope, 'owner_id': userId, 'household_id': scope == 'shared' ? household : null,
        'category_id': category, 'payment_method': method, 'purchase_date': iso(purchase),
        'due_date': iso(monthShift(due, i)), 'paid': i == 0 && paid,
        'installment_number': i + 1, 'installment_count': count,
        'recurrence_group_id': groupId, 'recurrence_type': recurrence,
      });
    }
    setState(() => saving = true);
    try {
      await db.from('expenses').insert(records);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: ${errorText(e)}')));
    } finally { if (mounted) setState(() => saving = false); }
  }
  @override
  Widget build(BuildContext context) {
    final allowed = widget.categories.where((c) => scope == 'individual' ? c['household_id'] == null : c['household_id'] == household).toList();
    final selectedCategory = allowed.any((c) => c['id'] == category) ? category : null;
    return Dialog(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Nova despesa', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      TextField(controller: description, decoration: const InputDecoration(labelText: 'Descrição')),
      TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Valor total (R\$)', hintText: '1200,50')),
      DropdownButtonFormField<String>(initialValue: scope, decoration: const InputDecoration(labelText: 'Visibilidade'), items: const [DropdownMenuItem(value: 'individual', child: Text('Individual (privada)')), DropdownMenuItem(value: 'shared', child: Text('Compartilhada'))], onChanged: (v) => setState(() { scope = v!; category = null; })),
      if (scope == 'shared') DropdownButtonFormField<String>(initialValue: household, decoration: const InputDecoration(labelText: 'Grupo compartilhado'), items: widget.households.map((h) => DropdownMenuItem(value: '${h['id']}', child: Text('${h['name']}'))).toList(), onChanged: (v) => setState(() { household = v; category = null; })),
      DropdownButtonFormField<String>(key: ValueKey('$scope:$household:$selectedCategory'), initialValue: selectedCategory, decoration: const InputDecoration(labelText: 'Classificação (opcional)'), items: [const DropdownMenuItem<String>(value: null, child: Text('Sem classificação')), ...allowed.map((c) => DropdownMenuItem(value: '${c['id']}', child: Text('${c['name']}')))], onChanged: (v) => setState(() => category = v)),
      DropdownButtonFormField<String>(initialValue: method, decoration: const InputDecoration(labelText: 'Forma de pagamento'), items: const [DropdownMenuItem(value: 'credito', child: Text('Cartão de crédito')), DropdownMenuItem(value: 'pix', child: Text('Pix')), DropdownMenuItem(value: 'dinheiro', child: Text('Dinheiro'))], onChanged: (v) => setState(() => method = v!)),
      DropdownButtonFormField<String>(initialValue: recurrence, decoration: const InputDecoration(labelText: 'Tipo de lançamento'), items: const [DropdownMenuItem(value: 'unica', child: Text('Compra / conta única')), DropdownMenuItem(value: 'mensal', child: Text('Conta fixa mensal (gerar meses futuros)'))], onChanged: (v) => setState(() { recurrence = v!; if (recurrence == 'mensal') condition = 'vista'; })),
      if (recurrence == 'unica') DropdownButtonFormField<String>(initialValue: condition, decoration: const InputDecoration(labelText: 'Condição'), items: const [DropdownMenuItem(value: 'vista', child: Text('À vista')), DropdownMenuItem(value: 'parcelado', child: Text('Parcelado'))], onChanged: (v) => setState(() => condition = v!)),
      if (recurrence == 'unica' && condition == 'parcelado') DropdownButtonFormField<int>(initialValue: installments, decoration: const InputDecoration(labelText: 'Quantidade de parcelas'), items: List.generate(60, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}x'))), onChanged: (v) => setState(() => installments = v!)),
      if (recurrence == 'mensal') DropdownButtonFormField<int>(initialValue: months, decoration: const InputDecoration(labelText: 'Gerar quantos meses?'), items: [3, 6, 12, 24, 36].map((n) => DropdownMenuItem(value: n, child: Text('$n meses'))).toList(), onChanged: (v) => setState(() => months = v!)),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Data da compra'), subtitle: Text(dateText(iso(purchase))), trailing: const Icon(Icons.calendar_today), onTap: () => pickDate(true)),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Primeiro vencimento'), subtitle: Text(dateText(iso(due))), trailing: const Icon(Icons.calendar_month), onTap: () => pickDate(false)),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Primeira ocorrência já paga'), value: paid, onChanged: (v) => setState(() => paid = v)),
      if (recurrence == 'mensal') const Text('Contas fixas geram ocorrências mensais com o mesmo valor inicial. Cada ocorrência pode ser marcada como paga; edição do valor ficará para a próxima etapa.', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [TextButton(onPressed: saving ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')), const SizedBox(width: 8), FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Salvando...' : 'Salvar'))]),
    ]))));
  }
}
