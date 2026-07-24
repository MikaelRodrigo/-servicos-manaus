/// Espelha o campo `verificacao` devolvido por `POST /auth/cadastro/*` e
/// `POST /auth/verificar-telefone/reenviar` (migração 17 no backend --
/// `ResultadoEnvioSms` em `services/sms.ts`).
///
/// `codigo` só vem preenchido quando `simulado == true` (nenhum provedor de
/// SMS configurado no backend ainda -- ver comentário em
/// `backend/src/services/sms.ts`): é o código de teste, mostrado direto na
/// tela para dar para confirmar sem precisar de um celular de verdade. Em
/// modo real, `codigo` é sempre `null` -- o código só chega por SMS mesmo.
class ResultadoEnvioCodigo {
  final bool simulado;
  final String? codigo;

  const ResultadoEnvioCodigo({required this.simulado, required this.codigo});

  factory ResultadoEnvioCodigo.fromJson(Map<String, dynamic> json) {
    return ResultadoEnvioCodigo(
      simulado: json['simulado'] as bool,
      codigo: json['codigo'] as String?,
    );
  }
}
