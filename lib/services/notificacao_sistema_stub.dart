/// Situação da permissão de notificações do sistema.
enum PermissaoNotificacao { naoSuportado, pendente, concedida, negada }

/// Versão para plataformas sem a Notification API do navegador.
class NotificacaoSistema {
  static bool get suportado => false;

  static PermissaoNotificacao get permissao => PermissaoNotificacao.naoSuportado;

  static Future<PermissaoNotificacao> pedirPermissao() async =>
      PermissaoNotificacao.naoSuportado;

  /// Mostra o aviso. Retorna true se foi exibido.
  static bool mostrar(String titulo, String corpo, {String? tag}) => false;
}
