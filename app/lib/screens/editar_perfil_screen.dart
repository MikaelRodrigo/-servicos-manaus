import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/config/api_config.dart';
import '../data/models/categoria.dart';
import '../data/models/endereco_cep.dart';
import '../data/models/perfil_profissional.dart';
import '../data/services/api_client.dart';
import '../data/services/categorias_service.dart';
import '../data/services/cep_service.dart';
import '../data/services/profissionais_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/selecao_foto_perfil.dart';
import '../widgets/selecao_tags_subcategorias.dart';

/// Tela em que o PRÓPRIO profissional edita seu perfil: foto, descrição
/// ("sobre mim"), CEP, contato, endereço e o portfólio visual (migração 16)
/// -- tudo o que é refletido no perfil público que o cliente vê ao tocar no
/// pino do profissional no mapa. É o que alimenta os campos que antes
/// ficavam sempre `null` -- sem esta tela, ninguém teria como preencher
/// `descricao`/`url_foto_perfil` depois do cadastro, nem aparecer na busca
/// por proximidade do mapa (que depende de latitude/longitude).
class EditarPerfilScreen extends StatefulWidget {
  const EditarPerfilScreen({super.key});

  @override
  State<EditarPerfilScreen> createState() => _EditarPerfilScreenState();
}

class _EditarPerfilScreenState extends State<EditarPerfilScreen> {
  final _descricaoController = TextEditingController();
  final _cepController = TextEditingController();
  final _contatoController = TextEditingController();
  final _enderecoController = TextEditingController();
  late Future<MeuPerfilProfissional> _futuroPerfilAtual;

  // Guardado à parte (não só dentro do Future) para servir de referência de
  // "o que já está gravado" nos comparativos de `_salvar` (mesmo padrão de
  // `PerfilClienteScreen._perfilCarregado`) -- evita mandar um PATCH de
  // contato/endereço quando a pessoa não alterou nada neles.
  MeuPerfilProfissional? _perfilCarregado;

  XFile? _fotoEscolhida;
  Uint8List? _bytesFotoEscolhida;
  String? _urlFotoAtual;

  // Localização/endereço JÁ GRAVADOS -- mostrados como texto informativo
  // ("Localização atual: ..."), nunca pré-preenchidos no campo de CEP. O
  // campo de CEP é só de ENTRADA (mesmo espírito do seletor de foto: ele
  // não mostra a foto atual dentro do próprio botão de escolher foto nova,
  // mostra ao lado). Evita reenviar sempre o mesmo CEP sem querer.
  String? _enderecoAtualExibicao;
  bool _salvando = false;

  // Autofill em tempo real do CEP: dispara ~500ms depois que o usuário
  // termina de digitar os 8 dígitos (debounce -- evita bater na API a cada
  // tecla). `_enderecoPreview` é o endereço RECÉM-CONSULTADO (ainda não
  // salvo, só uma prévia); é um conceito diferente de `_enderecoAtualExibicao`
  // acima, que é o endereço já GRAVADO no perfil.
  Timer? _debounceCep;
  EnderecoPorCep? _enderecoPreview;
  bool _consultandoCep = false;
  String? _erroCep;

  // Especialidades (tags de subcategoria, migração 11 no backend) -- lista
  // fixa (`_categorias`) alimenta a busca do `SelecaoTagsSubcategorias`;
  // `_tags` são as especialidades que o profissional JÁ TEM agora.
  // Diferente do CEP/descrição acima, tags não fazem parte do "Salvar
  // perfil" em lote -- cada adição/remoção chama a API na hora (ver
  // `_adicionarTag`/`_removerTag`), então o estado aqui já reflete sempre o
  // que está gravado no banco.
  List<Categoria> _categorias = [];
  bool _carregandoCategorias = true;
  List<TagSubcategoria> _tags = [];

  // Painel de desempenho ("dashboard") -- resumo das próprias avaliações
  // (nota média + indicadores por critério), buscado à parte do perfil
  // (GET /profissionais/me/avaliacoes/resumo, autenticado). Separado de
  // `_futuroPerfilAtual` de propósito: se a busca de avaliações falhar, o
  // resto da tela (editar descrição/CEP/tags) continua funcionando
  // normalmente -- é um painel informativo, não um bloqueio de fluxo.
  ResumoAvaliacoes? _resumoDesempenho;
  bool _carregandoResumo = true;
  bool _erroResumo = false;

  // Portfólio visual (migração 16) -- galeria curada pelo PRÓPRIO
  // profissional, refletida no perfil público. Cada adição/remoção chama a
  // API na hora (mesmo espírito das tags de especialidade acima), não fica
  // dependendo do botão "Salvar perfil".
  List<FotoPortfolio> _fotosPortfolio = [];
  bool _carregandoFotos = true;
  bool _enviandoFotos = false;

  @override
  void initState() {
    super.initState();
    _futuroPerfilAtual = ProfissionaisService.instancia.buscarMeuPerfil();
    _futuroPerfilAtual.then((perfil) {
      if (!mounted) return;
      setState(() {
        _perfilCarregado = perfil;
        _descricaoController.text = perfil.descricao ?? '';
        _contatoController.text = perfil.contato ?? '';
        _enderecoController.text = perfil.endereco ?? '';
        _urlFotoAtual = perfil.urlFotoPerfil;
        _enderecoAtualExibicao = perfil.enderecoAtuacao;
        _tags = perfil.subcategorias;
      });
    });
    _carregarCategorias();
    _carregarResumoDesempenho();
    _carregarFotosPortfolio();
  }

  /// Busca a galeria já salva do profissional logado. Mesma rota pública
  /// usada no perfil público (`GET /profissionais/:id/portfolio-fotos`) --
  /// aqui é só chamada com o próprio id, ver comentário da rota no backend.
  Future<void> _carregarFotosPortfolio() async {
    try {
      final meuId = context.read<AuthProvider>().usuario!.id;
      final fotos = await ProfissionaisService.instancia.listarPortfolioFotos(meuId);
      if (!mounted) return;
      setState(() {
        _fotosPortfolio = fotos;
        _carregandoFotos = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _carregandoFotos = false);
    }
  }

  /// Escolhe uma ou mais imagens da galeria (sem recorte forçado -- ao
  /// contrário da foto de perfil, fotos de portfólio não precisam ser
  /// quadradas) e envia num único lote (`adicionarFotosPortfolio`). O
  /// backend recusa (400 -- vira `ApiException`) se estourar o teto de 6 por
  /// lote ou 24 no total.
  Future<void> _adicionarFotosPortfolio() async {
    final selecionadas = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (selecionadas.isEmpty || !mounted) return;

    setState(() => _enviandoFotos = true);
    try {
      final galeria = await ProfissionaisService.instancia.adicionarFotosPortfolio(selecionadas);
      if (!mounted) return;
      setState(() => _fotosPortfolio = galeria);
    } on ApiException catch (erro) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro.mensagem)));
      }
    } finally {
      if (mounted) setState(() => _enviandoFotos = false);
    }
  }

  Future<void> _removerFotoPortfolio(FotoPortfolio foto) async {
    setState(() => _fotosPortfolio = _fotosPortfolio.where((f) => f.idFoto != foto.idFoto).toList());
    try {
      final galeria = await ProfissionaisService.instancia.removerFotoPortfolio(foto.idFoto);
      if (!mounted) return;
      setState(() => _fotosPortfolio = galeria);
    } on ApiException catch (erro) {
      // Desfaz a remoção otimista se o backend recusar.
      if (!mounted) return;
      setState(() => _fotosPortfolio = [..._fotosPortfolio, foto]);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro.mensagem)));
    }
  }

  /// Busca o resumo de avaliações do profissional logado, para o painel de
  /// desempenho no topo da tela. Falha silenciosa de propósito (sem
  /// `SnackBar`): é um painel "a mais", não pode travar nem incomodar quem
  /// só veio editar a descrição -- `_erroResumo` deixa a UI mostrar um
  /// aviso discreto no lugar do painel, sem impedir o resto da tela.
  Future<void> _carregarResumoDesempenho() async {
    try {
      final resumo = await ProfissionaisService.instancia.buscarMinhasAvaliacoesResumo();
      if (!mounted) return;
      setState(() {
        _resumoDesempenho = resumo;
        _carregandoResumo = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _erroResumo = true;
        _carregandoResumo = false;
      });
    }
  }

  Future<void> _carregarCategorias() async {
    try {
      final categorias = await CategoriasService.instancia.listarCategorias();
      if (!mounted) return;
      setState(() {
        _categorias = categorias;
        _carregandoCategorias = false;
      });
    } on ApiException catch (erro) {
      if (!mounted) return;
      setState(() => _carregandoCategorias = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível carregar as categorias: ${erro.mensagem}')),
      );
    }
  }

  /// Chamado pelo `SelecaoTagsSubcategorias` quando o profissional confirma
  /// uma especialidade nova (Enter ou toque no dropdown). Deixa
  /// `ApiException` escapar de propósito -- é o próprio widget quem mostra
  /// o `SnackBar` de erro (ver `_confirmarAdicao` lá).
  Future<void> _adicionarTag(Subcategoria subcategoria) async {
    final tags = await ProfissionaisService.instancia.adicionarTag(subcategoria.id);
    if (!mounted) return;
    setState(() => _tags = tags);
  }

  /// Idem, para remoção -- inclusive o erro de "não pode remover a última",
  /// que o backend recusa com 400 (vira `ApiException`, mostrado pelo
  /// widget).
  Future<void> _removerTag(TagSubcategoria tag) async {
    final tags = await ProfissionaisService.instancia.removerTag(tag.id);
    if (!mounted) return;
    setState(() => _tags = tags);
  }

  @override
  void dispose() {
    _debounceCep?.cancel();
    _descricaoController.dispose();
    _cepController.dispose();
    _contatoController.dispose();
    _enderecoController.dispose();
    super.dispose();
  }

  /// Chamado a cada tecla no campo de CEP. Só dispara a consulta de verdade
  /// quando: (1) já tem os 8 dígitos completos, e (2) passou meio segundo
  /// sem nova tecla (debounce -- evita uma chamada de API por dígito
  /// enquanto a pessoa ainda está digitando). Apagar/editar o CEP depois de
  /// já ter um preview limpa o preview na hora, sem esperar debounce nenhum.
  void _aoDigitarCep(String valor) {
    _debounceCep?.cancel();

    if (valor.length != 8) {
      setState(() {
        _enderecoPreview = null;
        _erroCep = null;
        _consultandoCep = false;
      });
      return;
    }

    setState(() {
      _consultandoCep = true;
      _erroCep = null;
    });

    _debounceCep = Timer(const Duration(milliseconds: 500), () async {
      try {
        final endereco = await CepService.instancia.buscarEndereco(valor);
        if (!mounted || _cepController.text.trim() != valor) return;
        setState(() {
          _enderecoPreview = endereco;
          _consultandoCep = false;
        });
      } on ApiException catch (erro) {
        if (!mounted || _cepController.text.trim() != valor) return;
        setState(() {
          _enderecoPreview = null;
          _erroCep = erro.mensagem;
          _consultandoCep = false;
        });
      }
    });
  }

  // Escolher origem + selecionar + RECORTAR (1:1) moram todos em
  // `escolherEEditarFotoDePerfil` (widgets/selecao_foto_perfil.dart) --
  // compartilhado com `perfil_cliente_screen.dart`, para as duas telas
  // nunca divergirem no fluxo de troca de foto.
  Future<void> _trocarFoto() async {
    final resultado = await escolherEEditarFotoDePerfil(context);
    if (resultado == null || !mounted) return;
    setState(() {
      _fotoEscolhida = resultado.arquivo;
      _bytesFotoEscolhida = resultado.bytes;
    });
  }

  Future<void> _salvar() async {
    final descricao = _descricaoController.text.trim();
    final cep = _cepController.text.trim();
    final contato = _contatoController.text.trim();
    final endereco = _enderecoController.text.trim();

    // Só manda contato/endereço se de fato mudaram -- mesmo padrão de
    // `PerfilClienteScreen._salvar` -- evita um PATCH desnecessário quando a
    // pessoa só veio mexer na descrição/CEP/foto.
    final perfilAtual = _perfilCarregado;
    final contatoMudou = contato.isNotEmpty && contato != (perfilAtual?.contato ?? '');
    final enderecoMudou = endereco != (perfilAtual?.endereco ?? '');

    if (descricao.isEmpty && cep.isEmpty && !contatoMudou && !enderecoMudou && _fotoEscolhida == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Altere algum campo ou escolha uma foto antes de salvar.'),
        ),
      );
      return;
    }

    // Confere 8 dígitos ANTES de bater no backend -- feedback imediato em
    // vez de esperar a resposta de um CEP obviamente incompleto/errado.
    if (cep.isNotEmpty && cep.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O CEP precisa ter 8 dígitos.')),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final perfilAtualizado = await ProfissionaisService.instancia.atualizarMeuPerfil(
        descricao: descricao.isNotEmpty ? descricao : null,
        cep: cep.isNotEmpty ? cep : null,
        contato: contatoMudou ? contato : null,
        endereco: enderecoMudou ? endereco : null,
        foto: _fotoEscolhida,
      );
      if (!mounted) return;
      setState(() {
        _perfilCarregado = perfilAtualizado;
        _enderecoAtualExibicao = perfilAtualizado.enderecoAtuacao;
        _cepController.clear();
        _enderecoPreview = null;
        _erroCep = null;
      });
      // Reflete a foto nova no avatar do cabeçalho do mapa na hora, sem
      // precisar deslogar/logar de novo -- ver comentário em
      // `AuthProvider.atualizarFotoPerfil`.
      if (_fotoEscolhida != null) {
        await context.read<AuthProvider>().atualizarFotoPerfil(perfilAtualizado.urlFotoPerfil);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cep.isNotEmpty && perfilAtualizado.enderecoAtuacao != null
                ? 'Perfil atualizado! Localização: ${perfilAtualizado.enderecoAtuacao}'
                : 'Perfil atualizado!',
          ),
        ),
      );
      // `canPop`: esta tela agora vive em DOIS lugares -- empurrada (push)
      // a partir de outros pontos do app, ou como uma aba fixa de
      // `HomeShell` (via `IndexedStack`, "Meus dados" do profissional). Só
      // faz sentido voltar quando ela foi de fato empilhada; como aba fixa
      // não há nada para "fechar" -- o SnackBar acima já é a confirmação.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(perfilAtualizado);
      }
    } on ApiException catch (erro) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro.mensagem)));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar meu perfil')),
      body: FutureBuilder<MeuPerfilProfissional>(
        future: _futuroPerfilAtual,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final urlFotoAtual = ApiConfig.urlAbsoluta(_urlFotoAtual);

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: AvatarFotoPerfil(
                  bytesFotoEscolhida: _bytesFotoEscolhida,
                  urlFotoAtual: urlFotoAtual,
                  onTocar: _trocarFoto,
                ),
              ),
              const SizedBox(height: 20),

              // Painel de desempenho ("dashboard") -- fechamento estatístico
              // das avaliações já recebidas, todo calculado NO SERVIDOR
              // (GET /profissionais/me/avaliacoes/resumo): o app só exibe o
              // resultado pronto (nota média + 3 indicadores), nunca soma
              // ou processa avaliação nenhuma no dispositivo.
              _PainelDesempenho(
                resumo: _resumoDesempenho,
                carregando: _carregandoResumo,
                erro: _erroResumo,
              ),
              const SizedBox(height: 20),

              TextField(
                controller: _descricaoController,
                maxLines: 5,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Sobre mim',
                  hintText: 'Conte um pouco sobre sua experiência e seus serviços...',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),

              // CEP define onde o profissional aparece na busca por
              // proximidade do mapa -- ver PATCH /profissionais/me no
              // backend, que geocodifica o CEP em latitude/longitude.
              TextField(
                controller: _cepController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 8,
                onChanged: _aoDigitarCep,
                decoration: InputDecoration(
                  labelText: 'CEP',
                  hintText: 'Ex.: 69010030',
                  helperText: 'Define onde você aparece no mapa para os clientes.',
                  suffixIcon: _consultandoCep
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
              // Preview do endereço encontrado para o CEP recém-digitado --
              // aparece ANTES de salvar, como confirmação visual imediata
              // (autofill em tempo real). Erro (CEP inexistente, por
              // exemplo) some sozinho assim que a pessoa edita o campo de
              // novo (ver `_aoDigitarCep`).
              if (_erroCep != null) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 16, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _erroCep!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ),
                  ],
                ),
              ] else if (_enderecoPreview != null && _enderecoPreview!.textoFormatado.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _enderecoPreview!.textoFormatado,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_enderecoAtualExibicao != null && _enderecoAtualExibicao!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Localização atual: $_enderecoAtualExibicao',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),

              // Contato/endereço -- editáveis pela primeira vez aqui
              // (migração 16). `contato` antes só era definido no cadastro,
              // sem nenhum caminho de atualização; `endereco` é texto livre,
              // complementar ao CEP acima (que só serve para geolocalizar a
              // busca no mapa) -- mesmo espírito de
              // `PerfilClienteScreen`/`clientes.endereco`.
              TextField(
                controller: _contatoController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Contato (telefone/WhatsApp)',
                  hintText: '92988887777',
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _enderecoController,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Endereço',
                  hintText: 'Rua, número, bairro, ponto de referência...',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),

              // Especialidades -- cada box é uma tag adicionada/removida NA
              // HORA (não faz parte do "Salvar perfil" em lote abaixo, ver
              // `_adicionarTag`/`_removerTag`). Sem "categoria única" mais
              // nesta tela: o profissional pode ter quantas especialidades
              // quiser, e aparece na busca de QUALQUER uma delas.
              Text('Especialidades', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _carregandoCategorias
                  ? const Center(child: CircularProgressIndicator())
                  : SelecaoTagsSubcategorias(
                      categorias: _categorias,
                      tagsAtuais: _tags,
                      aoAdicionar: _adicionarTag,
                      aoRemover: _removerTag,
                    ),
              const SizedBox(height: 20),

              // Portfólio visual (migração 16) -- galeria de fotos que o
              // PRÓPRIO profissional escolhe para mostrar seu trabalho,
              // refletida no perfil público (`perfil_profissional_screen.dart`,
              // seção "Fotos do trabalho"). Diferente do histórico de
              // avaliações (que também aparece lá, alimentado pelos
              // CLIENTES) -- este aqui é 100% curado pelo dono do perfil.
              // Cada adição/remoção salva NA HORA, sem passar pelo botão
              // "Salvar perfil" abaixo.
              Text('Portfólio visual', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Fotos do seu trabalho, visíveis para quem visitar seu perfil.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              _SecaoPortfolio(
                fotos: _fotosPortfolio,
                carregando: _carregandoFotos,
                enviando: _enviandoFotos,
                aoAdicionar: _adicionarFotosPortfolio,
                aoRemover: _removerFotoPortfolio,
              ),
              const SizedBox(height: 12),

              FilledButton.icon(
                onPressed: _salvando ? null : _salvar,
                icon: _salvando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(_salvando ? 'Salvando...' : 'Salvar perfil'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Painel de desempenho ("dashboard") -- fechamento estatístico das
/// avaliações do profissional: nota média + indicadores de qualidade
/// (resolução de problema, comportamento, custo-benefício). Todo o CÁLCULO
/// vem pronto do servidor (`GET /profissionais/me/avaliacoes/resumo`); este
/// widget só decide COMO desenhar, nunca soma nem processa avaliação
/// nenhuma -- é puramente de exibição.
///
/// Três estados possíveis, sempre dentro do mesmo `Card` (a transição entre
/// eles não muda a posição do painel na tela):
///   1. `carregando` -- spinner pequeno + texto.
///   2. `erro` -- aviso discreto (a tela continua editável mesmo assim).
///   3. dados prontos -- se `resumo.totalAvaliacoes == 0`, mensagem neutra
///      de "ainda sem avaliações"; senão, nota média + os 3 indicadores.
class _PainelDesempenho extends StatelessWidget {
  final ResumoAvaliacoes? resumo;
  final bool carregando;
  final bool erro;

  const _PainelDesempenho({
    required this.resumo,
    required this.carregando,
    required this.erro,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _conteudo(context),
      ),
    );
  }

  Widget _conteudo(BuildContext context) {
    if (carregando) {
      return Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text('Carregando seu desempenho...', style: Theme.of(context).textTheme.bodyMedium),
        ],
      );
    }

    if (erro) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Não foi possível carregar seu desempenho agora. Isso não afeta o resto do seu perfil.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ),
        ],
      );
    }

    final dados = resumo;
    if (dados == null || dados.totalAvaliacoes == 0) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.insights_outlined, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Você ainda não tem avaliações. Assim que concluir seu primeiro serviço avaliado, seu desempenho aparece aqui.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.dashboard_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('Seu desempenho', style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Icon(Icons.star, color: Colors.amber, size: 28),
            const SizedBox(width: 8),
            Text(
              dados.mediaGeral != null ? dados.mediaGeral!.toStringAsFixed(1) : '--',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'nota média · ${dados.totalAvaliacoes} avaliação(ões)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // `Wrap` (não `Row`) de propósito: numa tela estreita (celular) os
        // três indicadores quebram em mais de uma linha; numa janela larga
        // (Flutter Web/desktop) eles ficam lado a lado -- o mesmo painel se
        // adapta aos dois sem precisar de layout condicional por plataforma.
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _IndicadorDesempenho(
              icone: Icons.build_outlined,
              rotulo: 'Resolução de Problema',
              valor: dados.mediaTecnico,
            ),
            _IndicadorDesempenho(
              icone: Icons.emoji_people_outlined,
              rotulo: 'Comportamental',
              valor: dados.mediaComportamental,
            ),
            _IndicadorDesempenho(
              icone: Icons.payments_outlined,
              rotulo: 'Custo benefício',
              valor: dados.mediaEconomico,
            ),
          ],
        ),
      ],
    );
  }
}

/// Grade do portfólio visual (migração 16) -- fotos já salvas + um tile de
/// "adicionar" no fim. Cada foto tem um botão "x" no canto para remoção
/// imediata; o tile de adicionar mostra um spinner enquanto um lote está
/// sendo enviado (evita disparos duplicados por toques repetidos).
///
/// Widget "burro" de propósito, mesmo espírito de `AvatarFotoPerfil`: não
/// sabe nada de `ImagePicker`/`ProfissionaisService`, só recebe o estado
/// pronto e avisa a tela (`aoAdicionar`/`aoRemover`) quando alguém toca.
class _SecaoPortfolio extends StatelessWidget {
  final List<FotoPortfolio> fotos;
  final bool carregando;
  final bool enviando;
  final VoidCallback aoAdicionar;
  final ValueChanged<FotoPortfolio> aoRemover;

  const _SecaoPortfolio({
    required this.fotos,
    required this.carregando,
    required this.enviando,
    required this.aoAdicionar,
    required this.aoRemover,
  });

  static const _tamanhoTile = 88.0;

  @override
  Widget build(BuildContext context) {
    if (carregando) {
      return const SizedBox(
        height: _tamanhoTile,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final foto in fotos) _tileFoto(context, foto),
        _tileAdicionar(context),
      ],
    );
  }

  Widget _tileFoto(BuildContext context, FotoPortfolio foto) {
    final url = ApiConfig.urlAbsoluta(foto.urlFoto);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: url != null
              ? Image.network(
                  url,
                  width: _tamanhoTile,
                  height: _tamanhoTile,
                  fit: BoxFit.cover,
                )
              : Container(
                  width: _tamanhoTile,
                  height: _tamanhoTile,
                  color: Colors.grey.shade300,
                ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () => aoRemover(foto),
            child: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.black87,
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tileAdicionar(BuildContext context) {
    return InkWell(
      onTap: enviando ? null : aoAdicionar,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: _tamanhoTile,
        height: _tamanhoTile,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(10),
        ),
        child: enviando
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.add_photo_alternate_outlined, color: Colors.grey.shade600, size: 28),
      ),
    );
  }
}

/// Um indicador de qualidade dentro do painel de desempenho -- ícone +
/// rótulo + valor, dentro de um "chip" com borda sutil. `valor == null`
/// (critério sem avaliação suficiente, caso raríssimo já que os três
/// critérios são preenchidos juntos em toda avaliação) mostra "--" em vez
/// de quebrar a tela.
class _IndicadorDesempenho extends StatelessWidget {
  final IconData icone;
  final String rotulo;
  final double? valor;

  const _IndicadorDesempenho({
    required this.icone,
    required this.rotulo,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                valor != null ? valor!.toStringAsFixed(1) : '--',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                rotulo,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
