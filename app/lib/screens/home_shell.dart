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

/// Redução TOTAL de largura da cápsula, em cm, acumulada ao longo de
/// pedidos sucessivos: 1,9cm + 2cm = 3,9cm. Sempre CENTRALIZADA -- ver
/// `margemLateral` em `_construirBarraFlutuante`, que soma METADE disto a
/// cada lado (encolhe a largura total nesse valor exato sem tirar a
/// cápsula do centro).
const _reducaoLarguraCm = 1.9 + 2.0;

/// Altura da cápsula -- 58 (valor de uma rodada anterior) + 0,2cm (pedido
/// explícito). Todos os itens (Home incluído -- ele não tem mais destaque
/// nenhum, ver comentário da classe) vivem dentro dessa altura, sem vazar.
final _alturaBarraFlutuante = 58.0 + _cmParaPx(0.2);

/// cm -> pixels lógicos, mesma conversão usada em `mapa_screen.dart`
/// (`_cmParaPx`) -- repetida aqui porque aquela é privada ao próprio
/// arquivo. Se um dia isso for usado num terceiro lugar, vale extrair para
/// um utilitário compartilhado.
double _cmParaPx(double cm) => cm / 2.54 * 160;

/// Tamanho dos ícones do menu -- pedido explícito: 30% maiores que o
/// tamanho original (24).
const _tamanhoIconeMenu = 24.0 * 1.3;

/// Um item de navegação da barra flutuante -- ícone (normal/selecionado),
/// rótulo e o ÍNDICE que ele representa dentro de `telas`/`IndexedStack`.
/// Esse índice é fixo por papel (ver `build`) -- não é a posição em que o
/// item é desenhado na barra, que varia (metade dos itens vai pro lado
/// esquerdo do Home, a outra metade pro direito -- ver
/// `_construirBarraFlutuante`).
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
/// app:
///   Cliente:      Rendimentos · Perfil · Início · Solicitações
///   Profissional: Rendimentos · Perfil · Início · Clientes · Solicitações
///
/// O item "Início" (Home) é PADRÃO, igual a todos os outros -- pedido
/// explícito: sem cor de destaque, sem círculo, sem elevação própria; o
/// mesmo ícone-em-cima/rótulo-embaixo, a mesma cor de seleção
/// (`AppColors.destaque` quando ativo) que os demais. Fica no CENTRO
/// geométrico da linha de botões (metade dos outros itens de cada lado,
/// ver `metade` em `build`), mas isso é só POSIÇÃO -- visualmente ele não
/// se distingue em nada dos vizinhos.
///
/// "Clientes" (visão do profissional sobre a própria carteira, ver
/// `MeusClientesScreen`) é o único item sem equivalente do lado do
/// cliente -- entra como item A MAIS só para quem é profissional.
///
/// "Perfil" é a MESMA ideia nos dois papéis (a própria conta), só que
/// aponta pra telas diferentes -- `PerfilClienteScreen` (cliente) ou
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
      const MapaScreen(), // Início = 0
      const RendimentosScreen(), // Rendimentos = 1
      ehProfissional ? const EditarPerfilScreen() : const PerfilClienteScreen(), // Perfil = 2
      if (ehProfissional) const MeusClientesScreen(), // Clientes = 3 (só profissional)
      const ServicosScreen(), // Solicitações = último índice
    ];
    final indiceSolicitacoes = telas.length - 1;

    // Se o número de abas mudar (ex.: sessão trocou de papel) e o índice
    // atual ficasse fora da lista, voltamos para a primeira aba em vez de
    // deixar o IndexedStack apontar para um índice inexistente.
    final indiceSeguro = _indiceAtual < telas.length ? _indiceAtual : 0;

    // Item de Início (Home) -- PADRÃO, igual a todos os outros (pedido
    // explícito, ver comentário da classe): mesmo tratamento visual de
    // `_botaoNavegacao`, só entra separado dos "itensLaterais" pra poder
    // ficar exatamente no meio deles (ver split logo abaixo).
    const itemHome = _ItemNavegacao(
      icone: Icons.home_outlined,
      iconeSelecionado: Icons.home,
      rotulo: 'Início',
      indice: 0,
    );

    final itensLaterais = [
      // "$" no ícone -- pedido explícito: `monetization_on` é uma moeda
      // com o símbolo "$" desenhado nela (diferente de `assessment`, que
      // usado antes, era só um gráfico de barras sem nenhum "$").
      const _ItemNavegacao(
        icone: Icons.monetization_on_outlined,
        iconeSelecionado: Icons.monetization_on,
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

    // Divide os itens laterais entre esquerda e direita do Início -- com
    // um número ÍMPAR deles (caso do cliente: Rendimentos, Perfil,
    // Solicitações -- 3), o lado esquerdo fica com um a mais.
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
            itemHome: itemHome,
            itensEsquerda: itensEsquerda,
            itensDireita: itensDireita,
          ),
        ],
      ),
    );
  }

  /// Barra de navegação flutuante -- um contêiner em formato de cápsula
  /// "suspensa" sobre o conteúdo. Todos os itens (Início incluído) usam o
  /// MESMO widget (`_botaoNavegacao`) e o MESMO tratamento de layout
  /// (`Expanded`, distribuição igual de espaço) -- nenhum se destaca dos
  /// outros.
  ///
  /// Largura reduzida em 3,9cm no total e mantida centralizada: soma
  /// METADE dessa redução à margem de CADA lado -- é o que encolhe a
  /// largura total nesse valor exato sem tirar a cápsula do centro (mesma
  /// técnica já usada para o cartão do mapa, ver `_cmParaPx` em
  /// `mapa_screen.dart`).
  Widget _construirBarraFlutuante(
    BuildContext context, {
    required int indiceAtual,
    required _ItemNavegacao itemHome,
    required List<_ItemNavegacao> itensEsquerda,
    required List<_ItemNavegacao> itensDireita,
  }) {
    final margemLateral = _margemBarraFlutuante + _cmParaPx(_reducaoLarguraCm) / 2;

    return Positioned(
      left: margemLateral,
      right: margemLateral,
      // Soma a área segura do sistema (gesto/home indicator) à margem --
      // sem isso, em aparelhos com navegação por gestos a barra ficaria
      // colada (ou parcialmente escondida) atrás dela.
      bottom: _margemBarraFlutuante + MediaQuery.of(context).padding.bottom,
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
              for (final item in itensEsquerda)
                Expanded(child: _botaoNavegacao(item, indiceAtual)),
              Expanded(child: _botaoNavegacao(itemHome, indiceAtual)),
              for (final item in itensDireita)
                Expanded(child: _botaoNavegacao(item, indiceAtual)),
            ],
          ),
        ),
      ),
    );
  }

  /// Um item da cápsula -- ícone em cima, rótulo embaixo, toda a área
  /// reage ao toque (não só o ícone). MESMO widget para todos os itens,
  /// Início incluído -- pedido explícito de não destacar nenhum deles.
  Widget _botaoNavegacao(_ItemNavegacao item, int indiceAtual) {
    final selecionado = indiceAtual == item.indice;
    final cor = selecionado ? AppColors.destaque : AppColors.textoSecundario;

    return InkWell(
      onTap: () => setState(() => _indiceAtual = item.indice),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selecionado ? item.iconeSelecionado : item.icone, color: cor, size: _tamanhoIconeMenu),
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
}
