import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme/app_theme.dart';

/// Resultado de uma edição de foto de perfil bem-sucedida: o `XFile` (para
/// continuar usando exatamente o mesmo contrato que `ProfissionaisService`/
/// `ClientesService` já esperavam em `foto`) e os bytes já lidos (para a
/// pré-visualização imediata em `MemoryImage`, sem precisar reler o arquivo).
typedef FotoPerfilEditada = ({XFile arquivo, Uint8List bytes});

/// Fluxo completo de troca de foto de perfil: escolher a origem (câmera ou
/// galeria) → selecionar a imagem → RECORTAR em 1:1 antes de devolver.
///
/// Devolve `null` se a pessoa cancelar em qualquer etapa (não escolheu
/// origem, cancelou o seletor de imagem, ou cancelou o recorte) -- quem
/// chama não precisa distinguir ONDE cancelou, só se terminou com uma foto
/// pronta ou não.
///
/// Por que recortar ANTES de mandar pro backend, e não depois: a foto de
/// perfil é sempre exibida num círculo (`CircleAvatar`) em todas as telas
/// que a mostram (mapa, perfil público, portfólio) -- se a pessoa manda uma
/// foto retangular sem recortar, o preview e o resultado final nunca batem
/// exatamente (o círculo corta uma área diferente da que ela escolheu). Com
/// o recorte na entrada, o que ela vê na hora de ajustar É o que vai ser
/// salvo -- sem surpresa depois do upload.
Future<FotoPerfilEditada?> escolherEEditarFotoDePerfil(BuildContext context) async {
  final origem = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (contextoFolha) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Tirar foto'),
            onTap: () => Navigator.of(contextoFolha).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Escolher da galeria'),
            onTap: () => Navigator.of(contextoFolha).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (origem == null) return null;

  final selecionada = await ImagePicker().pickImage(source: origem, imageQuality: 85);
  if (selecionada == null) return null;

  // `context` atravessou um `await` (o seletor de imagem) -- checagem
  // obrigatória antes de usá-lo de novo (o widget pode ter saído da árvore
  // enquanto a pessoa escolhia a foto, ex.: navegou pra trás).
  if (!context.mounted) return null;

  final recortada = await ImageCropper().cropImage(
    sourcePath: selecionada.path,
    // Requisito da foto de perfil: sempre quadrada, sem opção de mudar --
    // é o mesmo formato que TODO CircleAvatar do app espera.
    aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 85,
    uiSettings: [
      // Tela nativa de recorte no Android (com zoom/arraste + botão de
      // confirmar embutidos). Cores alinhadas à paleta do redesign
      // (AppColors.destaque) em vez do azul padrão do Android.
      AndroidUiSettings(
        toolbarTitle: 'Ajustar foto de perfil',
        toolbarColor: AppColors.destaque,
        toolbarWidgetColor: Colors.white,
        statusBarColor: AppColors.destaque,
        activeControlsWidgetColor: AppColors.destaque,
        backgroundColor: AppColors.fundo,
        initAspectRatio: CropAspectRatioPreset.square,
        lockAspectRatio: true, // trava em 1:1 -- sem opção de escolher outro formato.
        hideBottomControls: false,
      ),
      IOSUiSettings(
        title: 'Ajustar foto de perfil',
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
        aspectRatioPickerButtonHidden: true, // esconde o seletor de formato -- só 1:1 existe aqui.
      ),
      // Flutter Web não tem crop nativo -- o pacote usa uma implementação
      // própria em JS por baixo (mesmo princípio do cropper.js: canvas +
      // arraste do mouse), mas exposta pela MESMA API Dart acima. Por isso
      // o app funciona igual em mobile e no Chrome sem código duplicado.
      WebUiSettings(context: context),
    ],
  );
  if (recortada == null) return null;

  final bytes = await recortada.readAsBytes();
  final arquivoFinal = XFile(recortada.path, name: 'foto_perfil.jpg');
  return (arquivo: arquivoFinal, bytes: bytes);
}

/// Avatar redondo com o "selo" de câmera no canto + botão "Trocar foto de
/// perfil" abaixo -- a mesma composição visual que `editar_perfil_screen.dart`
/// e `perfil_cliente_screen.dart` já usavam individualmente (duplicada nos
/// dois arquivos); virou um widget único para as duas telas nunca mais
/// divergirem visualmente uma da outra.
///
/// Widget "burro" de propósito: não sabe nada sobre `ImagePicker` nem
/// `ImageCropper` -- só mostra o estado atual (bytes já recortados, ou a
/// URL da foto já salva) e avisa quando alguém toca, via `onTocar`. Quem usa
/// decide o que fazer no toque (chamar `escolherEEditarFotoDePerfil`, tipicamente).
class AvatarFotoPerfil extends StatelessWidget {
  final Uint8List? bytesFotoEscolhida;
  final String? urlFotoAtual;
  final VoidCallback onTocar;

  const AvatarFotoPerfil({
    super.key,
    required this.bytesFotoEscolhida,
    required this.urlFotoAtual,
    required this.onTocar,
  });

  @override
  Widget build(BuildContext context) {
    final urlAtual = urlFotoAtual;
    return Column(
      children: [
        GestureDetector(
          onTap: onTocar,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 56,
                backgroundColor: AppColors.superficieSecundaria,
                backgroundImage: bytesFotoEscolhida != null
                    ? MemoryImage(bytesFotoEscolhida!)
                    : (urlAtual != null ? NetworkImage(urlAtual) : null) as ImageProvider?,
                child: bytesFotoEscolhida == null && urlAtual == null
                    ? Icon(Icons.person, size: 56, color: AppColors.textoSecundario)
                    : null,
              ),
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.destaque,
                child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onTocar,
          child: const Text('Trocar foto de perfil'),
        ),
      ],
    );
  }
}
