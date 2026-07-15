import 'package:flutter/material.dart';

/// Avatar circular preenchido com a inicial de um nome -- usado como
/// fallback sempre que não há foto (ou a foto falha ao carregar), em
/// qualquer lugar do app que precise identificar uma pessoa visualmente
/// (cabeçalho do mapa, lista de clientes do profissional, etc.). Extraído
/// como widget compartilhado para as várias telas nunca divergirem nesse
/// visual -- cor de fundo puxa do tema (`colorScheme.primaryContainer`),
/// então acompanha automaticamente qualquer ajuste de paleta futuro.
class AvatarIniciais extends StatelessWidget {
  final String nome;
  final double tamanho;

  const AvatarIniciais({super.key, required this.nome, this.tamanho = 38});

  String get _inicial {
    final texto = nome.trim();
    return texto.isNotEmpty ? texto[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      alignment: Alignment.center,
      child: Text(
        _inicial,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: tamanho * 0.42,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
