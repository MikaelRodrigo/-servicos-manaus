import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import 'editar_perfil_screen.dart';
import 'mapa_screen.dart';
import 'meus_clientes_screen.dart';
import 'perfil_cliente_screen.dart';
import 'rendimentos_screen.dart';
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

/// Diâmetro do botão circular de destaque (Home), fixo na ponta ESQUERDA
/// da barra (ver `_construirBarraFlutuante` -- layout redesenhado a partir
/// do mockup enviado pelo usuário, que mostra Home fora do centro).
const _diametroBotaoHome = 56.0;

/// Cor do botão de Home -- pedido explícito de design (mockup mostra um
/// dourado/amarelo, diferente do azul `AppColors.destaque` usado no resto
/// do app). Constante LOCAL deste arquivo de propósito: não altera o azul
/// de destaque usado em botões/links do app inteiro, só este botão.
const _corBotaoHome = Color(0xFFF2B705);

/// cm -> pixels lógicos, mesma conversão usada em `mapa_screen.dart`
/// (`_cmParaPx`) -- repetida aqui porque aquela é privada ao próprio
/// arquivo. Se um dia isso for usado num terceiro lugar, vale extrair para
/// um utilitário compartilhado.
double _cmParaPx(double cm) => cm / 2.54 * 160;

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
/// app. Layout redesenhado a partir de um mockup enviado pelo usuário: o
/// botão de Home fica FIXO na ponta esquerda (não mais centralizado), e os
/// demais itens se distribuem à direita dele, na mesma ordem do mockup:
///   Cliente:      HOME (esquerda) · Rendimentos · Perfil · Solicitações
///   Profissional: HOME (esquerda) · Rendimentos · Perfil · Clientes · Solicitações
///
/// "Clientes" (visão do profissional sobre a própria carteira, ver
/// `MeusClientesScreen`) não está no mockup -- ele só mostrava 4 itens
/// genéricos, sem cobrir o caso do profissional. Em vez de remover essa
/// funcionalidade (não foi pedido), ela entra como um item A MAIS só para
/// quem é profissional, mantendo a mesma ordem/aparência do mockup para
/// tudo que ele de fato mostra.
///
/// "Perfil" é a MESMA ideia nos dois papéis (a própria conta, chamada
/// antes de "Meus dados" -- renomeada para bater com o rótulo do mockup),
/// só que aponta pra telas diferentes -- `PerfilClienteScreen` (cliente) ou
/// `EditarPerfilScreen` (profissional).
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
      const MapaScreen(), // Home = 0
      const RendimentosScreen(), // Rendimentos = 1
      ehProfissional ? const EditarPerfilScreen() : const PerfilClienteScreen(), // Perfil = 2
      if (ehProfissional) const MeusClientesScreen(), // Clientes = 3 (só profissional; fora do mockup, ver comentário da classe)
      const ServicosScreen(), // Solicitações = último índice
    ];
    final indiceSolicitacoes = telas.length - 1;

    // Se o número de abas mudar (ex.: sessão trocou de papel) e o índice
    // atual ficasse fora da lista, voltamos para a primeira aba em vez de
    // deixar o IndexedStack apontar para um índice inexistente.
    final indiceSeguro = _indiceAtual < telas.length ? _indiceAtual : 0;

    // O item de índice 0 (Home) vira o botão circular fixo na ESQUERDA da
    // barra (ver `_construirBarraFlutuante`) -- os demais entram, nesta
    // MESMA ordem, num Row à direita dele. Ordem e rótulos batem com o
    // mockup enviado pelo usuário; "Clientes" (só profissional) é o único
    // item fora dele, ver comentário no topo da classe.
    final itens = [
      const _ItemNavegacao(
        icone: Icons.assessment_outlined,
        iconeSelecionado: Icons.assessment,
        rotulo: 'Rendimentos',
        indice: 1,
      ),
      const _ItemNavegacao(
        icone: Icons.person_outline,
        iconeSelecionado: Icons.person,
        rotulo: 'Perfil',
        indice: 2,
      ),
      if (ehProfissional)
        const _ItemNavegacao(
          icone: Icons.groups_outlined,
          iconeSelecionado: Icons.groups,
          rotulo: 'Clientes',
          indice: 3,
        ),
      _ItemNavegacao(
        icone: Icons.fact_check_outlined,
        iconeSelecionado: Icons.fact_check,
        rotulo: 'Solicitações',
        indice: indiceSolicitacoes,
      ),
    ];

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
            itens: itens,
          ),
        ],
      ),
    );
  }

  /// Barra de navegação flutuante -- substitui o `NavigationBar` padrão
  /// (fixo, colado nas bordas) por um contêiner em formato de cápsula
  /// "suspensa" sobre o conteúdo, com o item Home num botão circular de
  /// destaque FIXO NA ESQUERDA (não mais centralizado -- redesenho a
  /// partir do mockup do usuário) e os demais itens preenchendo o resto da
  /// cápsula à direita dele, em Row.
  ///
  /// Largura reduzida em 1,9cm e mantida centralizada -- pedido explícito:
  /// em vez de esticar de ponta a ponta com uma margem fixa (como antes),
  /// soma METADE dos 1,9cm à margem de CADA lado -- é o que encolhe a
  /// largura total nesse valor exato sem tirar a cápsula do centro (mesma
  /// técnica já usada para o cartão do mapa, ver `_cmParaPx` em
  /// `mapa_screen.dart`).
  Widget _construirBarraFlutuante(
    BuildContext context, {
    required int indiceAtual,
    required List<_ItemNavegacao> itens,
  }) {
    final margemLateral = _margemBarraFlutuante + _cmParaPx(1.9) / 2;

    return Positioned(
      left: margemLateral,
      right: margemLateral,
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
          children: [
            // A cápsula em si -- fundo branco, cantos totalmente
            // arredondados (raio = metade da altura, formato de "pílula"),
            // sombra por baixo pra dar a sensação de flutuar sobre a
            // tela. Ancorada embaixo da SizedBox (mesma folga acima que
            // sobra pro botão de Home vazar).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
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
                      // Vão reservado à esquerda para o botão circular de
                      // Home -- ele não faz parte deste Row (fica no
                      // Stack, por cima, ancorado em `left: 0`), mas o
                      // espaço precisa existir pra não sobrepor o próximo
                      // ícone.
                      const SizedBox(width: _diametroBotaoHome + 4),
                      for (final item in itens) Expanded(child: _botaoNavegacao(item, indiceAtual)),
                    ],
                  ),
                ),
              ),
            ),
            // Botão circular de destaque (Home) -- fixo na ponta esquerda
            // da cápsula (`left: 0`, `top: 0`; antes ficava centralizado
            // via `alignment: Alignment.bottomCenter` do Stack, removido
            // porque agora cada Positioned decide sua própria posição),
            // cor própria (dourado, pedido de design) pra se sobressair,
            // com elevação própria e uma borda branca fina simulando
            // "flutuar" por cima da barra.
            Positioned(left: 0, top: 0, child: _botaoHome()),
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
  /// certinho na área circular (não num quadrado invisível ao redor). Sem
  /// variação visual por seleção (diferente dos itens laterais) -- o
  /// mockup mostra o círculo sempre dourado/preenchido, esteja a aba Home
  /// ativa ou não, então não precisa saber o índice atual.
  Widget _botaoHome() {
    const indiceHome = 0;

    return Material(
      color: _corBotaoHome,
      shape: const CircleBorder(side: BorderSide(color: AppColors.superficie, width: 3)),
      elevation: 4,
      shadowColor: _corBotaoHome.withValues(alpha: 0.5),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => setState(() => _indiceAtual = indiceHome),
        child: SizedBox(
          width: _diametroBotaoHome,
          height: _diametroBotaoHome,
          child: Icon(
            // Ícone de casa em contorno escuro sobre o círculo dourado --
            // pedido de design (mockup mostra o ícone em tom escuro, não
            // branco). `home_outlined` mesmo quando selecionado: o mockup
            // usa um traço fino em vez do ícone preenchido.
            Icons.home_outlined,
            color: AppColors.textoPrimario,
            size: 26,
          ),
        ),
      ),
    );
  }
}
