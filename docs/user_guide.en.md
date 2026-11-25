🌐 **Idioma / Language:** [🇧🇷 Português](user_guide.md) | [🇺🇸 English](user_guide.en.md)

# 📖 Technical & Deployment Guide

## 1. Prerequisites & Dependencies

* **Database Engine:** Oracle Database `11g Release 2` or higher (uses standard `LISTAGG` compatible with 11g+ without relying on 12.2+ overflow syntax).
* **Required Privileges:** Read-only (`SELECT`) access on the source ERP transactional tables (`fato_pallet_cabecalho`, `fato_pallet_volumes`, and `fato_saldo_estoque`).
* **Expected Source Tables:**
  * `erp_raw.fato_pallet_cabecalho`: Pallet header records (`codigo_empresa`, `id_pallet`, `codigo_item`, `versao_item`, `status_pallet`).
  * `erp_raw.fato_pallet_volumes`: Line-item quantities and lots assigned to each pallet (`codigo_empresa`, `id_pallet`, `quantidade_volume`).
  * `erp_raw.fato_saldo_estoque`: Current physical inventory balances per warehouse (`codigo_empresa`, `codigo_item`, `versao_item`, `codigo_deposito`, `quantidade_saldo`).

---

## 2. Output Data Dictionary

| Column | Data Type | Description & Business Rule |
| :--- | :--- | :--- |
| `codigo_item` | `VARCHAR2` | Item/SKU identifier resolved via `COALESCE` across pallet and inventory tables. |
| `versao_item` | `VARCHAR2` | Item engineering version/revision resolved via `COALESCE`. |
| `qtde_pallet_consolidado` | `NUMBER` | Total quantity across pallets with status `'F'` (Closed) or `'C'` (Loaded). |
| `qtde_pallet_aberto` | `NUMBER` | Total quantity across pallets with status `'A'` (Open / pending closure). |
| `qtde_saldo_estoque` | `NUMBER` | Total positive physical balance (`> 0`) across monitored production warehouses (`103` and `106`). |
| `diferenca` | `NUMBER` | Calculated as `qtde_pallet_consolidado - qtde_saldo_estoque`. Any non-zero value flags a discrepancy. |
| `lista_depositos` | `VARCHAR2` | Ordered list of warehouses holding stock, formatted as `WAREHOUSE(BALANCE)` (e.g., `103(300), 106(150)`). |
| `lista_pallets` | `VARCHAR2` | Ordered list of active pallets, formatted as `ID(STATUS)` (e.g., `10452(F), 10489(A)`). |
| `status_auditoria` | `VARCHAR2` | Audit control flag: `'Ok'` when `diferenca = 0`; `'Verificar'` (Verify) when `diferenca <> 0`. |

---

## 3. Execution & Parameterization

### Query Parameters
* `:p_codigo_empresa` *(Required)*: Company/plant identifier for multi-tenant isolation.
* `:p_status_filtro` *(Optional)*:
  * Pass `'Verificar'` to return **only** mismatched items (recommended for automated alerting jobs).
  * Pass `'Ok'` to audit fully reconciled items.
  * Pass `NULL` to retrieve the complete plant-wide reconciliation view.

### Scheduling Setup (Exception-Driven Observability)
When deploying via an ERP scheduler or orchestrator (Airflow, Cron, Jenkins):
1. Schedule a daily pre-shift run (e.g., **04:57 AM**) passing `:p_status_filtro = 'Verificar'`.
2. Enable **empty-result suppression** so no email notification is triggered when the query returns 0 rows.
3. **Operational Remediation Matrix:**
   * **`qtde_pallet_aberto > 0` and `diferenca < 0`:** Production posting updated inventory, but pallet `(A)` was not closed by the operator.
   * **`qtde_pallet_consolidado = 0` and `diferenca < 0`:** Warehouse balance exists with no linked pallet; review production posting records.
   * **`qtde_saldo_estoque = 0` and `diferenca > 0`:** Stock was shipped or transferred out, but the pallet record remains active.
