import 'dart:convert';
import 'dart:io';
import '../model/produto_model.dart';

class ProdutoService {
  final String baseUrl;
  final HttpClient _client = HttpClient();

  ProdutoService({this.baseUrl = 'http://localhost:8080/produtos'});

  Future<List<ProdutoModel>> getProdutos() async {
    final request = await _client.getUrl(Uri.parse(baseUrl));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(body);
      return list.map((item) => ProdutoModel.fromMap(item as Map<String, dynamic>)).toList();
    }
    throw Exception('Falha ao carregar produtos: ${response.statusCode}');
  }

  Future<ProdutoModel> getProdutoById(String id) async {
    final request = await _client.getUrl(Uri.parse('$baseUrl/$id'));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode == 200) {
      return ProdutoModel.fromMap(jsonDecode(body) as Map<String, dynamic>);
    }
    throw Exception('Produto nao encontrado');
  }

  Future<ProdutoModel> createProduto(ProdutoModel produto) async {
    final request = await _client.postUrl(Uri.parse(baseUrl));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(produto.toMap()));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode == 201) {
      return ProdutoModel.fromMap(jsonDecode(body) as Map<String, dynamic>);
    }
    throw Exception('Falha ao cadastrar produto');
  }

  Future<ProdutoModel> updateProduto(ProdutoModel produto) async {
    if (produto.id == null) {
      throw Exception('ID do produto obrigatorio para atualizacao');
    }
    final request = await _client.putUrl(Uri.parse('$baseUrl/${produto.id}'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(produto.toMap()));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode == 200) {
      return ProdutoModel.fromMap(jsonDecode(body) as Map<String, dynamic>);
    }
    throw Exception('Falha ao atualizar produto');
  }

  Future<void> deleteProduto(String id) async {
    final request = await _client.deleteUrl(Uri.parse('$baseUrl/$id'));
    final response = await request.close();
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Falha ao excluir produto');
    }
  }
}
