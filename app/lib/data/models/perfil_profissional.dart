/// Espelha GET /profissionais/:id (ver `buscarPerfilPublico` no backend).
///
/// É o "cartão de visitas" completo do profissional -- o que aparece quando
/// o cliente toca no pino dele no mapa. Repare que NÃO existem campos
/// `email` NEM `contato` aqui: a rota pública nunca devolve isso (ver
/// comentário no repository do backend sobre spam/scraping). O pedido de
/// serviço acontece pelo próprio app ("Solicitar serviço"), sem precisar
/// do telefone do profissional.
class PerfilProfissional {
  final String id;
  final String tipoPessoa; // 'PF' ou 'PJ'
  final String nomeExibicao;
  final String? atuacao;
  // Nome da CATEGORIA-mãe da subcategoria em `atuacao` (migração 09) -- ex.:
  // atuacao = "Eletricista", categoria = "Manutenção e Reforma". Usado na
  // edição de perfil para mostrar "categoria atual" antes de trocar.
  final String? categoria;
  final String? descricao;
  final String? urlFotoPerfil;
  final double? latitude;
  final double? longitude;
  final String? enderecoAtuacao;

  const PerfilProfissional({
    required this.id,
    required this.tipoPessoa,
    required this.nomeExibicao,
    required this.atuacao,
    required this.categoria,
    required this.descricao,
    required this.urlFotoPerfil,
    required this.latitude,
    required this.longitude,
    required this.enderecoAtuacao,
  });

  factory PerfilProfissional.fromJson(Map<String, dynamic> json) {
    return PerfilProfissional(
      id: json['profissional_id'] as String,
      tipoPessoa: json['tipo_pessoa'] as String,
      nomeExibicao: json['nome_exibicao'] as String,
      atuacao: json['atuacao'] as String?,
      categoria: json['categoria'] as String?,
      descricao: json['descricao'] as String?,
      urlFotoPerfil: json['url_foto_perfil'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      enderecoAtuacao: json['endereco_atuacao'] as String?,
    );
  }
}

/// Espelha GET /profissionais/:id/avaliacoes/resumo (ver `ResumoDeAvaliacoes`
/// no backend). As médias vêm `null` quando o profissional ainda não tem
/// nenhuma avaliação -- e é assim que a tela distingue "0 estrelas" (ruim)
/// de "ninguém avaliou ainda" (neutro).
class ResumoAvaliacoes {
  final int totalAvaliacoes;
  final double? mediaTecnico;
  final double? mediaComportamental;
  final double? mediaEconomico;
  final double? mediaGeral;

  const ResumoAvaliacoes({
    required this.totalAvaliacoes,
    required this.mediaTecnico,
    required this.mediaComportamental,
    required this.mediaEconomico,
    required this.mediaGeral,
  });

  factory ResumoAvaliacoes.fromJson(Map<String, dynamic> json) {
    return ResumoAvaliacoes(
      totalAvaliacoes: json['total_avaliacoes'] as int,
      mediaTecnico: (json['media_tecnico'] as num?)?.toDouble(),
      mediaComportamental: (json['media_comportamental'] as num?)?.toDouble(),
      mediaEconomico: (json['media_economico'] as num?)?.toDouble(),
      mediaGeral: (json['media_geral'] as num?)?.toDouble(),
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
/// nenhuma na avaliação. `urlFotoCliente` (migração 07) é a foto de PERFIL
/// do cliente que avaliou -- diferente de `urlsFotos`, que são as fotos DO
/// SERVIÇO anexadas na avaliação.
class ItemPortfolio {
  final String idServico;
  final String avaliacaoId;
  final String nomeCliente;
  final String? urlFotoCliente;
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
    required this.urlFotoCliente,
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
      urlFotoCliente: json['url_foto_cliente'] as String?,
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
