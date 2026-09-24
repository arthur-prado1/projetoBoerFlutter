import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../model/quadra_model.dart';
import '../services/quadra_service.dart';

/// Formatador monetário brasileiro (R$ 0,00)
class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    String cleanText = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanText.isEmpty) {
      return newValue.copyWith(text: '');
    }

    if (cleanText.length > 8) {
      cleanText = cleanText.substring(0, 8);
    }

    double value = double.parse(cleanText) / 100.0;
    String formatted = value.toStringAsFixed(2).replaceAll('.', ',');

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class QuadrasScreen extends StatefulWidget {
  const QuadrasScreen({super.key});

  @override
  State<QuadrasScreen> createState() => _QuadrasScreenState();
}

class _QuadrasScreenState extends State<QuadrasScreen> {
  final QuadraService _quadraService = QuadraService();

  // Estado da lupa de busca
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final Map<String, String> _exemplosImagens = {
    'Futebol Society':
        'https://images.unsplash.com/photo-1575361204480-aadea25e6e68?w=800',
    'Tênis':
        'https://images.unsplash.com/photo-1595435934249-5df7ed86e1c0?w=800',
    'Beach Tennis':
        'https://images.unsplash.com/photo-1612872087720-bb876e2e67d1?w=800',
    'Basquete':
        'https://images.unsplash.com/photo-1546519638-68e109498ffc?w=800',
  };

  final Map<String, IconData> _iconesModalidades = {
    'Futebol Society': Icons.sports_soccer,
    'Tênis': Icons.sports_tennis,
    'Beach Tennis': Icons.beach_access,
    'Basquete': Icons.sports_basketball,
  };

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (Route<dynamic> route) => false,
      );
    }
  }

  // Formulário modal para Criar (Create) ou Editar (Update)
  void _abrirFormularioQuadra({QuadraModel? quadraExistente}) {
    final bool isEdicao = quadraExistente != null;
    final formKey = GlobalKey<FormState>();

    final nomeController =
        TextEditingController(text: quadraExistente?.nome ?? '');
    final tipoController =
        TextEditingController(text: quadraExistente?.tipo ?? 'Futebol Society');
    final precoController = TextEditingController(
      text: quadraExistente != null
          ? quadraExistente.precoPorHora.toStringAsFixed(2).replaceAll('.', ',')
          : '',
    );
    final imagemController =
        TextEditingController(text: quadraExistente?.imagemUrl ?? '');

    bool salvando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Cabeçalho do modal
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isEdicao ? 'Editar Quadra' : 'Nova Quadra',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const Divider(),
                      const SizedBox(height: 10),

                      // Campo 1: Nome
                      TextFormField(
                        controller: nomeController,
                        decoration: const InputDecoration(
                          labelText: 'Nome da Quadra',
                          hintText: 'Ex: Quadra Society 1, Arena Beach',
                          prefixIcon: Icon(Icons.sports),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setModalState(() {}),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Informe o nome da quadra';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Campo 2: Tipo / Modalidade
                      DropdownButtonFormField<String>(
                        initialValue: _exemplosImagens.containsKey(tipoController.text)
                            ? tipoController.text
                            : 'Futebol Society',
                        decoration: const InputDecoration(
                          labelText: 'Modalidade / Tipo',
                          prefixIcon: Icon(Icons.category),
                          border: OutlineInputBorder(),
                        ),
                        items: _exemplosImagens.keys
                            .map((tipo) => DropdownMenuItem(
                                  value: tipo,
                                  child: Row(
                                    children: [
                                      Icon(_iconesModalidades[tipo] ?? Icons.sports,
                                          size: 18, color: Colors.green),
                                      const SizedBox(width: 8),
                                      Text(tipo),
                                    ],
                                  ),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              tipoController.text = val;
                              if (imagemController.text.trim().isEmpty &&
                                  _exemplosImagens.containsKey(val)) {
                                imagemController.text = _exemplosImagens[val]!;
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),

                      // Campo 3: Preço por hora com Máscara Monetária (R$ 0,00)
                      TextFormField(
                        controller: precoController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          CurrencyInputFormatter(),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Preço por Hora',
                          hintText: '0,00',
                          prefixText: 'R\$ ',
                          prefixIcon: Icon(Icons.attach_money),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setModalState(() {}),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Informe o valor por hora';
                          }
                          final clean = v.replaceAll('.', '').replaceAll(',', '.');
                          final parsed = double.tryParse(clean);
                          if (parsed == null || parsed <= 0) {
                            return 'Informe um valor maior que R\$ 0,00';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Campo 4: URL da Imagem (manipulada no Firestore)
                      TextFormField(
                        controller: imagemController,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: 'URL da Imagem (Firestore)',
                          hintText: 'https://...',
                          prefixIcon: const Icon(Icons.image),
                          suffixIcon: imagemController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  tooltip: 'Limpar link',
                                  onPressed: () {
                                    imagemController.clear();
                                    setModalState(() {});
                                  },
                                )
                              : null,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setModalState(() {}),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Informe a URL da imagem da quadra';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),

                      // Atalhos para preencher imagens de teste
                      const Text(
                        'Sugestões rápidas de imagem:',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _exemplosImagens.entries.map((entry) {
                          final isSelected =
                              imagemController.text.trim() == entry.value;
                          final icon =
                              _iconesModalidades[entry.key] ?? Icons.sports;
                          return ActionChip(
                            label: Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? Colors.green.shade900
                                    : Colors.black87,
                              ),
                            ),
                            avatar: Icon(
                              icon,
                              size: 15,
                              color: isSelected
                                  ? Colors.green.shade800
                                  : Colors.grey.shade700,
                            ),
                            backgroundColor: isSelected
                                ? Colors.green.shade100
                                : Colors.grey.shade100,
                            side: BorderSide(
                              color: isSelected
                                  ? Colors.green
                                  : Colors.grey.shade300,
                              width: isSelected ? 1.5 : 1,
                            ),
                            onPressed: () {
                              setModalState(() {
                                tipoController.text = entry.key;
                                imagemController.text = entry.value;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),

                      // Seção de Pré-visualização da Imagem ao Vivo
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.visibility,
                                  size: 16, color: Colors.green),
                              SizedBox(width: 6),
                              Text(
                                'Pré-visualização do Card',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          if (imagemController.text.trim().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: Colors.green.shade300),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle,
                                      size: 12, color: Colors.green),
                                  SizedBox(width: 4),
                                  Text(
                                    'Ao vivo',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Card interativo de Pré-visualização
                      Container(
                        height: 180,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: imagemController.text.trim().isNotEmpty
                                ? Colors.green.shade400
                                : Colors.grey.shade300,
                            width: imagemController.text.trim().isNotEmpty
                                ? 1.5
                                : 1,
                          ),
                          boxShadow: imagemController.text.trim().isNotEmpty
                              ? const [
                                  BoxShadow(
                                    color: Color(0x1A000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: imagemController.text.trim().isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_photo_alternate_outlined,
                                        size: 46,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Nenhuma imagem selecionada',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Insira uma URL acima ou clique em uma sugestão para ver o preview',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    imagemController.text.trim(),
                                    fit: BoxFit.cover,
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                      if (loadingProgress == null) {
                                        return child;
                                      }
                                      return Container(
                                        color: Colors.grey.shade100,
                                        child: Center(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const SizedBox(
                                                width: 28,
                                                height: 28,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2.5,
                                                  color: Colors.green,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              Text(
                                                'Carregando imagem...',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                    errorBuilder:
                                        (context, error, stackTrace) {
                                      return Container(
                                        color: Colors.red.shade50,
                                        padding: const EdgeInsets.all(16),
                                        child: Center(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.broken_image_rounded,
                                                color: Colors.redAccent,
                                                size: 40,
                                              ),
                                              const SizedBox(height: 8),
                                              const Text(
                                                'URL de imagem inválida ou inacessível',
                                                style: TextStyle(
                                                  color: Colors.redAccent,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Verifique o link ou clique em uma das sugestões acima',
                                                style: TextStyle(
                                                  color: Colors.grey.shade600,
                                                  fontSize: 11,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  // Overlay degradê com dados ao vivo do card
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            Color(0xD9000000),
                                          ],
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  child: Text(
                                                    tipoController.text,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  nomeController.text
                                                          .trim()
                                                          .isNotEmpty
                                                      ? nomeController.text
                                                          .trim()
                                                      : 'Nome da Quadra',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            precoController.text
                                                    .trim()
                                                    .isNotEmpty
                                                ? 'R\$ ${precoController.text.trim()} / h'
                                                : 'R\$ 0,00 / h',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 16),

                      // Botão de Ação (Salvar / Atualizar)
                      ElevatedButton.icon(
                        onPressed: salvando
                            ? null
                            : () async {
                                if (!(formKey.currentState?.validate() ??
                                    false)) {
                                  return;
                                }

                                setModalState(() => salvando = true);

                                final messenger = ScaffoldMessenger.of(context);
                                try {
                                  final double preco = double.parse(
                                      precoController.text
                                          .trim()
                                          .replaceAll('.', '')
                                          .replaceAll(',', '.'));

                                  final quadra = QuadraModel(
                                    id: quadraExistente?.id,
                                    nome: nomeController.text.trim(),
                                    tipo: tipoController.text.trim(),
                                    precoPorHora: preco,
                                    imagemUrl: imagemController.text.trim(),
                                  );

                                  if (isEdicao) {
                                    await _quadraService.updateQuadra(quadra);
                                  } else {
                                    await _quadraService.createQuadra(quadra);
                                  }

                                  if (ctx.mounted) {
                                    Navigator.of(ctx).pop();
                                  }
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(isEdicao
                                          ? 'Quadra atualizada com sucesso!'
                                          : 'Quadra cadastrada com sucesso!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                } catch (e) {
                                  setModalState(() => salvando = false);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('Erro ao salvar: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                        icon: salvando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(isEdicao ? Icons.save : Icons.add),
                        label: Text(
                          salvando
                              ? 'Salvando...'
                              : (isEdicao
                                  ? 'SALVAR ALTERAÇÕES'
                                  : 'CADASTRAR QUADRA'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Diálogo de confirmação para Excluir (Delete)
  void _confirmarExclusao(QuadraModel quadra) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('Excluir Quadra'),
            ],
          ),
          content: Text(
            'Tem certeza que deseja excluir "${quadra.nome}" do Firestore? Esta ação não pode ser desfeita.',
          ),
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
                final messenger = ScaffoldMessenger.of(context);
                try {
                  if (quadra.id != null) {
                    await _quadraService.deleteQuadra(quadra.id!);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Quadra excluída com sucesso!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Erro ao excluir: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('EXCLUIR'),
            ),
          ],
        );
      },
    );
  }

  // Widget para os Cards de Métricas do Dashboard
  Widget _buildDashboardMetrics(List<QuadraModel> quadras) {
    final int totalQuadras = quadras.length;

    // Cálculo do Ticket Médio por hora
    final double ticketMedio = totalQuadras > 0
        ? quadras.fold<double>(0.0, (sum, q) => sum + q.precoPorHora) /
            totalQuadras
        : 0.0;

    // Cálculo do Top 3 tipos de quadras mais cadastradas
    final Map<String, int> contagemTipos = {};
    for (final q in quadras) {
      final tipo = q.tipo.trim().isEmpty ? 'Outros' : q.tipo.trim();
      contagemTipos[tipo] = (contagemTipos[tipo] ?? 0) + 1;
    }

    final topTipos = contagemTipos.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final top3 = topTipos.take(3).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título da seção de Dashboards
          const Row(
            children: [
              Icon(Icons.dashboard_outlined, color: Colors.green, size: 20),
              SizedBox(width: 8),
              Text(
                'Dashboard e Indicadores',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Linha com Quantidade e Ticket Médio
          Row(
            children: [
              // Métrica 1: Quantidade de Quadras Cadastradas
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F8F1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.sports_tennis,
                                color: Colors.white, size: 16),
                          ),
                          Text(
                            '$totalQuadras',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Total de Quadras',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'Cadastradas no Firestore',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Métrica 2: Ticket Médio de Cada
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.monetization_on_outlined,
                                color: Colors.white, size: 16),
                          ),
                          Text(
                            'R\$ ${ticketMedio.toStringAsFixed(2).replaceAll('.', ',')}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E40AF),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Ticket Médio / Hora',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'Média de valor por locação',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Métrica 3: Top 3 Tipos de Quadras
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.emoji_events_outlined,
                        color: Color(0xFFD97706), size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Top 3 Tipos de Quadras',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (top3.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Cadastre quadras para visualizar o ranking de modalidades.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  )
                else
                  Column(
                    children: List.generate(top3.length, (index) {
                      final item = top3[index];
                      final icon =
                          _iconesModalidades[item.key] ?? Icons.sports;
                      final double percentual = totalQuadras > 0
                          ? (item.value / totalQuadras)
                          : 0.0;

                      final List<String> posicoes = ['🥇 1º', '🥈 2º', '🥉 3º'];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  posicoes[index],
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(icon, size: 14, color: Colors.black87),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    item.key,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${item.value} ${item.value == 1 ? 'quadra' : 'quadras'} (${(percentual * 100).toStringAsFixed(0)}%)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: percentual,
                                minHeight: 6,
                                backgroundColor: const Color(0xFFFDE68A),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  index == 0
                                      ? const Color(0xFFD97706)
                                      : (index == 1
                                          ? const Color(0xFF6B7280)
                                          : const Color(0xFFB45309)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F6),
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: 'Pesquisar por nome ou modalidade...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val);
                },
              )
            : const Row(
                children: [
                  Icon(Icons.dashboard_customize_outlined, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Gerenciamento de Quadras',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          // Botão da Lupa de Busca
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Fechar pesquisa',
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Pesquisar quadras',
              onPressed: () {
                setState(() => _isSearching = true);
              },
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Mais opções',
            onSelected: (value) {
              if (value == 'sair') {
                _logout(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'sair',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.redAccent, size: 20),
                    SizedBox(width: 10),
                    Text(
                      'Sair',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1, // Quadras é a aba 1
        onDestinationSelected: (idx) {
          if (idx == 0) {
            Navigator.pushReplacementNamed(context, '/home');
          }
        },
        indicatorColor: Colors.green.shade100,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: Colors.green),
            label: 'Perfil',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: Colors.green),
            label: 'Quadras',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormularioQuadra(),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          'Nova Quadra',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<QuadraModel>>(
          stream: _quadraService.streamQuadras(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.green),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 8),
                    Text('Erro ao carregar quadras: ${snapshot.error}'),
                  ],
                ),
              );
            }

            final todasQuadras = snapshot.data ?? [];

            // Filtro aplicado pela Lupa de Busca
            final quadras = todasQuadras.where((q) {
              if (_searchQuery.trim().isEmpty) return true;
              final termo = _searchQuery.trim().toLowerCase();
              return q.nome.toLowerCase().contains(termo) ||
                  q.tipo.toLowerCase().contains(termo);
            }).toList();

            return Column(
              children: [
                // Seção de Dashboards (Quantidade, Ticket Médio, Top 3 Tipos)
                _buildDashboardMetrics(todasQuadras),

                // Cabeçalho da Lista de Quadras com Status da Busca
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Quadras Cadastradas',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          if (_searchQuery.trim().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${quadras.length} encontrada(s)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade900,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_searchQuery.trim().isNotEmpty)
                        InkWell(
                          onTap: () {
                            setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                            });
                          },
                          child: const Row(
                            children: [
                              Icon(Icons.clear,
                                  size: 14, color: Colors.redAccent),
                              SizedBox(width: 2),
                              Text(
                                'Limpar busca',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.redAccent),
                              ),
                            ],
                          ),
                        )
                      else
                        Text(
                          '${todasQuadras.length} no total',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),

                // Listagem de Quadras
                Expanded(
                  child: quadras.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _searchQuery.trim().isNotEmpty
                                      ? Icons.search_off_rounded
                                      : Icons.sports_soccer_outlined,
                                  size: 64,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _searchQuery.trim().isNotEmpty
                                      ? 'Nenhuma quadra encontrada para "$_searchQuery"'
                                      : 'Nenhuma quadra cadastrada no momento',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _searchQuery.trim().isNotEmpty
                                      ? 'Verifique a ortografia ou tente pesquisar por outro esporte/nome.'
                                      : 'Toque no botão "+ Nova Quadra" para adicionar seu primeiro item com foto no Firestore.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                if (_searchQuery.trim().isNotEmpty)
                                  TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _searchQuery = '';
                                        _searchController.clear();
                                      });
                                    },
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Limpar pesquisa'),
                                  )
                                else
                                  ElevatedButton.icon(
                                    onPressed: () => _abrirFormularioQuadra(),
                                    icon: const Icon(Icons.add),
                                    label:
                                        const Text('Cadastrar Primeira Quadra'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(
                              left: 16, right: 16, top: 4, bottom: 80),
                          itemCount: quadras.length,
                          itemBuilder: (context, index) {
                            final quadra = quadras[index];

                            return Card(
                              margin: const EdgeInsets.only(bottom: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 3,
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Imagem da Quadra
                                  SizedBox(
                                    height: 160,
                                    width: double.infinity,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (quadra.imagemUrl.isNotEmpty)
                                          Image.network(
                                            quadra.imagemUrl,
                                            fit: BoxFit.cover,
                                            loadingBuilder: (context, child,
                                                loadingProgress) {
                                              if (loadingProgress == null) {
                                                return child;
                                              }
                                              return Container(
                                                color: Colors.grey.shade200,
                                                child: const Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.green,
                                                  ),
                                                ),
                                              );
                                            },
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                              return Container(
                                                color: Colors.grey.shade300,
                                                child: const Center(
                                                  child: Icon(
                                                    Icons.sports_tennis,
                                                    size: 60,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              );
                                            },
                                          )
                                        else
                                          Container(
                                            color: Colors.grey.shade300,
                                            child: const Center(
                                              child: Icon(
                                                Icons.sports_tennis,
                                                size: 60,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                        // Badge com o Tipo / Modalidade sobre a imagem
                                        Positioned(
                                          top: 12,
                                          left: 12,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: const Color(0xA6000000),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  _iconesModalidades[
                                                          quadra.tipo] ??
                                                      Icons.label,
                                                  size: 14,
                                                  color: Colors.white,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  quadra.tipo,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Informações e botões de ação
                                  Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                quadra.nome,
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'R\$ ${quadra.precoPorHora.toStringAsFixed(2).replaceAll('.', ',')} / hora',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'ID: ${quadra.id ?? ""}',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color:
                                                      Colors.grey.shade500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Botão Editar (Update)
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined,
                                              color: Colors.blueGrey),
                                          tooltip: 'Editar Quadra',
                                          onPressed: () =>
                                              _abrirFormularioQuadra(
                                                  quadraExistente: quadra),
                                        ),

                                        // Botão Excluir (Delete)
                                        IconButton(
                                          icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.redAccent),
                                          tooltip: 'Excluir Quadra',
                                          onPressed: () =>
                                              _confirmarExclusao(quadra),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
