import 'dart:convert';
import 'dart:io';
import 'package:equadras/model/produto_model.dart';
import 'src/carrinho_repository.dart';
import 'src/loja.dart';
import 'src/notificacao_repository.dart';
import 'src/produto_repository.dart';

/// Nome padrão da chave de conta de serviço do Firebase, na raiz do projeto.
/// Também pode ser indicada pela variável FIREBASE_SERVICE_ACCOUNT
/// (ou GOOGLE_APPLICATION_CREDENTIALS) com o caminho do arquivo .json.
const nomeChavePadrao = 'firebase-service-account.json';

/// Onde os produtos são guardados (Firestore, ou memória sem a chave).
late final ProdutoRepository repositorio;

/// Carrinho de compras e pedidos (mesmo armazenamento dos produtos).
late final LojaService loja;

/// Notificações dos usuários (mesmo armazenamento dos produtos).
late final NotificacaoRepository notificacoes;

/// Clientes conectados em tempo real (WebSocket em /ws ou /api/ws) e o uid
/// do usuário de cada um (informado em /ws?uid=...; pode ser nulo).
final Map<WebSocket, String?> clientesTempoReal = {};

void _enviar(WebSocket cliente, String mensagem) {
  try {
    cliente.add(mensagem);
  } catch (_) {
    clientesTempoReal.remove(cliente);
  }
}

/// Avisa todos os clientes conectados que um produto mudou.
/// Mensagem: {"evento": "criado" | "atualizado" | "excluido", "produto": {...}}
void notificarClientes(String evento, ProdutoModel produto) {
  final mensagem = jsonEncode({'evento': evento, 'produto': produto.toMap()});
  for (final cliente in clientesTempoReal.keys.toList()) {
    _enviar(cliente, mensagem);
  }
}

/// Envia uma notificação só para as conexões daquele usuário.
/// Mensagem: {"evento": "notificacao", "notificacao": {...}}
void notificarUsuario(String uid, Notificacao notificacao) {
  final mensagem = jsonEncode({
    'evento': 'notificacao',
    'notificacao': notificacao.toJson(),
  });
  clientesTempoReal.forEach((cliente, uidCliente) {
    if (uidCliente == uid) _enviar(cliente, mensagem);
  });
}

Future<void> _conectarTempoReal(HttpRequest request) async {
  final uid = request.uri.queryParameters['uid'];
  final socket = await WebSocketTransformer.upgrade(request);
  clientesTempoReal[socket] = (uid == null || uid.isEmpty) ? null : uid;
  stdout.writeln('Cliente em tempo real conectado (${clientesTempoReal.length} ativo(s))');
  socket.listen(
    (_) {}, // O servidor só envia; mensagens recebidas são ignoradas.
    onDone: () => clientesTempoReal.remove(socket),
    onError: (_) => clientesTempoReal.remove(socket),
    cancelOnError: true,
  );
}

/// Procura a chave do Firebase: variável de ambiente ou arquivo na raiz.
File? _localizarChave() {
  final env = Platform.environment['FIREBASE_SERVICE_ACCOUNT'] ??
      Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'];
  if (env != null && env.trim().isNotEmpty) return File(env.trim());

  // Raiz do projeto = pasta acima de bin/
  final raiz = File.fromUri(Platform.script).parent.parent;
  final arquivo = File('${raiz.path}${Platform.pathSeparator}$nomeChavePadrao');
  return arquivo.existsSync() ? arquivo : null;
}

Future<ProdutoRepository> _criarRepositorio() async {
  if (Platform.environment['USAR_MEMORIA'] == '1') {
    stdout.writeln('USAR_MEMORIA=1: ignorando o Firestore; dados só em memória.');
    return MemoriaProdutoRepository();
  }
  final chave = _localizarChave();
  if (chave == null) {
    stdout.writeln('');
    stdout.writeln('AVISO: chave do Firebase não encontrada.');
    stdout.writeln('  Os produtos vão ficar só na MEMÓRIA e somem ao reiniciar a API.');
    stdout.writeln('  Para salvar no Firestore, baixe a chave em: Firebase Console >');
    stdout.writeln('  Configurações do projeto > Contas de serviço > Gerar nova chave privada,');
    stdout.writeln('  e salve na raiz do projeto como "$nomeChavePadrao".');
    stdout.writeln('');
    return MemoriaProdutoRepository();
  }
  if (!chave.existsSync()) {
    throw StateError('Chave do Firebase não encontrada em: ${chave.path}');
  }

  final firestore = await FirestoreProdutoRepository.conectar(chave);
  // Testa o acesso já na inicialização e cria os exemplos se estiver vazio.
  final existentes = await firestore.listar();
  if (existentes.isEmpty) {
    for (final p in produtosIniciais()) {
      await firestore.criar(p);
    }
    stdout.writeln('Coleção "produtos" estava vazia: 2 produtos de exemplo criados.');
  }
  return firestore;
}

void main() async {
  try {
    repositorio = await _criarRepositorio();
    final repo = repositorio;
    if (repo is FirestoreProdutoRepository) {
      notificacoes = FirestoreNotificacaoRepository(projectId: repo.projectId, client: repo.client);
      loja = LojaService(
        produtos: repo,
        carrinhos: FirestoreCarrinhoRepository(projectId: repo.projectId, client: repo.client),
        pedidos: FirestorePedidoRepository(projectId: repo.projectId, client: repo.client),
        notificacoes: notificacoes,
      );
    } else {
      notificacoes = MemoriaNotificacaoRepository();
      loja = LojaService(
        produtos: repo,
        carrinhos: MemoriaCarrinhoRepository(),
        pedidos: MemoriaPedidoRepository(),
        notificacoes: notificacoes,
      );
    }
  } catch (e) {
    stderr.writeln('ERRO ao conectar no Firestore: $e');
    stderr.writeln('Confira se a chave .json é do projeto certo e se o Firestore está ativo.');
    exit(1);
  }

  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('Produtos salvos em: ${repositorio.descricao}');
  stdout.writeln('Servidor REST rodando em http://${server.address.host}:${server.port}');

  await for (HttpRequest request in server) {
    _handleRequest(request);
  }
}

double? _lerPreco(dynamic valor) {
  if (valor == null) return null;
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor.toString());
}

int? _lerQuantidade(dynamic valor) {
  if (valor == null) return null;
  if (valor is num) return valor.toInt();
  return int.tryParse(valor.toString());
}

/// Lê o corpo JSON; devolve null (e já responde 400) se for inválido.
Future<Map<String, dynamic>?> _lerCorpo(HttpRequest request) async {
  final content = await utf8.decoder.bind(request).join();
  if (content.trim().isEmpty) {
    _sendJson(request.response, HttpStatus.badRequest, {'erro': 'Corpo da requisicao vazio'});
    return null;
  }
  final data = jsonDecode(content);
  if (data is! Map<String, dynamic>) {
    _sendJson(request.response, HttpStatus.badRequest, {'erro': 'Formato JSON invalido'});
    return null;
  }
  return data;
}

void _handleRequest(HttpRequest request) async {
  // Canal de tempo real: o front recebe as alterações sem precisar de F5.
  final rota = request.uri.pathSegments;
  final ehRotaWs = (rota.length == 1 && rota[0] == 'ws') ||
      (rota.length == 2 && rota[0] == 'api' && rota[1] == 'ws');
  if (ehRotaWs && WebSocketTransformer.isUpgradeRequest(request)) {
    await _conectarTempoReal(request);
    return;
  }

  final response = request.response;
  response.headers.add('Access-Control-Allow-Origin', '*');
  response.headers.add('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  response.headers.add('Access-Control-Allow-Headers', 'Origin, Content-Type, Accept');
  response.headers.contentType = ContentType.json;

  if (request.method == 'OPTIONS') {
    response.statusCode = HttpStatus.noContent;
    await response.close();
    return;
  }

  List<String> pathSegments = rota;
  if (pathSegments.isNotEmpty && pathSegments.first == 'api') {
    pathSegments = pathSegments.sublist(1);
  }

  if (pathSegments.isNotEmpty && pathSegments.first == 'carrinhos') {
    await _rotasCarrinho(request, pathSegments);
    return;
  }

  if (pathSegments.isNotEmpty && pathSegments.first == 'notificacoes') {
    await _rotasNotificacoes(request, pathSegments);
    return;
  }

  if (pathSegments.isEmpty || pathSegments.first != 'produtos') {
    _sendJson(response, HttpStatus.notFound, {'erro': 'Rota nao encontrada'});
    return;
  }

  try {
    if (pathSegments.length == 1) {
      // GET /produtos
      if (request.method == 'GET') {
        final lista = await repositorio.listar();
        _sendJson(response, HttpStatus.ok, lista.map((p) => p.toMap()).toList());
        return;
      }

      // POST /produtos
      if (request.method == 'POST') {
        final data = await _lerCorpo(request);
        if (data == null) return;

        final novoProduto = await repositorio.criar(ProdutoModel(
          nome: data['nome']?.toString() ?? '',
          categoria: data['categoria']?.toString() ?? '',
          preco: _lerPreco(data['preco']) ?? 0.0,
          quantidade: _lerQuantidade(data['quantidade']) ?? 0,
          imagemUrl: data['imagemUrl']?.toString().trim() ?? '',
        ));

        _sendJson(response, HttpStatus.created, novoProduto.toMap());
        notificarClientes('criado', novoProduto);
        return;
      }
    }

    if (pathSegments.length == 2) {
      final id = pathSegments[1];

      // GET /produtos/{id}
      if (request.method == 'GET') {
        final produto = await repositorio.buscar(id);
        if (produto == null) {
          _sendJson(response, HttpStatus.notFound, {'erro': 'Produto nao encontrado'});
          return;
        }
        _sendJson(response, HttpStatus.ok, produto.toMap());
        return;
      }

      // PUT /produtos/{id} (campos não enviados continuam como estão)
      if (request.method == 'PUT') {
        final atual = await repositorio.buscar(id);
        if (atual == null) {
          _sendJson(response, HttpStatus.notFound, {'erro': 'Produto nao encontrado'});
          return;
        }

        final data = await _lerCorpo(request);
        if (data == null) return;

        final atualizado = await repositorio.salvar(atual.copyWith(
          nome: data['nome']?.toString(),
          categoria: data['categoria']?.toString(),
          preco: _lerPreco(data['preco']),
          quantidade: _lerQuantidade(data['quantidade']),
          imagemUrl: data['imagemUrl']?.toString().trim(),
        ));

        _sendJson(response, HttpStatus.ok, atualizado.toMap());
        notificarClientes('atualizado', atualizado);
        return;
      }

      // DELETE /produtos/{id}
      if (request.method == 'DELETE') {
        final removido = await repositorio.buscar(id);
        if (removido == null) {
          _sendJson(response, HttpStatus.notFound, {'erro': 'Produto nao encontrado'});
          return;
        }

        await repositorio.excluir(id);
        _sendJson(response, HttpStatus.ok, {
          'mensagem': 'Produto removido com sucesso',
          'produto': removido.toMap(),
        });
        notificarClientes('excluido', removido);
        return;
      }
    }

    _sendJson(response, HttpStatus.methodNotAllowed, {'erro': 'Metodo nao permitido'});
  } on FormatException {
    _sendJson(response, HttpStatus.badRequest, {'erro': 'JSON invalido'});
  } on FirestoreException catch (e) {
    stderr.writeln(e);
    _sendJson(response, HttpStatus.badGateway, {'erro': e.toString()});
  } catch (e) {
    _sendJson(response, HttpStatus.internalServerError, {'erro': e.toString()});
  }
}

/// Rotas do carrinho de compras (o {uid} é o usuário do Firebase Auth):
///   GET    /carrinhos/{uid}                      ver carrinho
///   POST   /carrinhos/{uid}/itens                adicionar {produtoId, quantidade}
///   PUT    /carrinhos/{uid}/itens/{produtoId}    definir {quantidade} (0 remove)
///   DELETE /carrinhos/{uid}/itens/{produtoId}    remover item
///   DELETE /carrinhos/{uid}                      esvaziar
///   POST   /carrinhos/{uid}/finalizar            finalizar compra (baixa estoque)
Future<void> _rotasCarrinho(HttpRequest request, List<String> seg) async {
  final response = request.response;
  final metodo = request.method;
  try {
    if (seg.length < 2) {
      _sendJson(response, HttpStatus.notFound, {'erro': 'Informe o usuario: /carrinhos/{uid}'});
      return;
    }
    final uid = seg[1];

    if (seg.length == 2) {
      if (metodo == 'GET') {
        _sendJson(response, HttpStatus.ok, await loja.verCarrinho(uid));
        return;
      }
      if (metodo == 'DELETE') {
        _sendJson(response, HttpStatus.ok, await loja.esvaziar(uid));
        return;
      }
    }

    if (seg.length == 3 && seg[2] == 'itens' && metodo == 'POST') {
      final data = await _lerCorpo(request);
      if (data == null) return;
      final produtoId = data['produtoId']?.toString() ?? '';
      if (produtoId.isEmpty) {
        _sendJson(response, HttpStatus.badRequest, {'erro': 'Informe o produtoId'});
        return;
      }
      final quantidade = _lerQuantidade(data['quantidade']) ?? 1;
      _sendJson(response, HttpStatus.ok, await loja.adicionar(uid, produtoId, quantidade));
      return;
    }

    if (seg.length == 4 && seg[2] == 'itens') {
      final produtoId = seg[3];
      if (metodo == 'PUT') {
        final data = await _lerCorpo(request);
        if (data == null) return;
        final quantidade = _lerQuantidade(data['quantidade']);
        if (quantidade == null) {
          _sendJson(response, HttpStatus.badRequest, {'erro': 'Informe a quantidade'});
          return;
        }
        _sendJson(response, HttpStatus.ok,
            await loja.definirQuantidade(uid, produtoId, quantidade));
        return;
      }
      if (metodo == 'DELETE') {
        _sendJson(response, HttpStatus.ok, await loja.remover(uid, produtoId));
        return;
      }
    }

    if (seg.length == 3 && seg[2] == 'finalizar' && metodo == 'POST') {
      final compra = await loja.finalizar(uid);
      _sendJson(response, HttpStatus.created, {
        'mensagem': 'Compra finalizada com sucesso',
        'pedido': compra.pedido,
        'notificacao': compra.notificacao?.toJson(),
      });
      // O estoque mudou: avisa as telas abertas em tempo real.
      for (final p in compra.produtosAtualizados) {
        notificarClientes('atualizado', p);
      }
      // E avisa o usuário em todos os dispositivos dele.
      final notificacao = compra.notificacao;
      if (notificacao != null) notificarUsuario(uid, notificacao);
      return;
    }

    _sendJson(response, HttpStatus.notFound, {'erro': 'Rota nao encontrada'});
  } on LojaException catch (e) {
    _sendJson(response, e.status, {'erro': e.mensagem});
  } on FormatException {
    _sendJson(response, HttpStatus.badRequest, {'erro': 'JSON invalido'});
  } on FirestoreException catch (e) {
    stderr.writeln(e);
    _sendJson(response, HttpStatus.badGateway, {'erro': e.toString()});
  } catch (e) {
    _sendJson(response, HttpStatus.internalServerError, {'erro': e.toString()});
  }
}

/// Rotas das notificações do usuário:
///   GET /notificacoes/{uid}              listar (mais recentes primeiro)
///   PUT /notificacoes/{uid}/{id}/lida    marcar uma como lida
///   PUT /notificacoes/{uid}/lidas        marcar todas como lidas
Future<void> _rotasNotificacoes(HttpRequest request, List<String> seg) async {
  final response = request.response;
  final metodo = request.method;
  try {
    if (seg.length < 2 || seg[1].trim().isEmpty) {
      _sendJson(response, HttpStatus.notFound, {'erro': 'Informe o usuario: /notificacoes/{uid}'});
      return;
    }
    final uid = seg[1];

    Future<Map<String, dynamic>> lista() async {
      final itens = await notificacoes.listar(uid);
      return {
        'uid': uid,
        'naoLidas': itens.where((n) => !n.lida).length,
        'notificacoes': itens.map((n) => n.toJson()).toList(),
      };
    }

    if (seg.length == 2 && metodo == 'GET') {
      _sendJson(response, HttpStatus.ok, await lista());
      return;
    }

    if (seg.length == 3 && seg[2] == 'lidas' && metodo == 'PUT') {
      for (final n in await notificacoes.listar(uid)) {
        if (!n.lida) await notificacoes.marcarLida(uid, n.id);
      }
      _sendJson(response, HttpStatus.ok, await lista());
      return;
    }

    if (seg.length == 4 && seg[3] == 'lida' && metodo == 'PUT') {
      final n = await notificacoes.marcarLida(uid, seg[2]);
      if (n == null) {
        _sendJson(response, HttpStatus.notFound, {'erro': 'Notificacao nao encontrada'});
        return;
      }
      _sendJson(response, HttpStatus.ok, await lista());
      return;
    }

    _sendJson(response, HttpStatus.notFound, {'erro': 'Rota nao encontrada'});
  } on FirestoreException catch (e) {
    stderr.writeln(e);
    _sendJson(response, HttpStatus.badGateway, {'erro': e.toString()});
  } catch (e) {
    _sendJson(response, HttpStatus.internalServerError, {'erro': e.toString()});
  }
}

void _sendJson(HttpResponse response, int status, dynamic body) {
  response.statusCode = status;
  response.write(jsonEncode(body));
  response.close();
}
