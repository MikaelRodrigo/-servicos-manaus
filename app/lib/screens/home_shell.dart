import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import 'editar_perfil_screen.dart';
import 'mapa_screen.dart';
import 'meus_clientes_screen.dart';
import 'perfil_cliente_screen.dart';
import 'servicos_screen.dart';

/// Margem entre a barra flutuante e as bordas do dispositivo (laterais e
/// inferior) -- é o que garante ela ficar "suspensa" em vez de colada,
/// pedido explícito de design.
const _margemBarraFlutuante = 20.0;

/// Altura da cápsula em si (sem contar o botão circular de Home, que vaza
/// pra cima dela -- ver `_construirBarraFlutuante`). Reduzida (64 -> 58,
/// pedido explícito) pra ocupar menos espaço vertical da tela -- só a
/// altura muda; largura/margens laterais continuam as mesmas.
const _alturaBarraFlutuante = 58.0;

/// Diâmetro do botão circular de destaque (Home), sempre no centro
/// geométrico da barra.
const _diametroBotaoHome = 56.0;

/// Um item de navegação da barra flutuante -- ícone (normal/selecionado),
/// rótulo e o ÍNDICE que ele representa dentro de `telas`/`IndexedStack`.
/// Esse índice é fixo por papel (ver `build`) -- não é a posição em que o
/// item é desenhado na barra, que varia (alguns vão pro lado esquerdo do
/// botão de Home, outros pro direito).
class _ItemNavegacao {
  final IconData icone;
  final IconData iconeSelecionado;
  final String rotulo;
  final int indice;

  const _ItemNavegacao({
    required this.icone,
    required this.iconeSelecionado,
    required this.rotulo,
    required this.indice,
  });
}

/// Casca de navegação da área logada -- uma barra flutuante em formato de
/// cápsula, suspensa sobre o conteúdo, alternando entre as áreas reais do
/// app, adaptada por papel:
///   Cliente:      Solicitações · HOME (centro, destaque) · Meus dados
///   Profissional: Solicitações · Clientes · HOME (centro, destaque) · Meus dados
///
/// "Meus dados" é a MESMA ideia nos dois papéis (a própria conta), só que
/// aponta pra telas diferentes -- `PerfilClienteScreen` (cliente) ou
/// `EditarPerfilScreen` (profissional, que antes só era alcançável por um
/// ícone de lápis escondido no AppBar do mapa; agora tem um lugar fixo e
/// óbvio, igual ao "Perfil" que o cliente já tinha). "Clientes" só existe
/// pro profissional -- é uma visão nova (ver `MeusClientesScreen`), sem
/// equivalente pro lado do cliente.
///
/// Usa `IndexedStack` (não troca de widget, só de VISIBILIDADE) para que
/// trocar de aba não jogue fora o estado de cada tela -- ex.: se você
/// rolou o mapa ou já buscou profissionais, isso continua lá ao voltar
/// da aba "Solicitações", em vez de recarregar do zero.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _indiceAtual = 0;

  @override
  Widget build(BuildContext context) {
    final papel = context.watch<AuthProvider>().usuario?.papel;
    final ehProfissional = papel == Papel.profissional;

    final telas = [
      const MapaScreen(),
      const ServicosScreen(),
      if (ehProfissional) const MeusClientesScreen(),
      ehProfissional ? const EditarPerfilScreen() : const PerfilClienteScreen(),
    ];

    // Se o número de abas mudar (ex.: sessão trocou de papel) e o índice
    // atual ficasse fora da lista, voltamos para a primeira aba em vez de
    // deixar o IndexedStack apontar para um índice inexistente.
    final indiceSeguro = _indiceAtual < telas.length ? _indiceAtual : 0;

    // O item de índice 0 (Home) vira o botão circular de destaque, sempre
    // no centro geométrico da barra -- os demais (Solicitações, Clientes,
    // Meus dados) se distribuem nos dois lados dela (ver
    // `_construirBarraFlutuante`), nunca dentro do mesmo Row que o botão
    // de Home.
    final itensLaterais = [
      const _ItemNavegacao(
        icone: Icons.assignment_outlined,
        iconeSelecionado: Icons.assignment,
        rotulo: 'Solicitações',
        indice: 1,
      ),
      if (ehProfissional)
        const _ItemNavegacao(
          icone: Icons.groups_outlined,
          iconeSelecionado: Icons.groups,
          rotulo: 'Clientes',
          indice: 2,
        ),
      _ItemNavegacao(
        icone: Icons.person_outline,
        iconeSelecionado: Icons.person,
        rotulo: 'Meus dados',
        indice: telas.length - 1,
      ),
    ];

    // Divide os itens laterais entre esquerda e direita do botão central --
    // com um número ÍMPAR deles (caso do profissional: Solicitações,
    // Clientes, Meus dados), o lado esquerdo fica com um a mais. O botão
    // de Home continua exatamente no centro geométrico da barra de
    // qualquer forma, já que ele não faz parte deste Row (ver Stack em
    // `_construirBarraFlutuante`).
    final metade = (itensLaterais.length / 2).ceil();
    final itensEsquerda = itensLaterais.sublist(0, metade);
    final itensDireita = itensLaterais.sublist(metade);

    return Scaffold(
      body: Stack(
        children: [
          // `Positioned.fill` garante que este fundo ocupe o Stack
          // inteiro (em vez de depender do tamanho "preferido" dos
          // filhos) -- é o que faz a área de conteúdo continuar
          // preenchendo a tela normalmente por trás da barra flutuante.
          //
          // O padding inferior reserva espaço pra nenhuma tela desenhar
          // conteúdo por baixo da barra -- sem isso, a última linha da
          // grade de categorias (por exemplo) ficaria escondida atrás
          // dela. O valor cobre a margem + altura da cápsula + a área de
          // gesto do sistema (barra "pill"/home indicator do
          // Android/iOS), com uma folga extra.
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: _margemBarraFlutuante +
                    _alturaBarraFlutuante +
                    MediaQuery.of(context).padding.bottom +
                    12,
              ),
              child: IndexedStack(index: indiceSeguro, children: telas),
            ),
          ),
          _construirBarraFlutuante(
            context,
            indiceAtual: indiceSeguro,
            itensEsquerda: itensEsquerda,
            itensDireita: itensDireita,
          ),
        ],
      ),
    );
  }

  /// Barra de navegação flutuante -- substitui o `NavigationBar` padrão
  /// (fixo, colado nas bordas) por um contêiner em formato de cápsula
  /// "suspensa" sobre o conteúdo, com o item Home elevado num botão
  /// circular de destaque no centro geométrico. Pedido explícito de
  /// design; nenhuma navegação nova -- os mesmos destinos/índices de
  /// antes, só a casca visual muda.
  Widget _construirBarraFlutuante(
    BuildContext context, {
    required int indiceAtual,
    required List<_ItemNavegacao> itensEsquerda,
    required List<_ItemNavegacao> itensDireita,
  }) {
    return Positioned(
      left: _margemBarraFlutuante,
      right: _margemBarraFlutuante,
      // Soma a área segura do sistema (gesto/home indicator) à margem --
      // sem isso, em aparelhos com navegação por gestos a barra ficaria
      // colada (ou parcialmente escondida) atrás dela.
      bottom: _margemBarraFlutuante + MediaQuery.of(context).padding.bottom,
      child: SizedBox(
        // Altura extra pro botão de Home "vazar" pra cima da cápsula --
        // mesma técnica de sobreposição usada no cartão do mapa (ver
        // `mapa_screen.dart`, `_construirCabecalhoComMapa`).
        height: _alturaBarraFlutuante + _diametroBotaoHome / 2,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // A cápsula em si -- fundo branco, cantos totalmente
            // arredondados (raio = metade da altura, formato de "pílula"),
            // sombra por baixo pra dar a sensação de flutuar sobre a
            // tela.
            Container(
              height: _alturaBarraFlutuante,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.superficie,
                borderRadius: BorderRadius.circular(_alturaBarraFlutuante / 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              // `Material` transparente por dentro -- sem ele, o efeito de
              // toque (ripple) dos `InkWell` abaixo não tem onde pintar
              // direito (a decoração do `Container` sozinha não serve de
              // superfície de tinta).
              child: Material(
                color: Colors.transparent,
                child: Row(
                  children: [
                    for (final item in itensEsquerda)
                      Expanded(child: _botaoNavegacao(item, indiceAtual)),
                    // Vão reservado embaixo do botão circular de Home --
                    // ele não faz parte deste Row (fica no Stack, por
                    // cima), mas o espaço precisa existir pra não
                    // sobrepor os ícones vizinhos.
                    const SizedBox(width: _diametroBotaoHome + 8),
                    for (final item in itensDireita)
                      Expanded(child: _botaoNavegacao(item, indiceAtual)),
                  ],
                ),
              ),
            ),
            // Botão circular de destaque (Home) -- cor sólida de destaque
            // (não branca, pra se sobressair da cápsula), com elevação
            // própria e uma borda branca fina simulando "flutuar" por
            // cima da barra.
            Positioned(top: 0, child: _botaoHome(indiceAtual)),
          ],
        ),
      ),
    );
  }

  /// Um item lateral (ícone + rótulo) da cápsula -- toda a área (ícone e
  /// texto) reage ao toque, não só o ícone.
  Widget _botaoNavegacao(_ItemNavegacao item, int indiceAtual) {
    final selecionado = indiceAtual == item.indice;
    final cor = selecionado ? AppColors.destaque : AppColors.textoSecundario;

    return InkWell(
      onTap: () => setState(() => _indiceAtual = item.indice),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selecionado ? item.iconeSelecionado : item.icone, color: cor, size: 24),
          const SizedBox(height: 2),
          Text(
            item.rotulo,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selecionado ? FontWeight.w600 : FontWeight.w500,
              color: cor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// O botão circular de destaque (Home) -- `Material` + `CircleBorder`
  /// dão o formato redondo, a elevação leve e o `InkWell` com toque
  /// certinho na área circular (não num quadrado invisível ao redor).
  Widget _botaoHome(int indiceAtual) {
    const indiceHome = 0;
    final selecionado = indiceAtual == indiceHome;

    return Material(
      color: AppColors.destaque,
      shape: const CircleBorder(side: BorderSide(color: AppColors.superficie, width: 3)),
      elevation: 4,
      shadowColor: AppColors.destaque.withValues(alpha: 0.5),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => setState(() => _indiceAtual = indiceHome),
        child: SizedBox(
          width: _diametroBotaoHome,
          height: _diametroBotaoHome,
          child: Icon(
            selecionado ? Icons.home : Icons.home_outlined,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }
}
