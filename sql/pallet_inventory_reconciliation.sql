/*
 * Projeto: Auditoria de Conciliação Física — Estoque Paletizado vs. Saldo por Depósito
 * Descrição: Realiza o batimento bilateral (FULL OUTER JOIN) entre volumes paletizados
 *            e saldos contábeis/físicos em depósitos produtivos, segregando pallets
 *            fechados/carregados de pallets abertos pendentes de encerramento.
 * Dialeto: Oracle SQL (11g+)
 */

SELECT consulta.*
  FROM (
    WITH cte_pallet_volumes AS (
        -- 1º estágio (Pallets): consolida volumes no grão de cada pallet (empresa, item, versão, sequencial)
        -- Evita produto cartesiano e duplicação de identificadores na agregação textual (LISTAGG)
        SELECT p.codigo_empresa,
               p.codigo_item,
               p.versao_item,
               p.id_pallet,
               p.status_pallet,
               SUM(pv.quantidade_volume) AS qtde_por_pallet
          FROM erp_raw.fato_pallet_cabecalho p
         INNER JOIN erp_raw.fato_pallet_volumes pv
            ON p.codigo_empresa = pv.codigo_empresa
           AND p.id_pallet      = pv.id_pallet
         WHERE p.codigo_empresa = :p_codigo_empresa
           AND p.status_pallet  IN ('F', 'C', 'A') -- F: Fechado | C: Carregado | A: Aberto
           -- AND p.codigo_item = '100638'
           -- AND p.versao_item = '3'
         GROUP BY p.codigo_empresa,
                  p.codigo_item,
                  p.versao_item,
                  p.id_pallet,
                  p.status_pallet
    ),
    cte_pallets_consolidado AS (
        -- 2º estágio (Pallets): agrega volumes por item/versão via agregação condicional
        -- e gera lista rastreável dos pallets envolvidos ordenados por status e identificador
        SELECT pv.codigo_empresa,
               pv.codigo_item,
               pv.versao_item,
               SUM(CASE WHEN pv.status_pallet IN ('F', 'C') THEN pv.qtde_por_pallet ELSE 0 END) AS qtde_pallet_consolidado,
               SUM(CASE WHEN pv.status_pallet = 'A'         THEN pv.qtde_por_pallet ELSE 0 END) AS qtde_pallet_aberto,
               LISTAGG(pv.id_pallet || '(' || pv.status_pallet || ')', ', ')
                   WITHIN GROUP (ORDER BY pv.status_pallet, pv.id_pallet)                       AS lista_pallets
          FROM cte_pallet_volumes pv
         GROUP BY pv.codigo_empresa,
                  pv.codigo_item,
                  pv.versao_item
    ),
    cte_saldos_deposito AS (
        -- 1º estágio (Saldos): consolida o saldo por depósito produtivo (103 e 106)
        -- Evita repetição de códigos de depósito quando há múltiplos lotes ou endereços
        SELECT s.codigo_empresa,
               s.codigo_item,
               s.versao_item,
               s.codigo_deposito,
               SUM(s.quantidade_saldo) AS qtde_por_deposito
          FROM erp_raw.fato_saldo_estoque s
         WHERE s.codigo_empresa   = :p_codigo_empresa
           AND s.quantidade_saldo > 0
           AND s.codigo_deposito  IN (103, 106)
           -- AND s.codigo_item   = '100638'
           -- AND s.versao_item   = '3'
         GROUP BY s.codigo_empresa,
                  s.codigo_item,
                  s.versao_item,
                  s.codigo_deposito
    ),
    cte_saldos_consolidado AS (
        -- 2º estágio (Saldos): agrega o saldo total do item/versão e concatena o detalhamento por depósito
        SELECT sd.codigo_empresa,
               sd.codigo_item,
               sd.versao_item,
               SUM(sd.qtde_por_deposito)                                              AS qtde_saldo_estoque,
               LISTAGG(sd.codigo_deposito || '(' || sd.qtde_por_deposito || ')', ', ')
                   WITHIN GROUP (ORDER BY sd.codigo_deposito)                         AS lista_depositos
          FROM cte_saldos_deposito sd
         GROUP BY sd.codigo_empresa,
                  sd.codigo_item,
                  sd.versao_item
    )
    -- Camada Final: Conciliação bilateral (FULL OUTER JOIN) para detectar órfãos em ambas as pontas
    SELECT COALESCE(p.codigo_item, s.codigo_item)                                AS codigo_item,
           COALESCE(p.versao_item, s.versao_item)                                AS versao_item,
           NVL(p.qtde_pallet_consolidado, 0)                                     AS qtde_pallet_consolidado,
           NVL(p.qtde_pallet_aberto, 0)                                          AS qtde_pallet_aberto,
           NVL(s.qtde_saldo_estoque, 0)                                          AS qtde_saldo_estoque,
           (NVL(p.qtde_pallet_consolidado, 0) - NVL(s.qtde_saldo_estoque, 0))    AS diferenca,
           s.lista_depositos,
           p.lista_pallets,
           DECODE((NVL(p.qtde_pallet_consolidado, 0) - NVL(s.qtde_saldo_estoque, 0)), 0, 'Ok', 'Verificar') AS status_auditoria
      FROM cte_pallets_consolidado p
      FULL OUTER JOIN cte_saldos_consolidado s
        ON p.codigo_empresa = s.codigo_empresa
       AND p.codigo_item    = s.codigo_item
       AND p.versao_item    = s.versao_item
     ORDER BY COALESCE(p.codigo_item, s.codigo_item),
              COALESCE(p.versao_item, s.versao_item)
) consulta
 WHERE consulta.status_auditoria = NVL(:p_status_filtro, consulta.status_auditoria);
