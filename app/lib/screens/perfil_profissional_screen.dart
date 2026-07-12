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
            border: OutlineInputBorder(),
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
                  _LinhaCriterio(rotulo: 'Técnico', valor: resumo.mediaTecnico),
                  _LinhaCriterio(rotulo: 'Comportamental', valor: resumo.mediaComportamental),
                  _LinhaCriterio(rotulo: 'Econômico', valor: resumo.mediaEconomico),
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

        Row(
          children: [
            const Icon(Icons.phone, size: 18, color: Colors.grey),
            const SizedBox(width: 6),
            Text(perfil.contato),
          ],
        ),
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

class _LinhaCriterio extends StatelessWidget {
  final String rotulo;
  final double? valor;

  const _LinhaCriterio({required this.rotulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(rotulo),
          Row(
            children: [
              _EstrelaMedia(valor: valor, tamanho: 16),
              const SizedBox(width: 6),
              Text(valor != null ? valor!.toStringAsFixed(1) : '--'),
            ],
          ),
        ],
      ),
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

/// Card do "histórico de portfólio" -- estilo Shopee: galeria de fotos
/// deslizável (quando a avaliação tem mais de uma) + botão "Útil" para
/// curtir. É `StatefulWidget` (não `StatelessWidget` como antes) porque
/// precisa guardar localmente se A PRÓPRIA PESSOA já curtiu e o total
/// atual, atualizando na hora sem recarregar o portfólio inteiro.
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

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final corDestaque = Theme.of(context).colorScheme.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.urlsFotos.isNotEmpty) _GaleriaDeFotos(urls: item.urlsFotos),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.nomeCliente,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 16, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(item.mediaEstrelas.toStringAsFixed(1)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.dataConclusao.day.toString().padLeft(2, '0')}/'
                  '${item.dataConclusao.month.toString().padLeft(2, '0')}/'
                  '${item.dataConclusao.year}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (item.comentario != null && item.comentario!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(item.comentario!),
                ],
                const SizedBox(height: 8),
                InkWell(
                  onTap: _enviandoCurtida ? null : _alternarCurtida,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _curtido ? Icons.thumb_up : Icons.thumb_up_outlined,
                          size: 18,
                          color: _curtido ? corDestaque : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _totalCurtidas > 0 ? 'Útil ($_totalCurtidas)' : 'Útil',
                          style: TextStyle(
                            color: _curtido ? corDestaque : Colors.grey.shade600,
                            fontWeight: _curtido ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Galeria de fotos de uma avaliação -- desliza horizontalmente (`PageView`)
/// com bolinhas indicando a posição atual, igual à galeria de fotos de uma
/// avaliação no Shopee/Mercado Livre. Com uma foto só, os indicadores nem
/// aparecem (não faz sentido mostrar bolinha pra uma foto só).
class _GaleriaDeFotos extends StatefulWidget {
  final List<String> urls;

  const _GaleriaDeFotos({required this.urls});

  @override
  State<_GaleriaDeFotos> createState() => _GaleriaDeFotosState();
}

class _GaleriaDeFotosState extends State<_GaleriaDeFotos> {
  final _controlador = PageController();
  int _pagina = 0;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        SizedBox(
          height: 180,
          width: double.infinity,
          child: PageView.builder(
            controller: _controlador,
            itemCount: widget.urls.length,
            onPageChanged: (indice) => setState(() => _pagina = indice),
            itemBuilder: (context, indice) {
              final urlFoto = ApiConfig.urlAbsoluta(widget.urls[indice]);
              if (urlFoto == null) return const SizedBox.shrink();
              return Image.network(
                urlFoto,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
              );
            },
          ),
        ),
        if (widget.urls.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(widget.urls.length, (indice) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: indice == _pagina ? Colors.white : Colors.white54,
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}
