/// Notificação nativa do sistema (aviso do Windows/macOS/Android pelo
/// navegador). No navegador usa a Notification API; nas outras plataformas
/// não faz nada (a central de notificações do app continua funcionando).
library;

export 'notificacao_sistema_stub.dart'
    if (dart.library.js_interop) 'notificacao_sistema_web.dart';
