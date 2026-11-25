import 'package:equadras/model/produto_model.dart';

import 'carrinho_repository.dart';
import 'notificacao_repository.dart';
import 'produto_repository.dart';

/// Código curto do pedido mostrado ao usuário (ex.: "A1B2C3").
String codigoPedido(String id) =>
    (id.length > 6 ? id.substring(0, 6) : id).toUpperCase();

String _moeda(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

/// Erro de regra de negócio com o status HTTP que a API deve responder.
class LojaException implements Exception {
  final int status;
  final String mensagem;
  LojaException(this.status, this.mensagem);

  @override
  String toString() => mensagem;
}

/// Resultado da finalização: o pedido salvo e os produtos com o estoque novo.
class CompraFinalizada {
  final Map<String, dynamic> pedido;
  final List<ProdutoModel> produtosAtualizados;

  /// Notificação "Compra confirmada" criada para o usuário (se houver repositório).
  final Notificacao? notificacao;

  CompraFinalizada(this.pedido, this.produtosAtualizados, [this.notificacao]);
}

/// Regras do carrinho de compras e da finalização do pedido.
class LojaService {
  final ProdutoRepository produtos;
  final CarrinhoRepository carrinhos;
  final PedidoRepository pedidos;
  final NotificacaoRepository? notificacoes;

  LojaService({
    required this.produtos,
    required this.carrinhos,
    required this.pedidos,
    this.notificacoes,
  });

  void _validarUid(String uid) {
    if (uid.trim().isEmpty) {
      throw LojaException(400, 'Usuario nao informado');
    }
  }

  Future<Map<String, ProdutoModel>> _produtosPorId() async => {
        for (final p in await produtos.listar())
          if (p.id != null) p.id!: p,
      };

  /// Monta o JSON do carrinho com os dados atuais de cada produto.
  /// Itens de produtos que foram excluídos saem do carrinho automaticamente.
  Future<Map<String, dynamic>> verCarrinho(String uid) async {
    _validarUid(uid);
    final itens = await carrinhos.obter(uid);
    final catalogo = await _produtosPorId();

    final removidos = itens.keys.where((id) => !catalogo.containsKey(id)).toList();
    if (removidos.isNotEmpty) {
      for (final id in removidos) {
        itens.remove(id);
      }
      await carrinhos.salvar(uid, itens);
    }
    return _montarCarrinho(uid, itens, catalogo);
  }

  Map<String, dynamic> _montarCarrinho(
    String uid,
    ItensCarrinho itens,
    Map<String, ProdutoModel> catalogo,
  ) {
    final lista = <Map<String, dynamic>>[];
    var total = 0.0;
    var quantidadeItens = 0;
    for (final e in itens.entries) {
      final p = catalogo[e.key];
      if (p == null) continue;
      final subtotal = _arredondar(p.preco * e.value);
      total += subtotal;
      quantidadeItens += e.value;
      lista.add({
        'produtoId': e.key,
        'nome': p.nome,
        'categoria': p.categoria,
        'imagemUrl': p.imagemUrl,
        'precoUnitario': p.preco,
        'quantidade': e.value,
        'estoque': p.quantidade,
        'estoqueSuficiente': e.value <= p.quantidade,
        'subtotal': subtotal,
      });
    }
    return {
      'uid': uid,
      'itens': lista,
      'quantidadeItens': quantidadeItens,
      'total': _arredondar(total),
    };
  }

  Future<ProdutoModel> _produtoExistente(String produtoId) async {
    final p = await produtos.buscar(produtoId);
    if (p == null) throw LojaException(404, 'Produto nao encontrado');
    return p;
  }

  void _validarEstoque(ProdutoModel p, int quantidade) {
    if (quantidade > p.quantidade) {
      throw LojaException(
        409,
        p.quantidade == 0
            ? '"${p.nome}" esta esgotado'
            : 'Estoque insuficiente para "${p.nome}": apenas ${p.quantidade} un. disponiveis',
      );
    }
  }

  /// Soma [quantidade] ao que já estava no carrinho.
  Future<Map<String, dynamic>> adicionar(
      String uid, String produtoId, int quantidade) async {
    _validarUid(uid);
    if (quantidade <= 0) {
      throw LojaException(400, 'Quantidade deve ser maior que zero');
    }
    final produto = await _produtoExistente(produtoId);
    final itens = await carrinhos.obter(uid);
    final novaQuantidade = (itens[produtoId] ?? 0) + quantidade;
    _validarEstoque(produto, novaQuantidade);
    itens[produtoId] = novaQuantidade;
    await carrinhos.salvar(uid, itens);
    return verCarrinho(uid);
  }

  /// Define a quantidade exata; 0 remove o item.
  Future<Map<String, dynamic>> definirQuantidade(
      String uid, String produtoId, int quantidade) async {
    _validarUid(uid);
    if (quantidade < 0) {
      throw LojaException(400, 'Quantidade nao pode ser negativa');
    }
    final itens = await carrinhos.obter(uid);
    if (quantidade == 0) {
      itens.remove(produtoId);
    } else {
      final produto = await _produtoExistente(produtoId);
      _validarEstoque(produto, quantidade);
      itens[produtoId] = quantidade;
    }
    await carrinhos.salvar(uid, itens);
    return verCarrinho(uid);
  }

  Future<Map<String, dynamic>> remover(String uid, String produtoId) =>
      definirQuantidade(uid, produtoId, 0);

  Future<Map<String, dynamic>> esvaziar(String uid) async {
    _validarUid(uid);
    await carrinhos.salvar(uid, {});
    return verCarrinho(uid);
  }

  /// Confere o estoque de todos os itens, baixa as quantidades, salva o
  /// pedido e esvazia o carrinho. Se faltar estoque, nada é alterado.
  Future<CompraFinalizada> finalizar(String uid) async {
    _validarUid(uid);
    final itens = await carrinhos.obter(uid);
    if (itens.isEmpty) throw LojaException(400, 'O carrinho esta vazio');

    final catalogo = await _produtosPorId();

    // 1) Valida tudo antes de alterar qualquer coisa.
    final faltando = <String>[];
    for (final e in itens.entries) {
      final p = catalogo[e.key];
      if (p == null) {
        faltando.add('um produto do carrinho foi excluido');
      } else if (e.value > p.quantidade) {
        faltando.add('"${p.nome}" (pedido: ${e.value}, em estoque: ${p.quantidade})');
      }
    }
    if (faltando.isNotEmpty) {
      throw LojaException(409, 'Estoque insuficiente: ${faltando.join('; ')}');
    }

    // 2) Monta o pedido com os preços de agora.
    final carrinho = _montarCarrinho(uid, itens, catalogo);
    final pedido = <String, dynamic>{
      'uid': uid,
      'itens': [
        for (final item in carrinho['itens'] as List)
          {
            'produtoId': item['produtoId'],
            'nome': item['nome'],
            'precoUnitario': item['precoUnitario'],
            'quantidade': item['quantidade'],
            'subtotal': item['subtotal'],
          },
      ],
      'quantidadeItens': carrinho['quantidadeItens'],
      'total': carrinho['total'],
      'status': 'confirmado',
      'criadoEm': DateTime.now(),
    };

    // 3) Baixa o estoque.
    final atualizados = <ProdutoModel>[];
    for (final e in itens.entries) {
      final p = catalogo[e.key]!;
      atualizados.add(await produtos.salvar(p.copyWith(quantidade: p.quantidade - e.value)));
    }

    // 4) Salva o pedido e esvazia o carrinho.
    final id = await pedidos.criar(pedido);
    await carrinhos.salvar(uid, {});

    // 5) Notificação para o usuário. Se falhar, a compra continua valendo.
    Notificacao? notificacao;
    final repoNotificacoes = notificacoes;
    if (repoNotificacoes != null) {
      try {
        notificacao = await repoNotificacoes.criar(
          uid,
          Notificacao(
            titulo: 'Compra confirmada',
            mensagem: 'Pedido nº ${codigoPedido(id)} • '
                '${pedido['quantidadeItens']} item(ns) • '
                'Total ${_moeda(pedido['total'] as double)}',
            tipo: 'pedido',
            pedidoId: id,
          ),
        );
      } catch (_) {
        notificacao = null;
      }
    }

    return CompraFinalizada(
      {
        ...pedido,
        'id': id,
        'codigo': codigoPedido(id),
        'criadoEm': (pedido['criadoEm'] as DateTime).toUtc().toIso8601String(),
      },
      atualizados,
      notificacao,
    );
  }

  static double _arredondar(double v) => (v * 100).roundToDouble() / 100;
}
