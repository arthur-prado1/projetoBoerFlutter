import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../model/produto_model.dart';
import '../services/carrinho_controller.dart';
import '../services/produto_service.dart';
import '../utils/currency_input_formatter.dart';
import '../widgets/foto_produto.dart';
import '../widgets/sino_notificacoes.dart';
import '../widgets/dialogo_endereco_api.dart';
import '../services/api_config.dart';
import '../services/notificacao_controller.dart';
import '../services/push_service.dart';

/// Gerenciamento de Produtos.
///
/// O login continua no Firebase Auth (a rota /produtos só abre autenticado),
/// e os dados dos produtos vêm da API REST (bin/server.dart).
class ProdutosScreen extends StatefulWidget {
  /// Permite injetar outro service (ex.: testes). Padrão: API REST local.
  final ProdutoService? service;

  const ProdutosScreen({super.key, this.service});

  @override
  State<ProdutosScreen> createState() => _ProdutosScreenState();
}

class _ProdutosScreenState extends State<ProdutosScreen> {
  late final ProdutoService _produtoService =
      widget.service ?? ProdutoService();

  List<ProdutoModel> _produtos = [];
  bool _carregando = true;
  String? _erro;

  // Tempo real: a API avisa por WebSocket quando um produto muda
  WebSocketChannel? _canal;
  StreamSubscription? _assinatura;
  Timer? _timerReconexao;
  bool _aoVivo = false;
  bool _jaConectou = false;
  static const Duration _intervaloReconexao = Duration(seconds: 3);

  // Estado da lupa de busca
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  static const int _limiteEstoqueBaixo = 5;

  // Fotos padrão: um clique preenche o link da foto do produto
  static const List<({String rotulo, String url})> _fotosPadrao = [
    (
      rotulo: 'Bola',
      url: 'https://images.unsplash.com/photo-1614632537190-23e4146777db?w=400',
    ),
    (
      rotulo: 'Raquete',
      url: 'https://images.unsplash.com/photo-1622279457486-62dcc4a431d6?w=400',
    ),
    (
      rotulo: 'Tênis',
      url: 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=400',
    ),
  ];

  final CarrinhoController _carrinho = CarrinhoController.instancia;

  @override
  void initState() {
    super.initState();
    _carregarProdutos();
    _conectarTempoReal();
    _carrinho.carregar(silencioso: true);
    ApiConfig.endereco.addListener(_aoMudarEnderecoApi);
  }

  // Trocou o endereço da API: recarrega a lista e reconecta o tempo real.
  void _aoMudarEnderecoApi() {
    if (!mounted) return;
    _carregarProdutos();
    _assinatura?.cancel();
    _canal?.sink.close();
    _agendarReconexao();
  }

  Future<void> _alterarEnderecoApi() async {
    final mudou = await abrirDialogoEnderecoApi(context);
    if (!mounted) return;
    if (!mudou && _erro != null) _carregarProdutos(); // tenta de novo mesmo assim
  }

  @override
  void dispose() {
    ApiConfig.endereco.removeListener(_aoMudarEnderecoApi);
    _timerReconexao?.cancel();
    _assinatura?.cancel();
    _canal?.sink.close();
    _searchController.dispose();
    super.dispose();
  }

  // Abre o WebSocket da API; se falhar ou cair, tenta de novo a cada 3 s.
  Future<void> _conectarTempoReal() async {
    _timerReconexao?.cancel();
    final canal = _produtoService.conectarTempoReal();
    try {
      await canal.ready;
    } catch (_) {
      _agendarReconexao();
      return;
    }
    if (!mounted) {
      canal.sink.close();
      return;
    }

    _canal = canal;
    _assinatura = canal.stream.listen(
      (mensagem) {
        if (mensagem is String) _aplicarEvento(mensagem);
      },
      onDone: _agendarReconexao,
      onError: (_) => _agendarReconexao(),
      cancelOnError: true,
    );
    setState(() => _aoVivo = true);

    // Ao reconectar, busca a lista de novo para pegar o que mudou enquanto
    // estava desconectado (ex.: a API reiniciou).
    if (_jaConectou || _erro != null) {
      _carregarProdutos(silencioso: true);
    }
    _jaConectou = true;
  }

  void _agendarReconexao() {
    _assinatura?.cancel();
    _assinatura = null;
    _canal = null;
    if (!mounted) return;
    if (_aoVivo) setState(() => _aoVivo = false);
    _timerReconexao?.cancel();
    _timerReconexao = Timer(_intervaloReconexao, _conectarTempoReal);
  }

  // Aplica na lista a alteração avisada pela API (sem precisar de F5).
  void _aplicarEvento(String mensagem) {
    final evento = EventoProduto.fromJson(mensagem);
    if (evento == null || !mounted) return;

    final produto = evento.produto;
    setState(() {
      final index = _produtos.indexWhere((p) => p.id == produto.id);
      switch (evento.tipo) {
        case TipoEventoProduto.criado:
        case TipoEventoProduto.atualizado:
          if (index == -1) {
            _produtos = [..._produtos, produto];
          } else {
            _produtos = [..._produtos]..[index] = produto;
          }
        case TipoEventoProduto.excluido:
          if (index != -1) {
            _produtos = [..._produtos]..removeAt(index);
          }
      }
    });
    // Se o produto está no carrinho, atualiza preço/estoque lá também.
    _carrinho.aoMudarProduto(produto);
  }

  IconData _iconeCategoria(String categoria) => iconeCategoria(categoria);

  // Adiciona 1 unidade ao carrinho (a API confere o estoque).
  Future<void> _adicionarAoCarrinho(ProdutoModel produto) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _carrinho.adicionar(produto);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('"${produto.nome}" adicionado ao carrinho'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
          // Avisos com botão não somem sozinhos por padrão no Flutter atual.
          persist: false,
          action: SnackBarAction(
            label: 'VER CARRINHO',
            textColor: Colors.white,
            onPressed: _abrirCarrinho,
          ),
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  void _abrirCarrinho() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    Navigator.pushNamed(context, '/carrinho');
  }

  // Ícone do carrinho com o número de itens
  Widget _buildBotaoCarrinho() {
    return ListenableBuilder(
      listenable: _carrinho,
      builder: (context, _) {
        final qtd = _carrinho.quantidadeItens;
        return IconButton(
          tooltip: 'Meu carrinho',
          onPressed: _abrirCarrinho,
          icon: Badge(
            isLabelVisible: qtd > 0,
            label: Text(qtd > 99 ? '99+' : '$qtd'),
            backgroundColor: Colors.orange.shade700,
            child: const Icon(Icons.shopping_cart_outlined),
          ),
        );
      },
    );
  }

  // Listar (Read) - GET /produtos
  // `silencioso`: atualiza sem mostrar carregamento (usado pelo tempo real).
  Future<void> _carregarProdutos({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    }
    try {
      final produtos = await _produtoService.getProdutos();
      if (!mounted) return;
      setState(() {
        _produtos = produtos;
        _carregando = false;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (silencioso) return; // Mantém a lista atual; o aviso "Reconectando" já aparece.
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  Future<void> _logout(BuildContext context) async {
    await PushService.instancia.parar(); // para de receber push neste celular
    NotificacaoController.instancia.parar();
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (Route<dynamic> route) => false,
      );
    }
  }

  // Formulário modal para Cadastrar (POST) ou Editar (PUT)
  void _abrirFormularioProduto({ProdutoModel? produtoExistente}) {
    final bool isEdicao = produtoExistente != null;
    final formKey = GlobalKey<FormState>();

    final nomeController =
        TextEditingController(text: produtoExistente?.nome ?? '');
    final precoController = TextEditingController(
      text: produtoExistente != null
          ? produtoExistente.preco.toStringAsFixed(2).replaceAll('.', ',')
          : '',
    );
    final quantidadeController = TextEditingController(
      text: produtoExistente?.quantidade.toString() ?? '',
    );
    final imagemController =
        TextEditingController(text: produtoExistente?.imagemUrl ?? '');

    // Mantém a categoria atual mesmo que ela não esteja na lista padrão
    // (ex.: um produto cadastrado pelo Postman).
    final categorias = iconesCategorias.keys.toList();
    String categoria = produtoExistente?.categoria.trim() ?? categorias.first;
    if (categoria.isEmpty) categoria = 'Outros';
    if (!categorias.contains(categoria)) categorias.insert(0, categoria);

    bool salvando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Cabeçalho do modal
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isEdicao ? 'Editar Produto' : 'Novo Produto',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const Divider(),
                      const SizedBox(height: 10),

                      // Campo 1: Nome
                      TextFormField(
                        controller: nomeController,
                        decoration: const InputDecoration(
                          labelText: 'Nome do Produto',
                          hintText: 'Ex: Bola de Futebol Society',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Informe o nome do produto';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Campo 2: Categoria
                      DropdownButtonFormField<String>(
                        initialValue: categoria,
                        decoration: const InputDecoration(
                          labelText: 'Categoria',
                          prefixIcon: Icon(Icons.category),
                          border: OutlineInputBorder(),
                        ),
                        items: categorias
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Row(
                                    children: [
                                      Icon(_iconeCategoria(c),
                                          size: 18, color: Colors.green),
                                      const SizedBox(width: 8),
                                      Text(c),
                                    ],
                                  ),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => categoria = val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),

                      // Campos 3 e 4: Preço e Quantidade lado a lado
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: precoController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                CurrencyInputFormatter(),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Preço',
                                hintText: '0,00',
                                prefixText: 'R\$ ',
                                prefixIcon: Icon(Icons.attach_money),
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Informe o preço';
                                }
                                final parsed = parseMoeda(v);
                                if (parsed == null || parsed <= 0) {
                                  return 'Maior que R\$ 0,00';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: quantidadeController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Estoque',
                                hintText: '0',
                                prefixIcon: Icon(Icons.numbers),
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Informe a qtd.';
                                }
                                if (int.tryParse(v.trim()) == null) {
                                  return 'Número inválido';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Campo 5: Foto do produto por link
                      TextFormField(
                        controller: imagemController,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: 'Link da Foto (opcional)',
                          hintText: 'https://...',
                          prefixIcon: const Icon(Icons.image_outlined),
                          suffixIcon: imagemController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  tooltip: 'Remover foto',
                                  onPressed: () {
                                    imagemController.clear();
                                    setModalState(() {});
                                  },
                                )
                              : null,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setModalState(() {}),
                        validator: (v) {
                          final texto = v?.trim() ?? '';
                          if (texto.isEmpty) return null;
                          final uri = Uri.tryParse(texto);
                          if (uri == null ||
                              !(uri.scheme == 'http' || uri.scheme == 'https') ||
                              uri.host.isEmpty) {
                            return 'Informe um link começando com http:// ou https://';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),

                      // Fotos padrão + prévia
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Fotos padrão (toque para usar)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _fotosPadrao.map((foto) {
                                    final selecionada =
                                        imagemController.text.trim() ==
                                            foto.url;
                                    return Tooltip(
                                      message: 'Usar foto: ${foto.rotulo}',
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () {
                                          imagemController.text = foto.url;
                                          setModalState(() {});
                                        },
                                        child: Column(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: selecionada
                                                      ? Colors.green
                                                      : Colors.grey.shade300,
                                                  width: selecionada ? 2.5 : 1,
                                                ),
                                              ),
                                              child: _buildFoto(
                                                foto.url,
                                                tamanho: 56,
                                                raio: 9,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              foto.rotulo,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: selecionada
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                color: selecionada
                                                    ? Colors.green.shade800
                                                    : Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            children: [
                              Text(
                                'Prévia',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              _buildFoto(
                                imagemController.text.trim(),
                                tamanho: 84,
                                raio: 14,
                                categoria: categoria,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Botão de Ação (Salvar / Atualizar)
                      ElevatedButton.icon(
                        onPressed: salvando
                            ? null
                            : () async {
                                if (!(formKey.currentState?.validate() ??
                                    false)) {
                                  return;
                                }

                                setModalState(() => salvando = true);

                                final messenger = ScaffoldMessenger.of(context);
                                try {
                                  final produto = ProdutoModel(
                                    id: produtoExistente?.id,
                                    nome: nomeController.text.trim(),
                                    categoria: categoria,
                                    preco: parseMoeda(precoController.text)!,
                                    quantidade: int.parse(
                                        quantidadeController.text.trim()),
                                    imagemUrl: imagemController.text.trim(),
                                  );

                                  if (isEdicao) {
                                    await _produtoService
                                        .updateProduto(produto);
                                  } else {
                                    await _produtoService
                                        .createProduto(produto);
                                  }

                                  if (ctx.mounted) {
                                    Navigator.of(ctx).pop();
                                  }
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(isEdicao
                                          ? 'Produto atualizado com sucesso!'
                                          : 'Produto cadastrado com sucesso!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                  await _carregarProdutos();
                                } catch (e) {
                                  setModalState(() => salvando = false);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('Erro ao salvar: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                        icon: salvando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(isEdicao ? Icons.save : Icons.add),
                        label: Text(
                          salvando
                              ? 'Salvando...'
                              : (isEdicao
                                  ? 'SALVAR ALTERAÇÕES'
                                  : 'CADASTRAR PRODUTO'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Diálogo de confirmação para Excluir (DELETE)
  void _confirmarExclusao(ProdutoModel produto) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('Excluir Produto'),
            ],
          ),
          content: Text(
            'Tem certeza que deseja excluir "${produto.nome}"? Esta ação não pode ser desfeita.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                final messenger = ScaffoldMessenger.of(context);
                try {
                  if (produto.id != null) {
                    await _produtoService.deleteProduto(produto.id!);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Produto excluído com sucesso!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    await _carregarProdutos();
                  }
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Erro ao excluir: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('EXCLUIR'),
            ),
          ],
        );
      },
    );
  }

  // Cartão de uma métrica do dashboard
  Widget _buildMetrica({
    required IconData icone,
    required String valor,
    required String titulo,
    required String subtitulo,
    Color cor = Colors.green,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(cor.withValues(alpha: 0.07), Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icone, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    valor,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: cor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          Text(
            subtitulo,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // Dashboard: total de produtos, itens em estoque e valor do estoque
  Widget _buildDashboardMetrics(List<ProdutoModel> produtos) {
    final int totalProdutos = produtos.length;
    final int totalItens =
        produtos.fold<int>(0, (sum, p) => sum + p.quantidade);
    final double valorEstoque =
        produtos.fold<double>(0.0, (sum, p) => sum + p.preco * p.quantidade);
    final int estoqueBaixo =
        produtos.where((p) => p.quantidade <= _limiteEstoqueBaixo).length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_outlined,
                  color: Colors.green, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Dashboard do Estoque',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              _buildSeloTempoReal(),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildMetrica(
                  icone: Icons.inventory_2_outlined,
                  valor: '$totalProdutos',
                  titulo: 'Produtos',
                  subtitulo: 'Cadastrados',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetrica(
                  icone: Icons.layers_outlined,
                  valor: '$totalItens',
                  titulo: 'Itens',
                  subtitulo: 'Em estoque',
                  cor: Colors.teal,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetrica(
                  icone: Icons.warning_amber_rounded,
                  valor: '$estoqueBaixo',
                  titulo: 'Estoque baixo',
                  subtitulo: 'Até $_limiteEstoqueBaixo un.',
                  cor: estoqueBaixo > 0 ? Colors.orange : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Valor total em estoque',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  formatarMoeda(valorEstoque),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Selo "Ao vivo" / "Reconectando" do canal de tempo real
  Widget _buildSeloTempoReal() {
    final cor = _aoVivo ? Colors.green.shade800 : Colors.orange.shade800;
    return Tooltip(
      message: _aoVivo
          ? 'Conectado à API: alterações aparecem na hora, sem F5'
          : 'Sem conexão em tempo real com a API. Tentando reconectar...',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: cor),
            const SizedBox(width: 5),
            Text(
              _aoVivo ? 'API REST • Ao vivo' : 'API REST • Reconectando',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: cor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Estado de erro (ex.: API fora do ar)
  Widget _buildErro() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 12),
            const Text(
              'Não foi possível carregar os produtos',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _erro ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _carregarProdutos,
              icon: const Icon(Icons.refresh),
              label: const Text('TENTAR NOVAMENTE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _alterarEnderecoApi,
              icon: const Icon(Icons.dns_outlined),
              label: const Text('ALTERAR ENDEREÇO DA API'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
            ),
          ],
        ),
      ),
    );
  }

  // Foto do produto pelo link; sem link ou com link quebrado mostra o ícone
  // da categoria.
  Widget _buildFoto(
    String url, {
    required double tamanho,
    double raio = 12,
    String categoria = '',
  }) =>
      FotoProduto(url, tamanho: tamanho, raio: raio, categoria: categoria);

  // Botão "adicionar ao carrinho" + quantas unidades já estão no carrinho
  Widget _buildAcaoCarrinho(ProdutoModel produto) {
    return ListenableBuilder(
      listenable: _carrinho,
      builder: (context, _) {
        final id = produto.id ?? '';
        final noCarrinho = _carrinho.quantidadeDe(id);
        final ocupado = _carrinho.ocupado(id);
        final semEstoque = noCarrinho >= produto.quantidade;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              tooltip: produto.quantidade == 0
                  ? 'Esgotado'
                  : semEstoque
                      ? 'Todo o estoque já está no seu carrinho'
                      : 'Adicionar ao carrinho',
              onPressed: ocupado || semEstoque
                  ? null
                  : () => _adicionarAoCarrinho(produto),
              icon: ocupado
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_shopping_cart, size: 20),
            ),
            if (noCarrinho > 0)
              Text(
                '$noCarrinho no carrinho',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                ),
              ),
          ],
        );
      },
    );
  }

  // Selo de estoque (verde / laranja / vermelho)
  Widget _buildSeloEstoque(int quantidade) {
    final Color cor;
    final String texto;
    if (quantidade == 0) {
      cor = Colors.red;
      texto = 'Esgotado';
    } else if (quantidade <= _limiteEstoqueBaixo) {
      cor = Colors.orange.shade800;
      texto = '$quantidade un. • baixo';
    } else {
      cor = Colors.green.shade800;
      texto = '$quantidade un.';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: cor,
        ),
      ),
    );
  }

  Widget _buildCardProduto(ProdutoModel produto) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _buildFoto(
              produto.imagemUrl,
              tamanho: 72,
              raio: 12,
              categoria: produto.categoria,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    produto.nome,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    produto.categoria.isEmpty ? 'Sem categoria' : produto.categoria,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        formatarMoeda(produto.preco),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      _buildSeloEstoque(produto.quantidade),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID: ${produto.id ?? ""}',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            // Botão Adicionar ao Carrinho
            _buildAcaoCarrinho(produto),
            const SizedBox(width: 4),
            // Botão Editar (PUT)
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.blueGrey),
              tooltip: 'Editar Produto',
              onPressed: () =>
                  _abrirFormularioProduto(produtoExistente: produto),
            ),
            // Botão Excluir (DELETE)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Excluir Produto',
              onPressed: () => _confirmarExclusao(produto),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConteudo() {
    if (_carregando && _produtos.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.green),
      );
    }

    if (_erro != null) {
      return _buildErro();
    }

    // Filtro aplicado pela Lupa de Busca
    final termo = _searchQuery.trim().toLowerCase();
    final produtos = _produtos.where((p) {
      if (termo.isEmpty) return true;
      return p.nome.toLowerCase().contains(termo) ||
          p.categoria.toLowerCase().contains(termo);
    }).toList();

    return RefreshIndicator(
      color: Colors.green,
      onRefresh: _carregarProdutos,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          _buildDashboardMetrics(_produtos),

          // Cabeçalho da Lista com Status da Busca
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Produtos Cadastrados',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    if (termo.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${produtos.length} encontrado(s)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (termo.isNotEmpty)
                  InkWell(
                    onTap: () {
                      setState(() {
                        _searchQuery = '';
                        _searchController.clear();
                      });
                    },
                    child: const Row(
                      children: [
                        Icon(Icons.clear, size: 14, color: Colors.redAccent),
                        SizedBox(width: 2),
                        Text(
                          'Limpar busca',
                          style:
                              TextStyle(fontSize: 12, color: Colors.redAccent),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    '${_produtos.length} no total',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),

          if (produtos.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    termo.isNotEmpty
                        ? Icons.search_off_rounded
                        : Icons.inventory_2_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    termo.isNotEmpty
                        ? 'Nenhum produto encontrado para "$_searchQuery"'
                        : 'Nenhum produto cadastrado no momento',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (termo.isEmpty)
                    ElevatedButton.icon(
                      onPressed: () => _abrirFormularioProduto(),
                      icon: const Icon(Icons.add),
                      label: const Text('Cadastrar Primeiro Produto'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: produtos.map(_buildCardProduto).toList(),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F7),
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: 'Pesquisar por nome ou categoria...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              )
            : const Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Gerenciamento de Produtos',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Fechar pesquisa',
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Pesquisar produtos',
              onPressed: () => setState(() => _isSearching = true),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Recarregar da API',
              onPressed: _carregando ? null : _carregarProdutos,
            ),
          ],
          const SinoNotificacoes(),
          _buildBotaoCarrinho(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Mais opções',
            onSelected: (value) {
              if (value == 'api') {
                _alterarEnderecoApi();
              } else if (value == 'sair') {
                _logout(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'api',
                child: Row(
                  children: [
                    Icon(Icons.dns_outlined, color: Colors.green, size: 20),
                    SizedBox(width: 10),
                    Text('Endereço da API'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'sair',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.redAccent, size: 20),
                    SizedBox(width: 10),
                    Text(
                      'Sair',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: _carregando && _produtos.isNotEmpty
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: Colors.white,
                  backgroundColor: Colors.green,
                ),
              )
            : null,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 2, // Produtos é a aba 2
        onDestinationSelected: (idx) {
          if (idx == 0) {
            Navigator.pushReplacementNamed(context, '/home');
          } else if (idx == 1) {
            Navigator.pushReplacementNamed(context, '/quadras');
          }
        },
        indicatorColor: Colors.green.shade100,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: Colors.green),
            label: 'Perfil',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: Colors.green),
            label: 'Quadras',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2, color: Colors.green),
            label: 'Produtos',
          ),
        ],
      ),
      floatingActionButton: _erro == null
          ? FloatingActionButton.extended(
              onPressed: () => _abrirFormularioProduto(),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text(
                'Novo Produto',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          : null,
      body: SafeArea(child: _buildConteudo()),
    );
  }
}
