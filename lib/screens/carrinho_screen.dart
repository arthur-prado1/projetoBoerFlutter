import 'package:flutter/material.dart';

import '../model/carrinho_model.dart';
import '../services/carrinho_controller.dart';
import '../services/notificacao_controller.dart';
import '../widgets/sino_notificacoes.dart';
import '../utils/currency_input_formatter.dart';
import '../widgets/foto_produto.dart';

/// Carrinho de compras do usuário logado.
///
/// Os itens ficam guardados pela API no Firestore (carrinhos/{uid}).
/// Finalizar a compra baixa o estoque dos produtos e salva o pedido.
class CarrinhoScreen extends StatefulWidget {
  const CarrinhoScreen({super.key});

  @override
  State<CarrinhoScreen> createState() => _CarrinhoScreenState();
}

class _CarrinhoScreenState extends State<CarrinhoScreen> {
  final CarrinhoController _carrinho = CarrinhoController.instancia;

  @override
  void initState() {
    super.initState();
    _carrinho.carregar();
  }

  void _mostrarErro(Object e) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
    );
  }

  Future<void> _alterarQuantidade(ItemCarrinho item, int novaQuantidade) async {
    try {
      await _carrinho.alterarQuantidade(item.produtoId, novaQuantidade);
    } catch (e) {
      _mostrarErro(e);
    }
  }

  Future<void> _remover(ItemCarrinho item) async {
    try {
      await _carrinho.remover(item.produtoId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${item.nome}" removido do carrinho'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      _mostrarErro(e);
    }
  }

  void _confirmarEsvaziar() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Esvaziar carrinho'),
        content: const Text('Remover todos os itens do carrinho?'),
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
              try {
                await _carrinho.esvaziar();
              } catch (e) {
                _mostrarErro(e);
              }
            },
            child: const Text('ESVAZIAR'),
          ),
        ],
      ),
    );
  }

  void _confirmarFinalizar(CarrinhoModel carrinho) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.shopping_bag_outlined, color: Colors.green),
            SizedBox(width: 8),
            Text('Finalizar compra'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in carrinho.itens)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${item.quantidade}x ${item.nome}',
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(formatarMoeda(item.subtotal)),
                  ],
                ),
              ),
            const Divider(),
            Row(
              children: [
                const Expanded(
                  child: Text('Total',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Text(
                  formatarMoeda(carrinho.total),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              _finalizar();
            },
            child: const Text('CONFIRMAR COMPRA'),
          ),
        ],
      ),
    );
  }

  Future<void> _finalizar() async {
    final notificacoes = NotificacaoController.instancia;
    // Na primeira compra, o navegador pergunta se pode mostrar avisos.
    await notificacoes.ativarAvisosDoSistema();
    try {
      final pedido = await _carrinho.finalizar();
      // Aviso do sistema (Windows/navegador) + item novo no sininho.
      final notificacao = pedido.notificacao;
      if (notificacao != null) notificacoes.receber(notificacao);
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 56),
          title: const Text('Compra realizada!'),
          content: Text(
            'Pedido nº ${pedido.codigo}\n'
            '${pedido.quantidadeItens} item(ns) • Total ${formatarMoeda(pedido.total)}\n\n'
            'O estoque dos produtos já foi atualizado.',
            textAlign: TextAlign.center,
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('CONTINUAR COMPRANDO'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      _mostrarErro(e);
      _carrinho.carregar(silencioso: true); // mostra o estoque atual
    }
  }

  Widget _buildItem(ItemCarrinho item) {
    final ocupado = _carrinho.ocupado(item.produtoId) || _carrinho.ocupado('*');
    final podeAumentar = !ocupado && item.quantidade < item.estoque;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: item.estoqueSuficiente
            ? BorderSide.none
            : BorderSide(color: Colors.red.shade300, width: 1.5),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            FotoProduto(
              item.imagemUrl,
              tamanho: 64,
              categoria: item.categoria,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.nome,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${formatarMoeda(item.precoUnitario)} / un.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  if (!item.estoqueSuficiente)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.estoque == 0
                            ? 'Esgotado: remova para finalizar'
                            : 'Só ${item.estoque} em estoque: diminua a quantidade',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  // Controle de quantidade
                  Row(
                    children: [
                      _botaoQuantidade(
                        icone: item.quantidade > 1
                            ? Icons.remove
                            : Icons.delete_outline,
                        tooltip: item.quantidade > 1 ? 'Diminuir' : 'Remover',
                        onPressed: ocupado
                            ? null
                            : () => item.quantidade > 1
                                ? _alterarQuantidade(item, item.quantidade - 1)
                                : _remover(item),
                      ),
                      SizedBox(
                        width: 36,
                        child: ocupado
                            ? const Center(
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.green),
                                ),
                              )
                            : Text(
                                '${item.quantidade}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                      _botaoQuantidade(
                        icone: Icons.add,
                        tooltip: podeAumentar
                            ? 'Aumentar'
                            : 'Limite do estoque (${item.estoque})',
                        onPressed: podeAumentar
                            ? () => _alterarQuantidade(item, item.quantidade + 1)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Remover do carrinho',
                  icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                  onPressed: ocupado ? null : () => _remover(item),
                ),
                Text(
                  formatarMoeda(item.subtotal),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _botaoQuantidade({
    required IconData icone,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton.outlined(
        padding: EdgeInsets.zero,
        iconSize: 16,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icone),
      ),
    );
  }

  Widget _buildResumo(CarrinhoModel carrinho) {
    final finalizando = _carrinho.ocupado('*');
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -3)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${carrinho.quantidadeItens} item(ns)',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  Text(
                    formatarMoeda(carrinho.total),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: carrinho.podeFinalizar && !finalizando
                  ? () => _confirmarFinalizar(carrinho)
                  : null,
              icon: finalizando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.shopping_bag_outlined),
              label: Text(
                finalizando ? 'Finalizando...' : 'FINALIZAR COMPRA',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVazio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart_outlined,
                size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Seu carrinho está vazio',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Adicione produtos pelo botão de carrinho na lista de produtos.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('VER PRODUTOS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErro(String erro) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 12),
            const Text(
              'Não foi possível carregar o carrinho',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(erro,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _carrinho.carregar,
              icon: const Icon(Icons.refresh),
              label: const Text('TENTAR NOVAMENTE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _carrinho,
      builder: (context, _) {
        final carrinho = _carrinho.carrinho;
        final Widget corpo;
        if (_carrinho.carregando && carrinho.vazio) {
          corpo = const Center(
              child: CircularProgressIndicator(color: Colors.green));
        } else if (_carrinho.erro != null && carrinho.vazio) {
          corpo = _buildErro(_carrinho.erro!);
        } else if (carrinho.vazio) {
          corpo = _buildVazio();
        } else {
          corpo = RefreshIndicator(
            color: Colors.green,
            onRefresh: _carrinho.carregar,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!carrinho.podeFinalizar)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'O estoque de algum item mudou. Ajuste as quantidades destacadas para finalizar.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ...carrinho.itens.map(_buildItem),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF7F9F7),
          appBar: AppBar(
            title: const Row(
              children: [
                Icon(Icons.shopping_cart_outlined, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Meu Carrinho',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            actions: [
              const SinoNotificacoes(),
              if (!carrinho.vazio)
                TextButton.icon(
                  onPressed: _carrinho.ocupado('*') ? null : _confirmarEsvaziar,
                  icon: const Icon(Icons.remove_shopping_cart_outlined,
                      color: Colors.white),
                  label: const Text('Esvaziar',
                      style: TextStyle(color: Colors.white)),
                ),
            ],
          ),
          body: SafeArea(child: corpo),
          bottomNavigationBar: carrinho.vazio ? null : _buildResumo(carrinho),
        );
      },
    );
  }
}
