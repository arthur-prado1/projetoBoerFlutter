import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../services/user_services.dart';
import '../model/user_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final UserService _userService = UserService();

  final _phoneMaskFormatter = MaskTextInputFormatter(
    mask: '(##) #####-####',
    filter: {"#": RegExp(r'[0-9]')},
  );

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

  // Modal para atualizar dados cadastrais do usuário no Firestore
  void _abrirModalEditarPerfil(UserModel user) {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController(text: user.name);
    final phoneController = TextEditingController(text: user.phone);
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
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Editar Dados do Perfil',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nomeController,
                      decoration: const InputDecoration(
                        labelText: 'Nome Completo',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Informe seu nome';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [_phoneMaskFormatter],
                      decoration: const InputDecoration(
                        labelText: 'Telefone',
                        prefixIcon: Icon(Icons.phone),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Informe seu telefone';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: salvando
                          ? null
                          : () async {
                              if (!(formKey.currentState?.validate() ?? false)) {
                                return;
                              }

                              setModalState(() => salvando = true);
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                await _userService.updateUserProfile(
                                  name: nomeController.text.trim(),
                                  phone: phoneController.text.trim(),
                                );
                                if (ctx.mounted) {
                                  Navigator.of(ctx).pop();
                                }
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Perfil atualizado com sucesso!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } catch (e) {
                                setModalState(() => salvando = false);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Erro ao atualizar: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(salvando ? 'Salvando...' : 'SALVAR DADOS'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Tela principal do Usuário (mantendo o visual original de Bem-vindo e branding)
  Widget _buildUserHomeTab(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: StreamBuilder<UserModel?>(
            stream: _userService.streamUserProfile(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator(color: Colors.green);
              }

              final user = snapshot.data;
              final userName = user?.name.isNotEmpty == true
                  ? user!.name
                  : (FirebaseAuth.instance.currentUser?.displayName ??
                      'Jogador(a)');
              final userEmail = user?.email.isNotEmpty == true
                  ? user!.email
                  : (FirebaseAuth.instance.currentUser?.email ?? 'Não informado');
              final userPhone = user?.phone ?? 'Não informado';

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Ícone esportivo original do eQuadras
                  const Icon(
                    Icons.sports_tennis,
                    size: 90,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 8),

                  // Nome do Projeto
                  const Text(
                    'eQuadras',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Mensagem de Boas-Vindas
                  const Text(
                    'Bem-vindo(a),',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    userName,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Card com informações cadastrais do usuário (Firestore)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0A000000),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.green.shade50,
                              child: Text(
                                userName.isNotEmpty
                                    ? userName[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Dados da sua Conta',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    'Usuário autenticado no Firebase',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (user != null)
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    color: Colors.green, size: 20),
                                tooltip: 'Editar Perfil',
                                onPressed: () => _abrirModalEditarPerfil(user),
                              ),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          children: [
                            const Icon(Icons.email_outlined,
                                size: 18, color: Colors.grey),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                userEmail,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined,
                                size: 18, color: Colors.grey),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                userPhone.isNotEmpty
                                    ? userPhone
                                    : 'Telefone não cadastrado',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: userPhone.isNotEmpty
                                      ? Colors.black87
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Botão em Destaque para Acessar o Gerenciamento de Quadras
                  ElevatedButton.icon(
                    onPressed: () =>
                        Navigator.pushReplacementNamed(context, '/quadras'),
                    icon: const Icon(Icons.dashboard_customize_rounded),
                    label: const Text(
                      'GERENCIAR QUADRAS E DASHBOARDS',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 3,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Botão Sair da Conta
                  TextButton.icon(
                    onPressed: () => _logout(context),
                    icon: const Icon(Icons.logout, size: 18, color: Colors.redAccent),
                    label: const Text(
                      'Sair da Conta',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Perfil',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
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
        selectedIndex: 0,
        onDestinationSelected: (idx) {
          if (idx == 1) {
            Navigator.pushReplacementNamed(context, '/quadras');
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
      body: _buildUserHomeTab(context),
    );
  }
}
