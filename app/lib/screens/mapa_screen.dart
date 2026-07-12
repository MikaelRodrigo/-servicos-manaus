import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../data/models/profissional.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import '../providers/localizacao_provider.dart';
import '../providers/profissionais_provider.dart';
import 'editar_perfil_screen.dart';
import 'perfil_profissional_screen.dart';

/// Coordenada de fallback -- Teatro Amazonas, Centro de Manaus. Só é usada
/// se a localização do usuário ainda não chegou (evita o mapa nascer no
/// meio do Oceano Atlântico, em 0,0, antes do GPS responder).
const _centroManaus = LatLng(-3.130130, -60.023400);

class MapaScreen extends StatefulWidget {
  const MapaScreen({super.key});

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  final _mapController = MapController();
  final _profissaoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // `addPostFrameCallback` porque não dá para chamar `context.read` (que
    // dispara `notifyListeners`) durante o `initState` -- o Flutter ainda
    // está no meio da construção da árvore de widgets nesse momento.
    WidgetsBinding.instance.addPostFrameCallback((_) => _atualizarLocalizacaoEBuscar());
  }

  @override
  void dispose() {
    _profissaoController.dispose();
    super.dispose();
  }

  Future<void> _atualizarLocalizacaoEBuscar() async {
    final localizacao = context.read<LocalizacaoProvider>();
    await localizacao.obterLocalizacaoAtual();

    if (!mounted) return;

    final posicao = localizacao.posicao;
    if (posicao == null) {
      // `obterLocalizacaoAtual` já guardou a mensagem de erro em
      // `localizacao.erro` -- o `build()` abaixo mostra ela na tela.
      return;
    }

    _mapController.move(LatLng(posicao.latitude, posicao.longitude), 14);
    await _buscar(posicao.latitude, posicao.longitude);
  }

  Future<void> _buscar(double latitude, double longitude) async {
    await context.read<ProfissionaisProvider>().buscarProximos(
          latitude: latitude,
          longitude: longitude,
          raioKm: 10,
          profissao: _profissaoController.text.trim(),
        );
  }

  /// Toca no pino -> vai direto para o perfil público do profissional
  /// (foto, descrição, avaliações e portfólio). O pedido de serviço agora
  /// mora dentro dessa tela, não mais num bottom sheet resumido aqui.
  void _abrirPerfilProfissional(Profissional profissional) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PerfilProfissionalScreen(profissionalId: profissional.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizacao = context.watch<LocalizacaoProvider>();
    final profissionais = context.watch<ProfissionaisProvider>();
    final usuario = context.watch<AuthProvider>().usuario;

    final posicaoAtual = localizacao.posicao;

    final marcadores = <Marker>[
      if (posicaoAtual != null)
        Marker(
          point: LatLng(posicaoAtual.latitude, posicaoAtual.longitude),
          width: 24,
          height: 24,
          child: const DecoratedBox(
            decoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
            child: Icon(Icons.circle, color: Colors.white, size: 10),
          ),
        ),
      ...profissionais.resultados.map(
        (p) => Marker(
          point: LatLng(p.latitude, p.longitude),
          width: 42,
          height: 42,
          child: GestureDetector(
            onTap: () => _abrirPerfilProfissional(p),
            child: const Icon(Icons.location_pin, color: Colors.redAccent, size: 42),
          ),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Olá, ${usuario?.nome ?? ''}'),
        actions: [
          // Só profissional tem perfil público para editar -- cliente não
          // aparece no mapa, então não tem "perfil" nesse sentido.
          if (usuario?.papel == Papel.profissional)
            IconButton(
              tooltip: 'Editar meu perfil',
              icon: const Icon(Icons.edit),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditarPerfilScreen()),
                );
              },
            ),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _profissaoController,
                    decoration: const InputDecoration(
                      hintText: 'Filtrar por profissão (ex: eletricista)',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) {
                      if (posicaoAtual != null) {
                        _buscar(posicaoAtual.latitude, posicaoAtual.longitude);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Atualizar localização e buscar',
                  onPressed: _atualizarLocalizacaoEBuscar,
                  icon: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),

          if (localizacao.erro != null)
            _AvisoFaixa(mensagem: localizacao.erro!, cor: Colors.orange),
          if (profissionais.erro != null)
            _AvisoFaixa(mensagem: profissionais.erro!, cor: Colors.red),
          if (localizacao.carregando || profissionais.carregando)
            const LinearProgressIndicator(minHeight: 2),

          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: posicaoAtual != null
                    ? LatLng(posicaoAtual.latitude, posicaoAtual.longitude)
                    : _centroManaus,
                initialZoom: 13,
              ),
              children: [
                // Camada de "ladrilhos" (as imagens do mapa em si), vindo
                // dos servidores públicos do OpenStreetMap. `userAgentPackageName`
                // é OBRIGATÓRIO pela política de uso do OSM -- sem ele,
                // requests podem ser bloqueadas.
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.servicosmanaus.servicos_manaus_app',
                ),
                MarkerLayer(markers: marcadores),
                // Créditos ao OpenStreetMap -- também exigido pela política
                // de uso deles. Nunca remova isto de um app que usa os
                // ladrilhos gratuitos do OSM.
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvisoFaixa extends StatelessWidget {
  final String mensagem;
  final Color cor;

  const _AvisoFaixa({required this.mensagem, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: cor.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(mensagem, style: TextStyle(color: cor.withValues(alpha: 1))),
    );
  }
}
