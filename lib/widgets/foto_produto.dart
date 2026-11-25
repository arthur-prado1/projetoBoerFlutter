import 'package:flutter/material.dart';

/// Categorias de produto e seus ícones.
const Map<String, IconData> iconesCategorias = {
  'Futebol': Icons.sports_soccer,
  'Beach Tennis': Icons.beach_access,
  'Tênis': Icons.sports_tennis,
  'Vôlei': Icons.sports_volleyball,
  'Basquete': Icons.sports_basketball,
  'Acessórios': Icons.backpack_outlined,
  'Outros': Icons.category_outlined,
};

String _semAcento(String s) {
  const de = 'áàâãéêíóôõúç';
  const para = 'aaaaeeiooouc';
  var r = s;
  for (var i = 0; i < de.length; i++) {
    r = r.replaceAll(de[i], para[i]);
  }
  return r;
}

/// Ícone da categoria, ignorando maiúsculas e acentos ("Volei" = "Vôlei").
IconData iconeCategoria(String categoria) {
  final normalizada = _semAcento(categoria.trim().toLowerCase());
  for (final entry in iconesCategorias.entries) {
    if (_semAcento(entry.key.toLowerCase()) == normalizada) return entry.value;
  }
  return Icons.inventory_2_outlined;
}

/// Foto do produto pelo link; sem link ou com link quebrado mostra o ícone
/// da categoria.
class FotoProduto extends StatelessWidget {
  final String url;
  final double tamanho;
  final double raio;
  final String categoria;

  const FotoProduto(
    this.url, {
    super.key,
    required this.tamanho,
    this.raio = 12,
    this.categoria = '',
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: tamanho,
      height: tamanho,
      color: Colors.green.shade50,
      child: Icon(
        iconeCategoria(categoria),
        color: Colors.green,
        size: tamanho * 0.45,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(raio),
      child: url.isEmpty
          ? placeholder
          : Image.network(
              url,
              key: ValueKey(url),
              width: tamanho,
              height: tamanho,
              fit: BoxFit.cover,
              // No navegador, permite links de sites que bloqueiam CORS.
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              loadingBuilder: (context, child, progresso) {
                if (progresso == null) return child;
                return Container(
                  width: tamanho,
                  height: tamanho,
                  color: Colors.grey.shade100,
                  child: const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.green,
                      ),
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => Tooltip(
                message: 'Não foi possível carregar a foto',
                child: Stack(
                  children: [
                    placeholder,
                    Positioned(
                      right: 3,
                      bottom: 3,
                      child: Icon(Icons.broken_image_outlined,
                          size: 14, color: Colors.red.shade300),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
