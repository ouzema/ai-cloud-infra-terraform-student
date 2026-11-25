-- Séance 4, partie B : compteurs par terminal et par jour.
-- Même logique que customer_daily.sql, avec deux différences :
--   * le flux ne porte pas de label de fraude : TX_FRAUD vaut NULL pour ses lignes ;
--   * n_fraud se calcule avec COUNTIF(TX_FRAUD = 1), qui ignore les NULL et renvoie 0
--     pour le 1er octobre. C'est normal : un label de fraude arrive plusieurs jours
--     après la transaction, et le service ne lit le taux qu'avec 7 jours de retard.

CREATE OR REPLACE TABLE `team_really_cool.terminal_daily` AS
WITH flux AS (
  SELECT
    TX_ID,
    ANY_VALUE(TX_TS) AS TX_TS,
    ANY_VALUE(TERMINAL_ID) AS TERMINAL_ID,
    CAST(NULL AS INT64) AS TX_FRAUD
  FROM `team_really_cool.tx_history`
  WHERE TX_TS >= TIMESTAMP '2026-10-01'
  GROUP BY TX_ID
),
tx AS (
  SELECT TX_TS, TERMINAL_ID, TX_FRAUD
  FROM `fraudfinder.tx_seed`
  WHERE TX_TS >= TIMESTAMP '2026-09-10'
  UNION ALL
  SELECT TX_TS, TERMINAL_ID, TX_FRAUD
  FROM flux
)
SELECT
  TERMINAL_ID AS terminal_id,
  DATE(TX_TS) AS day,
  COUNT(*) AS n,
  COUNTIF(TX_FRAUD = 1) AS n_fraud
FROM tx
GROUP BY terminal_id, day;
