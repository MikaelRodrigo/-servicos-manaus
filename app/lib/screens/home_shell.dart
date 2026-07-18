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
/// pedidos sucessivos: 1,9cm (rodada anterior) + 2cm (pedido explícito
/// mais recente) = 3,9cm. Sempre CENTRALIZADA -- ver `margemLateral` em
/// `_construirBarraFlutuante`, que soma METADE disto a cada lado (encolhe
/// a largura total nesse valor exato sem tirar a cápsula do centro).
const _reducaoLarguraCm = 1.9 + 2.0;

/// Altura da cápsula -- 58 (valor de uma rodada anterior) + 0,2cm (pedido
/// explícito mais recente). Agora é a altura de TUDO: o botão de Home
/// deixou de vazar por cima dela (ver comentário da classe e de
/// `_botaoHome`), então não sobra nenhum espaço extra reservado no topo.
final _alturaBarraFlutuante = 58.0 + _cmParaPx(0.2);

/// Diâmetro do botão circular de Home -- agora um ITEM DENTRO da linha de
/// botões (pedido explícito: "mesma altura da linha horizontal"), por isso
/// precisa caber dentro de `_alturaBarraFlutuante` com folga, em vez de
/// vazar por cima dela como antes.
const _diametroBotaoHome = 44.0;

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
/// item é desenhado na barra, que varia (metade vai pro lado esquerdo do
/// botão de Home, a outra metade pro direito -- ver `_construirBarraFlutuante`).
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
///   Cliente:      Rendimentos · Perfil · HOME (centro) · Solicitações
///   Profissional: Rendimentos · Perfil · HOME (centro) · Clientes · Solicitações
///
/// O botão de Home fica sempre no CENTRO GEOMÉTRICO da linha de botões, na
/// MESMA altura dela (pedido explícito) -- diferente de uma versão anterior
/// deste arquivo, em que ele ficava fixo na ponta esquerda e vazava por
/// cima da cápsula. Agora ele é só mais um item DENTRO do `Row` (só que
/// com largura fixa e aparência distinta), então nunca sobrepõe nem
/// ultrapassa a altura da cápsula.
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
      const MapaScreen(), // Home = 0
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

    // Itens ao redor do botão de Home -- distribuídos à esquerda/direita
    // dele (ver `metade` abaixo) pra ele cair exatamente no CENTRO
    // geométrico da linha de botões, pedido explícito.
    final itensLaterais = [
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

    // Divide os itens laterais entre esquerda e direita do botão de Home --
    // com um número ÍMPAR deles (caso do profissional: Rendimentos, Perfil,
    // Clientes, Solicitações -- 4, na verdade par; só o caso do cliente, com
    // 3, é ímpar), o lado esquerdo fica com um a mais quando sobra resto.
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

  /// Barra de navegação flutuante -- um contêiner em formato de cápsula
  /// "suspensa" sobre o conteúdo, com o botão de Home no CENTRO da linha
  /// de botões, na mesma altura dela (pedido explícito -- ver comentário
  /// da classe).
  ///
  /// Largura reduzida em 3,9cm no total e mantida centralizada: soma
  /// METADE dessa redução à margem de CADA lado -- é o que encolhe a
  /// largura total nesse valor exato sem tirar a cápsula do centro (mesma
  /// técnica já usada para o cartão do mapa, ver `_cmParaPx` em
  /// `mapa_screen.dart`).
  Widget _construirBarraFlutuante(
    BuildContext context, {
    required int indiceAtual,
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
      // Sem SizedBox/Stack extra pra "vazar" pra cima -- o Home agora mora
      // DENTRO da linha de botões, então a cápsula já é a altura inteira
      // do componente.
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
              // Botão de Home -- largura FIXA (não Expanded), pra
              // continuar compacto e sempre cair exatamente no centro
              // geométrico entre os itens laterais (metade de cada lado
              // deles, ver `metade` em `build`), na MESMA altura da linha
              // (Row centraliza verticalmente por padrão).
              SizedBox(
                width: _diametroBotaoHome + 16,
                child: Center(child: _botaoHome()),
              ),
              for (final item in itensDireita)
                Expanded(child: _botaoNavegacao(item, indiceAtual)),
            ],
          ),
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

  /// O botão de destaque (Home) -- agora um ITEM DENTRO da linha de
  /// botões, centralizado nela e na mesma altura (pedido explícito),
  /// diferente de uma versão anterior deste arquivo, em que ele vazava
  /// por cima da cápsula. `Material` + `CircleBorder` seguem dando o
  /// formato redondo e o toque (`InkWell`) certinho na área circular.
  Widget _botaoHome() {
    const indiceHome = 0;

    return Material(
      color: _corBotaoHome,
      shape: const CircleBorder(side: BorderSide(color: AppColors.superficie, width: 3)),
      elevation: 2,
      shadowColor: _corBotaoHome.withValues(alpha: 0.5),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => setState(() => _indiceAtual = indiceHome),
        child: SizedBox(
          width: _diametroBotaoHome,
          height: _diametroBotaoHome,
          child: const Icon(
            // Ícone de casa em contorno escuro sobre o círculo dourado --
            // pedido de design anterior (mockup mostrava o ícone em tom
            // escuro, não branco).
            Icons.home_outlined,
            color: AppColors.textoPrimario,
            size: 22,
          ),
        ),
      ),
    );
  }
}
