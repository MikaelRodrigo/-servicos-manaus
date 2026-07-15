import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Marca do app -- um "badge" circular com gradiente na cor de destaque e o
/// ícone de ferramenta, usado tanto na tela de login quanto na splash de
/// carregamento inicial (`_PortaDeEntrada`, main.dart). Extraído para um
/// widget próprio para garantir que as duas telas usem exatamente a mesma
/// marca, sem duas cópias que podem divergir com o tempo -- antes disso, a
/// tela de login usava só um `Icon` solto (sem gradiente, sem sombra, sem
/// entrada animada) e a splash inicial não tinha marca nenhuma, só um
/// spinner sozinho no branco.
///
/// Entra na tela com um fade + leve "estouro" de escala (`Curves.easeOutBack`)
/// -- é o toque de "vida" pedido: a primeira coisa que a pessoa vê ao abrir
/// o app (ou a tela de login) não aparece estática, ela chega.
class LogoApp extends StatelessWidget {
  final double tamanho;

  const LogoApp({super.key, this.tamanho = 96});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutBack,
      builder: (context, progresso, filho) {
        return Opacity(
          // `clamp` porque `easeOutBack` ultrapassa 1.0 momentaneamente (é o
          // que dá o efeito de "estouro") -- `Opacity` não aceita valor fora
          // de 0..1.
          opacity: progresso.clamp(0.0, 1.0),
          child: Transform.scale(scale: progresso, child: filho),
        );
      },
      child: Container(
        width: tamanho,
        height: tamanho,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.destaque,
              AppColors.destaque.withValues(alpha: 0.72),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.destaque.withValues(alpha: 0.35),
              blurRadius: tamanho * 0.28,
              offset: Offset(0, tamanho * 0.09),
            ),
          ],
        ),
        child: Icon(Icons.handyman_rounded, size: tamanho * 0.46, color: Colors.white),
      ),
    );
  }
}
