// Teste de exemplo do `flutter create` removido -- ele testava o contador
// de cliques padrão (`MyApp`), que não existe mais no nosso app.
//
// Um teste de verdade para telas com Provider + chamadas HTTP precisa de
// mocks (para não depender do backend estar rodando durante o teste). Isso
// fica para uma etapa futura, quando o fluxo de telas estiver mais
// estável -- testar cedo demais, contra uma UI que ainda muda todo dia,
// custa mais manutenção do que vale.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder -- testes de widget virão numa etapa futura', () {
    expect(1 + 1, 2);
  });
}
