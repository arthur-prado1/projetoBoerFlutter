import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/api_config.dart';

/// Testa se há uma API do eQuadras respondendo no endereço.
/// Retorna null se deu certo, ou a mensagem de erro.
Future<String?> testarEnderecoApi(String endereco, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c
        .get(Uri.parse('$endereco/produtos'))
        .timeout(const Duration(seconds: 5));
    if (r.statusCode != 200) return 'A API respondeu com erro ${r.statusCode}.';
    final corpo = jsonDecode(utf8.decode(r.bodyBytes));
    if (corpo is! List) return 'Esse endereço respondeu, mas não parece ser a API do eQuadras.';
    return null;
  } on TimeoutException {
    return 'Sem resposta. Confira o IP, se a API está rodando e se o celular está na mesma rede.';
  } catch (_) {
    return 'Não foi possível conectar. Confira o IP e se a API está rodando no PC.';
  } finally {
    if (client == null) c.close();
  }
}

/// Janela para ver/trocar o endereço da API. Retorna true se mudou.
Future<bool> abrirDialogoEnderecoApi(BuildContext context) async {
  final mudou = await showDialog<bool>(
    context: context,
    builder: (_) => const _DialogoEnderecoApi(),
  );
  return mudou ?? false;
}

class _DialogoEnderecoApi extends StatefulWidget {
  const _DialogoEnderecoApi();

  @override
  State<_DialogoEnderecoApi> createState() => _DialogoEnderecoApiState();
}

class _DialogoEnderecoApiState extends State<_DialogoEnderecoApi> {
  late final TextEditingController _campo =
      TextEditingController(text: ApiConfig.url);
  bool _testando = false;
  bool _salvando = false;
  String? _resultado;
  bool _ok = false;

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  Future<void> _testar() async {
    final endereco = ApiConfig.normalizar(_campo.text);
    if (endereco == null) {
      setState(() {
        _ok = false;
        _resultado = 'Endereço inválido. Exemplo: 192.168.0.10:8080';
      });
      return;
    }
    setState(() {
      _testando = true;
      _resultado = null;
    });
    final erro = await testarEnderecoApi(endereco);
    if (!mounted) return;
    setState(() {
      _testando = false;
      _ok = erro == null;
      _resultado = erro ?? 'Conectado! A API respondeu em $endereco';
    });
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      final anterior = ApiConfig.url;
      final salvo = await ApiConfig.salvar(_campo.text);
      if (!mounted) return;
      Navigator.of(context).pop(salvo != anterior);
    } on FormatException catch (e) {
      setState(() {
        _salvando = false;
        _ok = false;
        _resultado = e.message;
      });
    }
  }

  Future<void> _restaurar() async {
    await ApiConfig.restaurarPadrao();
    if (!mounted) return;
    setState(() {
      _campo.text = ApiConfig.url;
      _resultado = 'Voltou para o padrão: ${ApiConfig.url}';
      _ok = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.dns_outlined, color: Colors.green),
          SizedBox(width: 8),
          Text('Endereço da API'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Produtos, carrinho e notificações vêm da API que roda no PC. '
              'Se o IP do PC mudar, troque aqui — não precisa reinstalar o app.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _campo,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'IP e porta da API',
                hintText: '192.168.0.10:8080',
                prefixIcon: Icon(Icons.lan_outlined),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _resultado = null),
              onSubmitted: (_) => _testar(),
            ),
            const SizedBox(height: 8),
            Text(
              'Dica: no PC, rode "ipconfig" e use o "Endereço IPv4" da rede '
              '(Wi-Fi ou Ethernet). O celular precisa estar na mesma rede.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            if (_resultado != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _ok ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _ok ? Icons.check_circle_outline : Icons.error_outline,
                      size: 18,
                      color: _ok ? Colors.green.shade800 : Colors.red.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_resultado!, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : _restaurar,
          child: const Text('PADRÃO'),
        ),
        TextButton.icon(
          onPressed: _testando || _salvando ? null : _testar,
          icon: _testando
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wifi_find_outlined, size: 18),
          label: const Text('TESTAR'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          onPressed: _salvando ? null : _salvar,
          child: const Text('SALVAR'),
        ),
      ],
    );
  }
}
