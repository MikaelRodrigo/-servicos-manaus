/// Endereço resolvido a partir de um CEP -- SÓ rua/bairro/cidade/UF, sem
/// coordenada nenhuma (a geocodificação de verdade só acontece quando o
/// perfil é salvo, via `PATCH /profissionais/me`). Alimenta o autofill em
/// tempo real do campo de CEP nos formulários.
class EnderecoPorCep {
  final String? logradouro;
  final String? bairro;
  final String? cidade;
  final String? uf;

  const EnderecoPorCep({this.logradouro, this.bairro, this.cidade, this.uf});

  factory EnderecoPorCep.fromJson(Map<String, dynamic> json) {
    return EnderecoPorCep(
      logradouro: json['logradouro'] as String?,
      bairro: json['bairro'] as String?,
      cidade: json['cidade'] as String?,
      uf: json['uf'] as String?,
    );
  }

  /// Formata pra exibição, tipo "Rua Doutor Luiz de Freitas Melro, Centro,
  /// Manaus - AM". Ignora partes vazias/ausentes (CEPs "genéricos", tipo de
  /// zona rural, às vezes vêm só com cidade/UF, sem rua/bairro).
  String get textoFormatado {
    final cidadeUf = (cidade != null && uf != null) ? '$cidade - $uf' : cidade;
    final partes = [logradouro, bairro, cidadeUf]
        .where((parte) => parte != null && parte.trim().isNotEmpty)
        .toList();
    return partes.join(', ');
  }
}
