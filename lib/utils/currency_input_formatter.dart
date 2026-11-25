import 'package:flutter/services.dart';

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

/// Converte o texto "1.234,56" do campo monetário para double.
double? parseMoeda(String texto) {
  final clean = texto.trim().replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(clean);
}

/// Formata um valor como "R$ 1234,56", no mesmo padrão da tela de quadras.
String formatarMoeda(double valor) {
  return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
}
