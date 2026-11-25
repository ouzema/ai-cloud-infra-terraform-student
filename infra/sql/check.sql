-- Contrôle de la partie B : nos compteurs du 10 au 30 septembre comparés aux tables
-- de référence du socle. Attendu : 0 et 0.

SELECT 'client' AS compteurs, COUNT(*) AS lignes_differentes FROM (
  SELECT customer_id, day, n, ROUND(amount_sum, 2) AS amount_sum
  FROM `team_really_cool.customer_daily`
  WHERE day <= '2026-09-30'
  EXCEPT DISTINCT
  SELECT customer_id, day, n, ROUND(amount_sum, 2) AS amount_sum
  FROM `fraudfinder.ref_customer_daily`
)
UNION ALL
SELECT 'terminal', COUNT(*) FROM (
  SELECT terminal_id, day, n, n_fraud
  FROM `team_really_cool.terminal_daily`
  WHERE day <= '2026-09-30'
  EXCEPT DISTINCT
  SELECT terminal_id, day, n, n_fraud
  FROM `fraudfinder.ref_terminal_daily`
);
