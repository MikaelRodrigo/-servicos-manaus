import 'categoria.dart' show TagSubcategoria;

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
  // TODAS as tags de especialidade do profissional (migração 11 no backend)
  // -- diferente de `atuacao`/`categoria` acima, que continuam sendo só a
  // escolha ÚNICA feita no cadastro. É o que alimenta os "boxes" na tela de
  // editar perfil e os chips no perfil público -- ver TagSubcategoria.
  final List<TagSubcategoria> subcategorias;

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
    this.subcategorias = const [],
  });

  factory PerfilProfissional.fromJson(Map<String, dynamic> json) {
    final listaTags = json['subcategorias'] as List<dynamic>? ?? const [];
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
      subcategorias: listaTags
          .map((item) => TagSubcategoria.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Espelha GET /profissionais/me (ver `buscarMeuPerfil` no backend --
/// `PerfilProfissional`, o mesmo nome do lado TypeScript, mas são arquivos
/// de linguagens diferentes, sem colisão real).
///
/// Diferente de [PerfilProfissional] (o "cartão de visitas" PÚBLICO): esta
/// classe é o que o PRÓPRIO profissional vê ao editar seu perfil --
/// inclui `email`, `contato` e `endereco`, que a rota pública nunca
/// devolve. Usada só em `editar_perfil_screen.dart`, nunca em telas de
/// terceiros.
class MeuPerfilProfissional {
  final String id;
  final String tipoPessoa;
  final String nomeExibicao;
  final String email;
  final String? contato;
  final String? endereco;
  final String? atuacao;
  final String? categoria;
  final String? descricao;
  final String? urlFotoPerfil;
  final String? cep;
  final String? enderecoAtuacao;
  final double? latitude;
  final double? longitude;
  final List<TagSubcategoria> subcategorias;

  const MeuPerfilProfissional({
    required this.id,
    required this.tipoPessoa,
    required this.nomeExibicao,
    required this.email,
    required this.contato,
    required this.endereco,
    required this.atuacao,
    required this.categoria,
    required this.descricao,
    required this.urlFotoPerfil,
    required this.cep,
    required this.enderecoAtuacao,
    required this.latitude,
    required this.longitude,
    this.subcategorias = const [],
  });

  factory MeuPerfilProfissional.fromJson(Map<String, dynamic> json) {
    final listaTags = json['subcategorias'] as List<dynamic>? ?? const [];
    return MeuPerfilProfissional(
      id: json['profissional_id'] as String,
      tipoPessoa: json['tipo_pessoa'] as String,
      nomeExibicao: json['nome_exibicao'] as String,
      email: json['email'] as String,
      contato: json['contato'] as String?,
      endereco: json['endereco'] as String?,
      atuacao: json['atuacao'] as String?,
      categoria: json['categoria'] as String?,
      descricao: json['descricao'] as String?,
      urlFotoPerfil: json['url_foto_perfil'] as String?,
      cep: json['cep'] as String?,
      enderecoAtuacao: json['endereco_atuacao'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      subcategorias: listaTags
          .map((item) => TagSubcategoria.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Espelha um item de GET /profissionais/:id/portfolio-fotos (tabela
/// `portfolio_profissional`, migração 16) -- uma foto da GALERIA CURADA
/// PELO PRÓPRIO PROFISSIONAL, sem vínculo com nenhum serviço/avaliação
/// específico. Diferente por completo de [ItemPortfolio] (histórico
/// alimentado pelos CLIENTES via avaliação) -- não confundir os dois na
/// UI: esta é a seção nova "Fotos do trabalho"/"Portfólio visual".
class FotoPortfolio {
  final String idFoto;
  final String urlFoto;
  final String? legenda;
  final int ordem;
  final DateTime createdAt;

  const FotoPortfolio({
    required this.idFoto,
    required this.urlFoto,
    required this.legenda,
    required this.ordem,
    required this.createdAt,
  });

  factory FotoPortfolio.fromJson(Map<String, dynamic> json) {
    return FotoPortfolio(
      idFoto: json['id_foto'] as String,
      urlFoto: json['url_foto'] as String,
      legenda: json['legenda'] as String?,
      ordem: json['ordem'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
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
  /// Especialidade contratada NESTE serviço -- ver migração 12 no backend.
  /// É o que permite o perfil público segmentar o histórico por categoria
  /// (ex.: mostrar só as avaliações de "Eletricista", separadas das de
  /// "Pintor" do mesmo profissional). `null` só em raríssimos serviços
  /// legados sem categoria alguma.
  final int? subcategoriaId;
  final String? subcategoriaNome;
  final int? categoriaId;
  final String? categoriaNome;
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
    required this.subcategoriaId,
    required this.subcategoriaNome,
    required this.categoriaId,
    required this.categoriaNome,
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
      subcategoriaId: json['subcategoria_id'] as int?,
      subcategoriaNome: json['subcategoria_nome'] as String?,
      categoriaId: json['categoria_id'] as int?,
      categoriaNome: json['categoria_nome'] as String?,
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
