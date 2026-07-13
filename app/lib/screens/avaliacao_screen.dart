import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../data/models/servico.dart';
import '../data/models/usuario.dart';
import '../data/services/api_client.dart';
import '../data/services/avaliacoes_service.dart';
import '../providers/auth_provider.dart';

/// Formulário de avaliação bilateral -- a MESMA tela serve para os dois
/// lados, decidindo internamente qual formulário mostrar (e qual endpoint
/// chamar) de acordo com o papel de quem está logado. Isso evita duas
/// telas quase idênticas com só os rótulos dos campos diferentes.
class AvaliacaoScreen extends StatefulWidget {
  final Servico servico;
  const AvaliacaoScreen({super.key, required this.servico});

  @override
  State<AvaliacaoScreen> createState() => _AvaliacaoScreenState();
}

/// Quantas fotos o cliente pode anexar numa avaliação -- espelha
/// `MAX_FOTOS_POR_AVALIACAO` em upload.ts no backend. Se mudar lá, mude aqui.
const _maxFotosPorAvaliacao = 5;

class _AvaliacaoScreenState extends State<AvaliacaoScreen> {
  // Notas 1 a 5. Começam em 5 -- é mais rápido para quem só quer elogiar
  // (o caso mais comum) e ainda assim totalmente ajustável.
  int _nota1 = 5;
  int _nota2 = 5;
  int _nota3 = 5;
  final _comentarioController = TextEditingController();
  final List<XFile> _fotos = [];
  bool _enviando = false;

  @override
  void dispose() {
    _comentarioController.dispose();
    super.dispose();
  }

  Future<void> _escolherFotos() async {
    if (_fotos.length >= _maxFotosPorAvaliacao) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Máximo de $_maxFotosPorAvaliacao fotos por avaliação.')),
      );
      return;
    }

    final origem = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (contexto) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.of(contexto).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                // No Android/iOS o image_picker sabe selecionar várias fotos
                // de uma vez na galeria; no navegador (web), só uma por vez
                // -- por isso o texto muda conforme a plataforma.
                kIsWeb ? 'Escolher da galeria' : 'Escolher da galeria (várias)',
              ),
              onTap: () => Navigator.of(contexto).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (origem == null) return;

    final espacoRestante = _maxFotosPorAvaliacao - _fotos.length;

    if (origem == ImageSource.gallery && !kIsWeb) {
      final escolhidas = await ImagePicker().pickMultiImage(imageQuality: 80);
      if (escolhidas.isEmpty) return;
      setState(() => _fotos.addAll(escolhidas.take(espacoRestante)));
      if (escolhidas.length > espacoRestante && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Só cabiam mais $espacoRestante foto(s) -- o resto foi ignorado.')),
        );
      }
      return;
    }

    final arquivo = await ImagePicker().pickImage(source: origem, imageQuality: 80);
    if (arquivo != null) {
      setState(() => _fotos.add(arquivo));
    }
  }

  void _removerFoto(int indice) {
    setState(() => _fotos.removeAt(indice));
  }

  Future<void> _enviar(Papel papel) async {
    setState(() => _enviando = true);

    try {
      if (papel == Papel.cliente) {
        await AvaliacoesService.instancia.avaliarProfissional(
          idServico: widget.servico.id,
          estrelasTecnico: _nota1,
          estrelasComportamental: _nota2,
          estrelasEconomico: _nota3,
          comentario: _comentarioController.text.trim(),
          fotos: _fotos,
        );
      } else {
        await AvaliacoesService.instancia.avaliarCliente(
          idServico: widget.servico.id,
          estrelasClareza: _nota1,
          estrelasComportamental: _nota2,
          estrelasPagamento: _nota3,
          comentario: _comentarioController.text.trim(),
        );
      }

      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (erro) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro.mensagem)));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final papel = context.read<AuthProvider>().usuario!.papel;
    final ehCliente = papel == Papel.cliente;

    final nomeDoAvaliado = ehCliente ? widget.servico.profissionalNome : widget.servico.clienteNome;

    // Os RÓTULOS mudam conforme quem avalia -- mas a MECÂNICA (3 notas +
    // comentário) é a mesma. Ver avaliacoes.repository.ts no backend:
    // avaliacoes_profissional tem estrelas_tecnico/comportamental/economico;
    // avaliacoes_cliente tem estrelas_clareza/comportamental/pagamento.
    //
    // Nomes dos critérios de quem avalia o PROFISSIONAL alinhados com o que
    // aparece no perfil público dele (ver `_BlocoDistribuicaoCriterio` em
    // perfil_profissional_screen.dart) -- mesmo rótulo em toda a jornada,
    // do formulário de avaliação até o gráfico de distribuição.
    final rotulo1 = ehCliente ? 'Resolução de Problema' : 'Clareza do pedido';
    final rotulo2 = 'Comportamental';
    final rotulo3 = ehCliente ? 'Custo benefício' : 'Pagamento em dia';

    return Scaffold(
      appBar: AppBar(title: Text('Avaliar $nomeDoAvaliado')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SeletorEstrelas(
              rotulo: rotulo1,
              valor: _nota1,
              onChanged: (v) => setState(() => _nota1 = v),
            ),
            const SizedBox(height: 16),
            _SeletorEstrelas(
              rotulo: rotulo2,
              valor: _nota2,
              onChanged: (v) => setState(() => _nota2 = v),
            ),
            const SizedBox(height: 16),
            _SeletorEstrelas(
              rotulo: rotulo3,
              valor: _nota3,
              onChanged: (v) => setState(() => _nota3 = v),
            ),
            const SizedBox(height: 24),

            TextField(
              controller: _comentarioController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Comentário (opcional)',
              ),
            ),
            const SizedBox(height: 16),

            // Upload de fotos: só faz sentido para o cliente avaliando o
            // profissional (avaliacoes_cliente não tem essa coluna, ver
            // Etapa de Avaliações no backend). Até 5 fotos.
            if (ehCliente) ...[
              Text(
                'Fotos do serviço (opcional, até $_maxFotosPorAvaliacao)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _SeletorDeFotos(
                fotos: _fotos,
                aoAdicionar: _escolherFotos,
                aoRemover: _removerFoto,
              ),
              const SizedBox(height: 24),
            ],

            FilledButton(
              onPressed: _enviando ? null : () => _enviar(papel),
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
              child: _enviando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Enviar avaliação'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fileira horizontal de miniaturas das fotos já escolhidas + um botão "+"
/// no final para adicionar mais (até o limite). Cada miniatura tem um "x"
/// no canto para remover -- comum em formulários de upload múltiplo.
class _SeletorDeFotos extends StatelessWidget {
  final List<XFile> fotos;
  final VoidCallback aoAdicionar;
  final ValueChanged<int> aoRemover;

  const _SeletorDeFotos({
    required this.fotos,
    required this.aoAdicionar,
    required this.aoRemover,
  });

  @override
  Widget build(BuildContext context) {
    final coubeMais = fotos.length < _maxFotosPorAvaliacao;

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: fotos.length + (coubeMais ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, indice) {
          if (indice == fotos.length) {
            // Último item, quando ainda cabe foto: o botão de adicionar.
            return _BotaoAdicionarFoto(onTap: aoAdicionar);
          }

          return _MiniaturaFoto(
            foto: fotos[indice],
            onRemover: () => aoRemover(indice),
          );
        },
      ),
    );
  }
}

class _BotaoAdicionarFoto extends StatelessWidget {
  final VoidCallback onTap;

  const _BotaoAdicionarFoto({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.add_a_photo_outlined, color: Colors.grey),
      ),
    );
  }
}

class _MiniaturaFoto extends StatelessWidget {
  final XFile foto;
  final VoidCallback onRemover;

  const _MiniaturaFoto({required this.foto, required this.onRemover});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          // `foto.readAsBytes()` funciona igual em mobile e web -- é por
          // isso que o app inteiro usa XFile + bytes em vez de dart:io File
          // (que nem existe no navegador) para lidar com imagens escolhidas.
          child: FutureBuilder<Uint8List>(
            future: foto.readAsBytes(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Container(width: 80, height: 80, color: Colors.grey.shade200);
              }
              return Image.memory(snapshot.data!, width: 80, height: 80, fit: BoxFit.cover);
            },
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: InkWell(
            onTap: onRemover,
            borderRadius: BorderRadius.circular(12),
            child: const CircleAvatar(
              radius: 12,
              backgroundColor: Colors.black87,
              child: Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cinco estrelas clicáveis -- widget pequeno o bastante para não merecer
/// arquivo próprio, mas reaproveitado três vezes na mesma tela.
class _SeletorEstrelas extends StatelessWidget {
  final String rotulo;
  final int valor;
  final ValueChanged<int> onChanged;

  const _SeletorEstrelas({
    required this.rotulo,
    required this.valor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rotulo, style: Theme.of(context).textTheme.titleSmall),
        Row(
          children: List.generate(5, (indice) {
            final posicao = indice + 1;
            return IconButton(
              onPressed: () => onChanged(posicao),
              icon: Icon(
                posicao <= valor ? Icons.star : Icons.star_border,
                color: Colors.amber,
              ),
            );
          }),
        ),
      ],
    );
  }
}
