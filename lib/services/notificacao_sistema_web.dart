import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Situação da permissão de notificações do sistema.
enum PermissaoNotificacao { naoSuportado, pendente, concedida, negada }

/// Notificações do sistema pelo navegador (Notification API).
/// O navegador mostra o aviso nativo do Windows/macOS/Android, mesmo com a
/// aba em segundo plano. Precisa da permissão do usuário (pedida uma vez).
class NotificacaoSistema {
  static bool get suportado => globalContext.has('Notification');

  static PermissaoNotificacao _converter(String valor) => switch (valor) {
        'granted' => PermissaoNotificacao.concedida,
        'denied' => PermissaoNotificacao.negada,
        _ => PermissaoNotificacao.pendente,
      };

  static PermissaoNotificacao get permissao {
    if (!suportado) return PermissaoNotificacao.naoSuportado;
    return _converter(web.Notification.permission);
  }

  /// Abre o pedido de permissão do navegador (se ainda não foi respondido).
  static Future<PermissaoNotificacao> pedirPermissao() async {
    if (!suportado) return PermissaoNotificacao.naoSuportado;
    if (permissao != PermissaoNotificacao.pendente) return permissao;
    try {
      final resposta = await web.Notification.requestPermission().toDart;
      return _converter(resposta.toDart);
    } catch (_) {
      return permissao;
    }
  }

  /// Mostra o aviso. Retorna true se foi exibido.
  static bool mostrar(String titulo, String corpo, {String? tag}) {
    if (permissao != PermissaoNotificacao.concedida) return false;
    try {
      final notificacao = web.Notification(
        titulo,
        web.NotificationOptions(
          body: corpo,
          icon: 'icons/Icon-192.png',
          tag: tag ?? '',
        ),
      );
      // Clicar no aviso traz a aba do app para frente.
      notificacao.onclick = ((web.Event _) {
        web.window.focus();
        notificacao.close();
      }).toJS;
      return true;
    } catch (_) {
      return false;
    }
  }
}
