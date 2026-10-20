# SPEC.md — SRM Credit Engine

**Senioridade:** Pleno | **Versão:** 1.0 | **Status:** premissas a validar com o negócio

## 1. Objetivo

Aplicação para **simular e registrar a cessão de recebíveis**, calculando valor presente (VP), deságio e pagamento em BRL ou USD. O MVP aceitará recebíveis em BRL dos tipos **Duplicata Mercantil** e **Cheque Pré-datado**, com câmbio cadastrado, histórico e extrato. Não executará transferências bancárias reais.

## 2. Premissas e regras

| Assunto | Decisão para o MVP |
|---|---|
| Fórmula | `VP = valorFace / (1 + taxaBase + spread)^prazoMeses`, com juros compostos mensais. |
| Taxas | Taxa base global de **1,00% a.m.** no MVP, atualizada manualmente/mock e versionada por vigência; spread de **1,50% a.m.** para duplicata e **2,50% a.m.** para cheque. Na fórmula, representar 1% como `0.01` (não `1.0`). Registrar os valores efetivamente aplicados em cada liquidação. |
| Prazo | **Meses inteiros**: usar o menor inteiro `n ≥ 1` para o qual `dataOperacao.plusMonths(n) ≥ vencimento` (mês parcial arredondado para cima). `dataOperacao` é a data de negócio em `America/Sao_Paulo`. Rejeitar vencimento no passado ou no mesmo dia. |
| Moeda | Título sempre em BRL; pagamento em BRL ou USD. Deságio sempre em BRL. |
| Câmbio | Cotação positiva em **BRL por 1 USD**, com instante de vigência. Na liquidação, usar a cotação mais recente vigente no instante da confirmação, desde que não tenha mais de **15 minutos**; caso ausente ou expirada, rejeitar pagamento em USD. Os 15 minutos são uma premissa inicial configurável, a validar com o negócio. |
| Simulação | Não reserva câmbio. O backend devolve um identificador/token opaco da simulação; a confirmação o referencia e o backend recalcula com os dados e a cotação vigentes. Se moeda ou valor líquido final (já arredondado) diferir do snapshot apresentado, retornar **409** e exigir nova confirmação. Não confiar em valor calculado enviado pelo frontend. |
| Liquidação | Um recebível admite **uma única liquidação**; após concluída, seu status é `SETTLED`. |

As regras de prazo, validade do câmbio e origem da taxa base são **premissas propostas** diante de ambiguidades do enunciado. Os casos de aferição usam taxa base de 1,00% a.m. e prazo inteiro conforme indicado na tabela.

## 3. Precisão e arredondamento

- **Java:** `BigDecimal` para dinheiro e taxas (nunca `float`/`double`); `LocalDate` para vencimento e `Instant` UTC para auditoria.
- **PostgreSQL:** `NUMERIC(20,2)` para montantes e `NUMERIC(20,8)` para taxas/câmbio.
- Taxas são armazenadas como frações decimais: por exemplo, 1,00% = `0.01000000` e 1,50% = `0.01500000`.
- Calcular com `MathContext.DECIMAL128` (34 dígitos), `RoundingMode.HALF_EVEN`, sem arredondar valores monetários intermediários para centavos.
- **BRL:** arredondar VP a 2 casas ao final; `deságio = valorFaceBRL − VPBRL`.
- **USD:** primeiro arredondar VPBRL a 2 casas, dividir pela cotação BRL/USD e arredondar USD a 2 casas. Preservar ambos os valores e a cotação utilizada.

**Golden cases (testes automatizados com igualdade exata ao centavo):**

| Caso | Entrada | Saída esperada |
|---|---|---|
| C1 | Duplicata; R$ 100.000; taxa base 1,00% a.m.; 3 meses; BRL | **R$ 92.859,94**; deságio R$ 7.140,06 |
| C2 | Cheque; R$ 25.000; taxa base 1,00% a.m.; 2 meses; BRL | **R$ 23.337,77**; deságio R$ 1.662,23 |
| C3 | Duplicata; R$ 100.000; taxa base 1,00% a.m.; 3 meses; USD; câmbio 5,4321 | **US$ 17.094,67**; deságio R$ 7.140,06 |

## 4. Integridade e API

- Separar API, serviços/Strategies e persistência; uma Strategy por tipo de recebível.
- Liquidação em **uma transação ACID**: inserção do registro e mudança de status confirmam juntas ou sofrem rollback.
- Exigir `Idempotency-Key` no endpoint de liquidação: chave e payload normalizado repetidos retornam o resultado original; mesma chave com conteúdo diferente retorna **409**.
- Impor restrição **UNIQUE** para recebível liquidado e atualização condicionada ao status, inclusive contra tentativas concorrentes com chaves diferentes.
- Liquidações **imutáveis**: sem rota nem permissão de aplicação para editar/excluir. Gravar cedente, recebível, valores, taxas, câmbio e sua vigência, moeda, prazo, timestamps e chave de idempotência.
- Disponibilizar operações de simulação, confirmação/liquidação, consulta de extrato e manutenção manual/mock das taxas com vigência.
- API REST documentada com Swagger/OpenAPI, validação de entradas e tratamento global de erros. Usar **201** ao liquidar, **400** para entrada inválida, **404** para recurso inexistente, **409** para conflito/idempotência e **422** para regra de negócio não atendida.

## 5. Critérios de aceite

**Usabilidade:** formulário para valor, tipo, vencimento e moeda; simulação antes da confirmação; erros claros; extrato filtrável por período, cedente e moeda, com paginação no servidor (máximo 100 itens/página).

**Segurança:** autenticação para atualizar câmbio e liquidar; validação server-side; SQL parametrizado; CORS restrito; segredos fora do código; HTTPS em produção.

**Desempenho:** em ambiente local com Docker Compose, PostgreSQL e câmbio mockado: **p95 ≤ 500 ms** para simular e **p95 ≤ 1 s** para consultar página de extrato com 10 mil registros. Metas propostas, a validar por medição.

**Confiabilidade:** testes para golden cases, limites e arredondamento, câmbio ausente/expirado, idempotência, disputa concorrente pelo mesmo recebível e rollback integral.

## 6. Dúvidas para o negócio

1. De onde vem a taxa base? Pode mudar por data, cliente ou risco?
2. Prazos como **45 dias** usam calendário, mês comercial ou pró-rata?
3. Qual cotação deve prevalecer: simulação, confirmação ou fechamento diário? Existe validade máxima?
4. Há outras moedas, tarifas, impostos ou regras por cedente?
5. O **lote** deve ser liquidado integralmente ou item a item? Qual volume esperado?
6. Como tratar estorno/cancelamento, perfis de acesso e retenção de auditoria?

**Fora do MVP:** pagamento bancário real, novos tipos/moedas e processamento de lotes. Os cortes serão descritos em `DECISIONS.md`.
