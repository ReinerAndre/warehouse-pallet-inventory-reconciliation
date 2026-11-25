🌐 **Idioma / Language:** [🇧🇷 Português](user_guide.md) | [🇺🇸 English](user_guide.en.md)

# 📖 Guia Técnico e de Implantação

## 1. Pré-requisitos e Dependências

* **Banco de Dados:** Oracle Database `11g Release 2` ou superior (utiliza `LISTAGG` padrão compatível com versões 11g+ sem dependências de cláusulas exclusivas do 12.2+).
* **Privilégios Necessários:** Permissão de leitura (`SELECT`) nas tabelas transacionais de origem do ERP (`fato_pallet_cabecalho`, `fato_pallet_volumes` e `fato_saldo_estoque`).
* **Tabelas de Origem Esperadas:**
  * `erp_raw.fato_pallet_cabecalho`: Cabeçalho dos unitizadores/pallets (`codigo_empresa`, `id_pallet`, `codigo_item`, `versao_item`, `status_pallet`).
  * `erp_raw.fato_pallet_volumes`: Detalhamento de quantidades e lotes vinculados a cada pallet (`codigo_empresa`, `id_pallet`, `quantidade_volume`).
  * `erp_raw.fato_saldo_estoque`: Posição atual de saldo físico por depósito (`codigo_empresa`, `codigo_item`, `versao_item`, `codigo_deposito`, `quantidade_saldo`).

---

## 2. Dicionário de Dados de Saída

| Coluna | Tipo de Dado | Descrição e Regra de Negócio |
| :--- | :--- | :--- |
| `codigo_item` | `VARCHAR2` | Código identificador do produto/item consolidado via `COALESCE` entre pallets e saldos. |
| `versao_item` | `VARCHAR2` | Versão/revisão de engenharia do item consolidada via `COALESCE`. |
| `qtde_pallet_consolidado` | `NUMBER` | Soma das quantidades dos pallets com status `'F'` (Fechado) ou `'C'` (Carregado). |
| `qtde_pallet_aberto` | `NUMBER` | Soma das quantidades dos pallets com status `'A'` (Aberto / pendente de fechamento). |
| `qtde_saldo_estoque` | `NUMBER` | Soma do saldo físico positivo (`> 0`) nos depósitos produtivos monitorados (`103` e `106`). |
| `diferenca` | `NUMBER` | Resultado de `qtde_pallet_consolidado - qtde_saldo_estoque`. Valores diferentes de `0` indicam divergência. |
| `lista_depositos` | `VARCHAR2` | Lista ordenada dos depósitos com saldo no formato `DEPOSITO(SALDO)` (ex.: `103(300), 106(150)`). |
| `lista_pallets` | `VARCHAR2` | Lista ordenada dos pallets ativos no formato `ID(STATUS)` (ex.: `10452(F), 10489(A)`). |
| `status_auditoria` | `VARCHAR2` | Indicador de controle: `'Ok'` quando `diferenca = 0`; `'Verificar'` quando `diferenca <> 0`. |

---

## 3. Como Executar e Parametrizar

### Parâmetros de Execução
* `:p_codigo_empresa` *(Obrigatório)*: Código numérico da empresa/planta para isolamento multiempresa.
* `:p_status_filtro` *(Opcional)*:
  * Passe `'Verificar'` para retornar **apenas** os itens com divergência (recomendado para jobs de alerta).
  * Passe `'Ok'` para auditar itens conciliados.
  * Passe `NULL` para retornar a visão completa da planta.

### Configuração de Agendamento (Observabilidade por Exceção)
Para implantação em motores de agendamento do ERP ou orquestradores (Airflow, Cron, Jenkins):
1. Agende a execução para o horário pré-turno (ex.: **04:57 AM** diário) passando `:p_status_filtro = 'Verificar'`.
2. Configure a regra de disparo de e-mail com **supressão de envio vazio** (*não enviar quando o dataset retornar 0 linhas*).
3. **Matriz de Tratativa Operacional:**
   * **`qtde_pallet_aberto > 0` e `diferenca < 0`:** O apontamento sensibilizou o estoque, mas o pallet `(A)` ainda não foi fechado pelo operador.
   * **`qtde_pallet_consolidado = 0` e `diferenca < 0`:** Existe saldo em depósito sem nenhum pallet gerado; verificar apontamento de produção.
   * **`qtde_saldo_estoque = 0` e `diferenca > 0`:** O saldo já foi baixado/transferido, mas o pallet permanece ativo sem encerramento.
