import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/config/api_config.dart';
import '../data/models/perfil_profissional.dart';
import '../data/models/usuario.dart';
import '../data/services/api_client.dart';
import '../data/services/profissionais_service.dart';
import '../data/services/servicos_service.dart';
import '../providers/auth_provider.dart';

/// Tela de perfil público do profissional -- abre ao tocar no pino dele no
/// mapa. Mostra foto, descrição ("sobre mim"), a média de avaliações por
/// critério, a quantidade de serviços já prestados e o histórico de
/// portfólio (fotos + comentários de clientes anteriores).
///
/// Só recebe o `profissionalId` (não o objeto `Profissional` inteiro da
/// busca) porque busca os três recursos -- perfil, resumo e portfólio --
/// direto do backend em paralelo. Isso também permite abrir esta tela a
/// partir de qualquer lugar que só tenha o ID (ex.: um link futuro, ou a
/// tela de detalhe de um serviço).
class PerfilProfissionalScreen extends StatefulWidget {
  final String profissionalId;

  const PerfilProfissionalScreen({super.key, required this.profissionalId});

  @override
  State<PerfilProfissionalScreen> createState() => _PerfilProfissionalScreenState();
}

class _PerfilProfissionalScreenState extends State<PerfilProfissionalScreen> {
  late Future<_DadosPerfil> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _carregar();
  }

  Future<_DadosPerfil> _carregar() async {
    final servico = ProfissionaisService.instancia;

    // As três chamadas não dependem uma da outra -- rodam em paralelo em
    // vez de em sequência, então a tela carrega em ~1 request de tempo,
    // não 3.
    final resultados = await Future.wait([
      servico.buscarPerfilPublico(widget.profissionalId),
      servico.buscarResumoAvaliacoes(widget.profissionalId),
      servico.buscarPortfolio(widget.profissionalId),
    ]);

    return _DadosPerfil(
      perfil: resultados[0] as PerfilProfissional,
      resumo: resultados[1] as ResumoAvaliacoes,
      portfolio: resultados[2] as List<ItemPortfolio>,
    );
  }

  Future<void> _solicitarServico(PerfilProfissional perfil) async {
    final papel = context.read<AuthProvider>().usuario?.papel;
    if (papel != Papel.cliente) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Só uma conta de cliente pode solicitar um serviço.')),
      );
      return;
    }

    final descricaoController = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (contextoDialogo) => AlertDialog(
        title: Text('Solicitar ${perfil.nomeExibicao}'),
        content: TextField(
          controller: descricaoController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Descreva o serviço (opcional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contextoDialogo).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contextoDialogo).pop(true),
            child: const Text('Solicitar'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    try {
      await ServicosService.instancia.solicitar(
        profissionalId: perfil.id,
        descricao: descricaoController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Serviço solicitado para ${perfil.nomeExibicao}!')),
        );
      }
    } on ApiException catch (erro) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro.mensagem)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil do profissional')),
      body: FutureBuilder<_DadosPerfil>(
        future: _futuro,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final mensagem = snapshot.error is ApiException
                ? (snapshot.error as ApiException).mensagem
                : 'Não foi possível carregar este perfil.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(mensagem, textAlign: TextAlign.center),
              ),
            );
          }

          final dados = snapshot.data!;
          return _ConteudoPerfil(
            dados: dados,
            aoSolicitarServico: () => _solicitarServico(dados.perfil),
          );
        },
      ),
    );
  }
}

class _DadosPerfil {
  final PerfilProfissional perfil;
  final ResumoAvaliacoes resumo;
  final List<ItemPortfolio> portfolio;

  const _DadosPerfil({required this.perfil, required this.resumo, required this.portfolio});
}

class _ConteudoPerfil extends StatelessWidget {
  final _DadosPerfil dados;
  final VoidCallback aoSolicitarServico;

  const _ConteudoPerfil({required this.dados, required this.aoSolicitarServico});

  @override
  Widget build(BuildContext context) {
    final perfil = dados.perfil;
    final resumo = dados.resumo;
    final urlFoto = ApiConfig.urlAbsoluta(perfil.urlFotoPerfil);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: CircleAvatar(
            radius: 56,
            backgroundColor: Colors.grey.shade300,
            backgroundImage: urlFoto != null ? NetworkImage(urlFoto) : null,
            child: urlFoto == null
                ? const Icon(Icons.person, size: 56, color: Colors.white)
                : null,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            perfil.nomeExibicao,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
        ),
        if (perfil.atuacao != null) ...[
          const SizedBox(height: 4),
          Center(
            child: Text(
              perfil.atuacao!,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey.shade700),
            ),
          ),
        ],
        const SizedBox(height: 16),

        // Resumo de avaliações + quantidade de serviços prestados.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _EstrelaMedia(valor: resumo.mediaGeral),
                    const SizedBox(width: 8),
                    Text(
                      resumo.mediaGeral != null
                          ? resumo.mediaGeral!.toStringAsFixed(1)
                          : 'Sem avaliações',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${resumo.totalAvaliacoes} serviço(s) já prestado(s) e avaliado(s)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (resumo.totalAvaliacoes > 0) ...[
                  const Divider(height: 24),
                  _BarraCriterio(rotulo: 'Resolução de Problema', media: resumo.mediaTecnico),
                  const SizedBox(height: 10),
                  _BarraCriterio(rotulo: 'Comportamental', media: resumo.mediaComportamental),
                  const SizedBox(height: 10),
                  _BarraCriterio(rotulo: 'Custo benefício', media: resumo.mediaEconomico),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Descrição / "sobre mim".
        if (perfil.descricao != null && perfil.descricao!.trim().isNotEmpty) ...[
          Text('Sobre', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(perfil.descricao!),
          const SizedBox(height: 16),
        ],

        // Endereço de atuação padrão -- só informativo (não afeta o cálculo
        // de distância, que continua vindo de latitude/longitude), serve
        // para o cliente ter uma noção de onde o profissional atua.
        if (perfil.enderecoAtuacao != null && perfil.enderecoAtuacao!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined, size: 18, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(child: Text(perfil.enderecoAtuacao!)),
            ],
          ),
        ],
        const SizedBox(height: 20),

        FilledButton.icon(
          onPressed: aoSolicitarServico,
          icon: const Icon(Icons.send),
          label: const Text('Solicitar serviço'),
        ),
        const SizedBox(height: 28),

        Text('Portfólio', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Histórico de serviços concluídos, com fotos e comentários de clientes.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),

        if (dados.portfolio.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Este profissional ainda não tem histórico de portfólio.'),
          )
        else
          ...dados.portfolio.map((item) => _CartaoPortfolio(item: item)),
      ],
    );
  }
}

/// Uma barra por critério (ex.: "Resolução de Problema"): rótulo à
/// esquerda, uma barra preenchida na proporção da MÉDIA daquele critério
/// (média / 5) e o número da média à direita -- 3 barras no total no
/// resumo do perfil, uma por critério, nada de detalhar nota-a-nota.
class _BarraCriterio extends StatelessWidget {
  final String rotulo;
  final double? media;

  const _BarraCriterio({required this.rotulo, required this.media});

  @override
  Widget build(BuildContext context) {
    final fracao = media != null ? (media! / 5).clamp(0.0, 1.0) : 0.0;

    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(rotulo, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fracao,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(Colors.amber),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 28,
          child: Text(
            media != null ? media!.toStringAsFixed(1) : '--',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Uma única estrela representando a média (não 5 estrelas individuais,
/// para não confundir com o seletor de avaliação -- aqui é só um resumo
/// visual rápido ao lado do número).
class _EstrelaMedia extends StatelessWidget {
  final double? valor;
  final double tamanho;

  const _EstrelaMedia({required this.valor, this.tamanho = 22});

  @override
  Widget build(BuildContext context) {
    if (valor == null) {
      return Icon(Icons.star_border, size: tamanho, color: Colors.grey);
    }
    return Icon(Icons.star, size: tamanho, color: Colors.amber);
  }
}

/// Card do "histórico de portfólio", no padrão de avaliação da Shopee:
/// avatar + nome do cliente + "Útil" na mesma linha do topo, estrelas logo
/// abaixo do nome, comentário como texto corrido, e miniaturas QUADRADAS
/// das fotos (não um banner full-width) -- toque numa miniatura abre a
/// foto em tela cheia, deslizável.
///
/// É `StatefulWidget` (não `StatelessWidget`) porque precisa guardar
/// localmente se A PRÓPRIA PESSOA já curtiu e o total atual, atualizando na
/// hora sem recarregar o portfólio inteiro.
class _CartaoPortfolio extends StatefulWidget {
  final ItemPortfolio item;

  const _CartaoPortfolio({required this.item});

  @override
  State<_CartaoPortfolio> createState() => _CartaoPortfolioState();
}

class _CartaoPortfolioState extends State<_CartaoPortfolio> {
  late bool _curtido;
  late int _totalCurtidas;
  bool _enviandoCurtida = false;

  @override
  void initState() {
    super.initState();
    _curtido = widget.item.curtidoPorMim;
    _totalCurtidas = widget.item.totalCurtidas;
  }

  Future<void> _alternarCurtida() async {
    final logado = context.read<AuthProvider>().usuario != null;
    if (!logado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entre na sua conta para curtir uma avaliação.')),
      );
      return;
    }

    setState(() => _enviandoCurtida = true);
    try {
      final resultado = await ProfissionaisService.instancia.curtirAvaliacao(widget.item.avaliacaoId);
      if (!mounted) return;
      setState(() {
        _curtido = resultado.curtido;
        _totalCurtidas = resultado.totalCurtidas;
      });
    } on ApiException catch (erro) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro.mensagem)));
      }
    } finally {
      if (mounted) setState(() => _enviandoCurtida = false);
    }
  }

  void _abrirFoto(int indiceInicial) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _VisualizadorDeFotos(
          urls: widget.item.urlsFotos,
          indiceInicial: indiceInicial,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final corDestaque = Theme.of(context).colorScheme.primary;
    final inicial = item.nomeCliente.trim().isNotEmpty ? item.nomeCliente.trim()[0].toUpperCase() : '?';
    final urlFotoCliente = ApiConfig.urlAbsoluta(item.urlFotoCliente);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Linha 1: avatar + nome + data à esquerda, botão "Útil" à
          // direita. Mesma posição da Shopee: avatar/usuário e "Útil" na
          // mesma altura, no topo. Avatar usa a FOTO DE PERFIL DO CLIENTE
          // (`clientes.url_foto_perfil`, exposta pela view desde a
          // migração 07) quando o cliente tiver preenchido uma -- senão
          // cai no mesmo fallback de sempre: iniciais do nome.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                backgroundImage: urlFotoCliente != null ? NetworkImage(urlFotoCliente) : null,
                child: urlFotoCliente == null
                    ? Text(
                        inicial,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nomeCliente,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.dataConclusao.day.toString().padLeft(2, '0')}/'
                      '${item.dataConclusao.month.toString().padLeft(2, '0')}/'
                      '${item.dataConclusao.year}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: _enviandoCurtida ? null : _alternarCurtida,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _curtido ? Icons.thumb_up : Icons.thumb_up_outlined,
                        size: 15,
                        color: _curtido ? corDestaque : Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _totalCurtidas > 0 ? 'Útil ($_totalCurtidas)' : 'Útil',
                        style: TextStyle(
                          fontSize: 12,
                          color: _curtido ? corDestaque : Colors.grey.shade600,
                          fontWeight: _curtido ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Linha 2: estrelas -- cinco ícones, não um número. Alinhadas na
          // margem esquerda do card (não indentadas sob o avatar), igual à
          // referência.
          const SizedBox(height: 8),
          _LinhaDeEstrelas(valor: item.mediaEstrelas),

          // Linha 3: comentário, texto corrido.
          if (item.comentario != null && item.comentario!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(item.comentario!, style: Theme.of(context).textTheme.bodyMedium),
          ],

          // Linha 4: miniaturas quadradas das fotos, roláveis na horizontal.
          if (item.urlsFotos.isNotEmpty) ...[
            const SizedBox(height: 10),
            _MiniaturasDeFotos(urls: item.urlsFotos, aoTocar: _abrirFoto),
          ],

          const SizedBox(height: 14),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

/// Cinco ícones de estrela (não um número) representando a média,
/// arredondada para o inteiro mais próximo -- é assim que a Shopee mostra
/// a nota de cada avaliação individual.
class _LinhaDeEstrelas extends StatelessWidget {
  final double valor;
  final double tamanho;

  const _LinhaDeEstrelas({required this.valor, this.tamanho = 15});

  @override
  Widget build(BuildContext context) {
    final preenchidas = valor.round().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (indice) {
        return Icon(
          indice < preenchidas ? Icons.star : Icons.star_border,
          size: tamanho,
          color: Colors.amber,
        );
      }),
    );
  }
}

/// Fileira horizontal de miniaturas QUADRADAS (96x96) das fotos de uma
/// avaliação -- o tamanho pequeno é de propósito, seguindo o padrão da
/// Shopee: a foto grande só aparece quando a pessoa toca numa miniatura
/// (ver `_VisualizadorDeFotos`).
class _MiniaturasDeFotos extends StatelessWidget {
  final List<String> urls;
  final ValueChanged<int> aoTocar;

  const _MiniaturasDeFotos({required this.urls, required this.aoTocar});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, indice) {
          final urlFoto = ApiConfig.urlAbsoluta(urls[indice]);
          return InkWell(
            onTap: () => aoTocar(indice),
            borderRadius: BorderRadius.circular(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: urlFoto != null
                  ? Image.network(
                      urlFoto,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 96,
                        height: 96,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    )
                  : Container(width: 96, height: 96, color: Colors.grey.shade200),
            ),
          );
        },
      ),
    );
  }
}

/// Tela cheia, fundo preto, para ver uma foto do portfólio em tamanho
/// grande -- abre já na foto que a pessoa tocou (`indiceInicial`) e deixa
/// deslizar (`PageView`) para as outras fotos da mesma avaliação.
/// `InteractiveViewer` permite dar zoom com pinça, como em qualquer
/// visualizador de foto de app de compras.
class _VisualizadorDeFotos extends StatefulWidget {
  final List<String> urls;
  final int indiceInicial;

  const _VisualizadorDeFotos({required this.urls, required this.indiceInicial});

  @override
  State<_VisualizadorDeFotos> createState() => _VisualizadorDeFotosState();
}

class _VisualizadorDeFotosState extends State<_VisualizadorDeFotos> {
  late final PageController _controlador;
  late int _pagina;

  @override
  void initState() {
    super.initState();
    _pagina = widget.indiceInicial;
    _controlador = PageController(initialPage: widget.indiceInicial);
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_pagina + 1} / ${widget.urls.length}'),
      ),
      body: PageView.builder(
        controller: _controlador,
        itemCount: widget.urls.length,
        onPageChanged: (indice) => setState(() => _pagina = indice),
        itemBuilder: (context, indice) {
          final urlFoto = ApiConfig.urlAbsoluta(widget.urls[indice]);
          if (urlFoto == null) return const SizedBox.shrink();
          return InteractiveViewer(
            child: Center(child: Image.network(urlFoto, fit: BoxFit.contain)),
          );
        },
      ),
    );
  }
}
