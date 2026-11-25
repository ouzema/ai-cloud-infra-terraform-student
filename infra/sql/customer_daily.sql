-- Séance 4, partie B : compteurs par client et par jour.
-- Source : le passé fourni par le socle (fraudfinder.tx_seed) + le flux historisé
-- dans team_really_cool.tx_history. Le résultat est relu par le service en partie C.
--
-- Choix :
--   * déduplication sur TX_ID : Pub/Sub livre au moins une fois, la table d'historique
--     est append-only ; on ne compte donc jamais les lignes brutes ;
--   * fenêtre sur TX_TS (temps de l'événement), pas sur publish_time ;
--   * le jour J n'est jamais inclus dans ses propres compteurs : la ligne du jour est
--     écrite, mais le service ne lira que les jours précédents (règle de la partie C).

CREATE OR REPLACE TABLE `team_really_cool.customer_daily` AS
WITH flux AS (
  SELECT
    TX_ID,
    ANY_VALUE(TX_TS) AS TX_TS,
    ANY_VALUE(CUSTOMER_ID) AS CUSTOMER_ID,
    ANY_VALUE(TX_AMOUNT) AS TX_AMOUNT
  FROM `team_really_cool.tx_history`
  WHERE TX_TS >= TIMESTAMP '2026-10-01'
  GROUP BY TX_ID
),
tx AS (
  -- Le passé de référence, puis notre flux.
  SELECT TX_TS, CUSTOMER_ID, TX_AMOUNT
  FROM `fraudfinder.tx_seed`
  WHERE TX_TS >= TIMESTAMP '2026-09-10'
  UNION ALL
  SELECT TX_TS, CUSTOMER_ID, TX_AMOUNT
  FROM flux
)
SELECT
  CUSTOMER_ID AS customer_id,
  DATE(TX_TS) AS day,
  COUNT(*) AS n,
  SUM(TX_AMOUNT) AS amount_sum
FROM tx
GROUP BY customer_id, day;
