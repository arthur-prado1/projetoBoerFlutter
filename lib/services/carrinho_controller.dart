import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../model/carrinho_model.dart';
import '../model/produto_model.dart';
import 'api_config.dart';
import 'carrinho_service.dart';
import 'produto_service.dart' show ProdutoApiException;

/// Estado do carrinho compartilhado entre as telas (contador no ícone,
/// tela de produtos e tela do carrinho).
///
/// O carrinho pertence ao usuário logado no Firebase Auth (uid) e fica
/// guardado pela API no Firestore, em carrinhos/{uid}.
class CarrinhoController extends ChangeNotifier {
  static final CarrinhoController instancia = CarrinhoController();

  CarrinhoService servico;

  /// Quem é o usuário atual. Pode ser trocado (ex.: testes, prévia sem login).
  String? Function() uidAtual = () => FirebaseAuth.instance.currentUser?.uid;

  CarrinhoController({CarrinhoService? servico})
      : servico = servico ?? CarrinhoService() {
    // Trocou o endereço da API: busca o carrinho na API nova.
    ApiConfig.endereco.addListener(() {
      if (_uidCarregado != null) carregar(silencioso: true);
    });
  }

  CarrinhoModel _carrinho = const CarrinhoModel();
  bool _carregando = false;
  String? _erro;
  String? _uidCarregado;

  /// IDs de produtos com uma ação em andamento (para travar botões).
  final Set<String> _ocupados = {};

  CarrinhoModel get carrinho => _carrinho;
  bool get carregando => _carregando;
  String? get erro => _erro;
  int get quantidadeItens => _carrinho.quantidadeItens;
  bool ocupado(String produtoId) => _ocupados.contains(produtoId);
  int quantidadeDe(String produtoId) => _carrinho.quantidadeDe(produtoId);

  String _uid() {
    final uid = uidAtual();
    if (uid == null || uid.isEmpty) {
      throw ProdutoApiException('Faça login para usar o carrinho.');
    }
    if (uid != _uidCarregado) {
      // Trocou de usuário: não mostra o carrinho de outra pessoa.
      _uidCarregado = uid;
      _carrinho = const CarrinhoModel();
    }
    return uid;
  }

  /// Busca o carrinho na API. `silencioso` não mostra carregamento nem erro.
  Future<void> carregar({bool silencioso = false}) async {
    try {
      final uid = _uid();
      if (!silencioso) {
        _carregando = true;
        _erro = null;
        notifyListeners();
      }
      _carrinho = await servico.obter(uid);
      _erro = null;
    } catch (e) {
      if (!silencioso) _erro = e.toString();
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> _executar(String chave, Future<CarrinhoModel> Function(String uid) acao) async {
    final uid = _uid();
    _ocupados.add(chave);
    notifyListeners();
    try {
      _carrinho = await acao(uid);
      _erro = null;
    } finally {
      _ocupados.remove(chave);
      notifyListeners();
    }
  }

  Future<void> adicionar(ProdutoModel produto, {int quantidade = 1}) {
    final id = produto.id;
    if (id == null) throw ProdutoApiException('Produto sem ID');
    return _executar(id, (uid) => servico.adicionar(uid, id, quantidade: quantidade));
  }

  Future<void> alterarQuantidade(String produtoId, int quantidade) => _executar(
      produtoId, (uid) => servico.definirQuantidade(uid, produtoId, quantidade));

  Future<void> remover(String produtoId) =>
      _executar(produtoId, (uid) => servico.remover(uid, produtoId));

  Future<void> esvaziar() => _executar('*', (uid) => servico.esvaziar(uid));

  /// Finaliza a compra: a API baixa o estoque, salva o pedido e esvazia o carrinho.
  Future<PedidoModel> finalizar() async {
    final uid = _uid();
    _ocupados.add('*');
    notifyListeners();
    try {
      final pedido = await servico.finalizar(uid);
      _carrinho = const CarrinhoModel();
      return pedido;
    } finally {
      _ocupados.remove('*');
      notifyListeners();
    }
  }

  /// Chamado quando a API avisa (tempo real) que um produto mudou: se ele
  /// está no carrinho, atualiza preço/estoque/nome sem precisar de F5.
  void aoMudarProduto(ProdutoModel produto) {
    if (produto.id != null && quantidadeDe(produto.id!) > 0) {
      carregar(silencioso: true);
    }
  }
}
