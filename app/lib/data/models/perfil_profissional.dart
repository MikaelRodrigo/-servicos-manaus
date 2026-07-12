/// Espelha GET /profissionais/:id (ver `buscarPerfilPublico` no backend).
///
/// É o "cartão de visitas" completo do profissional -- o que aparece quando
/// o cliente toca no pino dele no mapa. Repare que NÃO existe campo `email`
/// aqui: a rota pública nunca devolve isso (ver comentário no repository do
/// backend sobre spam/scraping). Quem precisar falar com o profissional usa
/// o `contato` (telefone/WhatsApp).
class PerfilProfissional {
  final String id;
  final String tipoPessoa; // 'PF' ou 'PJ'
  final String nomeExibicao;
  final String? atuacao;
  final String? descricao;
  final String? urlFotoPerfil;
  final String contato;
  final double? latitude;
  final double? longitude;

  const PerfilProfissional({
    required this.id,
    required this.tipoPessoa,
    required this.nomeExibicao,
    required this.atuacao,
    required this.descricao,
    required this.urlFotoPerfil,
    required this.contato,
    required this.latitude,
    required this.longitude,
  });

  factory PerfilProfissional.fromJson(Map<String, dynamic> json) {
    return PerfilProfissional(
      id: json['profissional_id'] as String,
      tipoPessoa: json['tipo_pessoa'] as String,
      nomeExibicao: json['nome_exibicao'] as String,
      atuacao: json['atuacao'] as String?,
      descricao: json['descricao'] as String?,
      urlFotoPerfil: json['url_foto_perfil'] as String?,
      contato: json['contato'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}

/// Espelha GET /profissionais/:id/avaliacoes/resumo (ver `ResumoDeAvaliacoes`
/// no backend). As médias vêm `null` quando o profissional ainda não tem
/// nenhuma avaliação -- e é assim que a tela distingue "0 estrelas" (ruim)
/// de "ninguém avaliou ainda" (neutro).
///
/// `distribuicao*` é sempre uma lista de 5 posições, na ordem
/// [nota 5, nota 4, nota 3, nota 2, nota 1] -- quantas avaliações deram
/// cada nota naquele critério. É o que alimenta o gráfico de barras
/// "5 estrelas ▬▬▬ 482" no perfil.
class ResumoAvaliacoes {
  final int totalAvaliacoes;
  final double? mediaTecnico;
  final double? mediaComportamental;
  final double? mediaEconomico;
  final double? mediaGeral;
  final List<int> distribuicaoTecnico;
  final List<int> distribuicaoComportamental;
  final List<int> distribuicaoEconomico;

  const ResumoAvaliacoes({
    required this.totalAvaliacoes,
    required this.mediaTecnico,
    required this.mediaComportamental,
    required this.mediaEconomico,
    required this.mediaGeral,
    required this.distribuicaoTecnico,
    required this.distribuicaoComportamental,
    required this.distribuicaoEconomico,
  });

  static List<int> _distribuicao(dynamic valor) {
    return (valor as List<dynamic>? ?? const [0, 0, 0, 0, 0])
        .map((item) => item as int)
        .toList();
  }

  factory ResumoAvaliacoes.fromJson(Map<String, dynamic> json) {
    return ResumoAvaliacoes(
      totalAvaliacoes: json['total_avaliacoes'] as int,
      mediaTecnico: (json['media_tecnico'] as num?)?.toDouble(),
      mediaComportamental: (json['media_comportamental'] as num?)?.toDouble(),
      mediaEconomico: (json['media_economico'] as num?)?.toDouble(),
      mediaGeral: (json['media_geral'] as num?)?.toDouble(),
      distribuicaoTecnico: _distribuicao(json['distribuicao_tecnico']),
      distribuicaoComportamental: _distribuicao(json['distribuicao_comportamental']),
      distribuicaoEconomico: _distribuicao(json['distribuicao_economico']),
    );
  }
}

/// Espelha um item de GET /profissionais/:id/portfolio (view
/// `vw_historico_portifolio` no backend) -- um serviço já concluído e
/// avaliado por um cliente, com fotos e comentário. É o "histórico de
/// portfólio alimentado pelos clientes" que aparece no perfil público.
///
/// `avaliacaoId` (não `idServico`) é o identificador usado para curtir --
/// ver `ProfissionaisService.curtirAvaliacao`. `urlsFotos` é sempre uma
/// lista (nunca null): pode vir vazia quando o cliente não anexou foto
/// nenhuma na avaliação.
class ItemPortfolio {
  final String idServico;
  final String avaliacaoId;
  final String nomeCliente;
  final String? comentario;
  final List<String> urlsFotos;
  final int estrelasTecnico;
  final int estrelasComportamental;
  final int estrelasEconomico;
  final double mediaEstrelas;
  final int totalCurtidas;
  final bool curtidoPorMim;
  final DateTime dataConclusao;
  final DateTime dataAvaliacao;

  const ItemPortfolio({
    required this.idServico,
    required this.avaliacaoId,
    required this.nomeCliente,
    required this.comentario,
    required this.urlsFotos,
    required this.estrelasTecnico,
    required this.estrelasComportamental,
    required this.estrelasEconomico,
    required this.mediaEstrelas,
    required this.totalCurtidas,
    required this.curtidoPorMim,
    required this.dataConclusao,
    required this.dataAvaliacao,
  });

  factory ItemPortfolio.fromJson(Map<String, dynamic> json) {
    return ItemPortfolio(
      idServico: json['id_servico'] as String,
      avaliacaoId: json['avaliacao_id'] as String,
      nomeCliente: json['nome_cliente'] as String,
      comentario: json['comentario'] as String?,
      urlsFotos: (json['urls_fotos'] as List<dynamic>? ?? const [])
          .map((item) => item as String)
          .toList(),
      estrelasTecnico: json['estrelas_tecnico'] as int,
      estrelasComportamental: json['estrelas_comportamental'] as int,
      estrelasEconomico: json['estrelas_economico'] as int,
      mediaEstrelas: (json['media_estrelas'] as num).toDouble(),
      totalCurtidas: json['total_curtidas'] as int,
      curtidoPorMim: json['curtido_por_mim'] as bool,
      dataConclusao: DateTime.parse(json['data_conclusao'] as String),
      dataAvaliacao: DateTime.parse(json['data_avaliacao'] as String),
    );
  }
}
