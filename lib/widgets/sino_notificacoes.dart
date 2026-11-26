import 'package:flutter/material.dart';

import '../model/notificacao_model.dart';
import '../services/notificacao_controller.dart';
import '../services/notificacao_sistema.dart';
import '../services/push_service.dart';

/// Sininho da AppBar com o número de notificações não lidas.
/// Ao tocar, abre o painel com a lista.
class SinoNotificacoes extends StatefulWidget {
  const SinoNotificacoes({super.key});

  @override
  State<SinoNotificacoes> createState() => _SinoNotificacoesState();
}

class _SinoNotificacoesState extends State<SinoNotificacoes> {
  final NotificacaoController _controller = NotificacaoController.instancia;

  @override
  void initState() {
    super.initState();
    _controller.iniciar();
    // No celular Android: registra o aparelho para receber push (FCM).
    PushService.instancia.iniciar();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final qtd = _controller.naoLidas;
        return IconButton(
          tooltip: qtd > 0 ? '$qtd notificação(ões) não lida(s)' : 'Notificações',
          onPressed: () => abrirPainelNotificacoes(context),
          icon: Badge(
            isLabelVisible: qtd > 0,
            label: Text(qtd > 99 ? '99+' : '$qtd'),
            backgroundColor: Colors.red.shade600,
            child: Icon(qtd > 0
                ? Icons.notifications_active_outlined
                : Icons.notifications_none),
          ),
        );
      },
    );
  }
}

/// Painel (bottom sheet) com as notificações do usuário.
void abrirPainelNotificacoes(BuildContext context) {
  final controller = NotificacaoController.instancia;
  controller.carregar(silencioso: true);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_outlined, color: Colors.green),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Notificações',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (controller.naoLidas > 0)
                      TextButton.icon(
                        onPressed: controller.marcarTodasLidas,
                        icon: const Icon(Icons.done_all, size: 18),
                        label: const Text('Marcar todas como lidas'),
                      ),
                    IconButton(
                      tooltip: 'Fechar',
                      icon: Icon(Icons.close, color: Colors.grey.shade700),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              _AvisoPermissao(controller: controller),
              const Divider(height: 1),
              Expanded(child: _ListaNotificacoes(controller: controller, scroll: scroll)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Faixa para ativar os avisos do Windows/navegador (se ainda não ativou).
class _AvisoPermissao extends StatelessWidget {
  final NotificacaoController controller;
  const _AvisoPermissao({required this.controller});

  @override
  Widget build(BuildContext context) {
    final permissao = controller.permissaoSistema;
    if (permissao == PermissaoNotificacao.concedida ||
        permissao == PermissaoNotificacao.naoSuportado) {
      return const SizedBox.shrink();
    }
    final negada = permissao == PermissaoNotificacao.negada;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: negada ? Colors.orange.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            negada ? Icons.notifications_off_outlined : Icons.desktop_windows_outlined,
            color: negada ? Colors.orange.shade800 : Colors.green.shade800,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              negada
                  ? 'Os avisos do sistema estão bloqueados. Para ativar, clique no cadeado ao lado do endereço do site e permita "Notificações".'
                  : 'Receba um aviso do Windows/navegador quando sua compra for confirmada, mesmo com a aba em segundo plano.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (!negada) ...[
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              onPressed: controller.ativarAvisosDoSistema,
              child: const Text('Ativar'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ListaNotificacoes extends StatelessWidget {
  final NotificacaoController controller;
  final ScrollController scroll;
  const _ListaNotificacoes({required this.controller, required this.scroll});

  @override
  Widget build(BuildContext context) {
    final itens = controller.itens;
    if (controller.carregando && itens.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Colors.green));
    }
    if (controller.erro != null && itens.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(controller.erro!, textAlign: TextAlign.center),
        ),
      );
    }
    if (itens.isEmpty) {
      return ListView(
        controller: scroll,
        children: [
          const SizedBox(height: 40),
          Icon(Icons.notifications_none, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'Nenhuma notificação ainda',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Quando você finalizar uma compra, ela aparece aqui.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      controller: scroll,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: itens.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) => _ItemNotificacao(
        notificacao: itens[i],
        onTap: () => controller.marcarLida(itens[i]),
      ),
    );
  }
}

class _ItemNotificacao extends StatelessWidget {
  final NotificacaoModel notificacao;
  final VoidCallback onTap;
  const _ItemNotificacao({required this.notificacao, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final n = notificacao;
    final ehPedido = n.tipo == 'pedido';
    return Material(
      color: n.lida ? Colors.white : Colors.green.shade50.withValues(alpha: 0.6),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: ehPedido ? Colors.green : Colors.blueGrey,
                child: Icon(
                  ehPedido ? Icons.shopping_bag_outlined : Icons.info_outline,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.titulo,
                            style: TextStyle(
                              fontWeight: n.lida ? FontWeight.w600 : FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Text(
                          tempoRelativo(n.criadoEm),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      n.mensagem,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                    ),
                  ],
                ),
              ),
              if (!n.lida)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 6),
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
