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

class _AvaliacaoScreenState extends State<AvaliacaoScreen> {
  // Notas 1 a 5. Começam em 5 -- é mais rápido para quem só quer elogiar
  // (o caso mais comum) e ainda assim totalmente ajustável.
  int _nota1 = 5;
  int _nota2 = 5;
  int _nota3 = 5;
  final _comentarioController = TextEditingController();
  XFile? _foto;
  bool _enviando = false;

  @override
  void dispose() {
    _comentarioController.dispose();
    super.dispose();
  }

  Future<void> _escolherFoto() async {
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
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.of(contexto).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (origem == null) return;

    final arquivo = await ImagePicker().pickImage(source: origem, imageQuality: 80);
    if (arquivo != null) {
      setState(() => _foto = arquivo);
    }
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
          foto: _foto,
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
    final rotulo1 = ehCliente ? 'Qualidade técnica' : 'Clareza do pedido';
    final rotulo2 = 'Comportamento';
    final rotulo3 = ehCliente ? 'Custo-benefício' : 'Pagamento em dia';

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
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Upload de foto: só faz sentido para o cliente avaliando o
            // profissional (avaliacoes_cliente não tem essa coluna, ver
            // Etapa de Avaliações no backend).
            if (ehCliente) ...[
              OutlinedButton.icon(
                onPressed: _escolherFoto,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(_foto == null ? 'Anexar foto do serviço (opcional)' : 'Foto selecionada: ${_foto!.name}'),
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
