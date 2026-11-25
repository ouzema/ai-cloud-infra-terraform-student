# Mesures séance 7 — groupe : team-really-cool

Région attribuée : `europe-west1` ; rôles pour cette étape (manipulation, mesure, analyse) : rôles
tournants de l'équipe (noms non consignés).

## Servir (étape 0)

| Mesure | Valeur |
| --- | --- |
| Démarrage à froid (première requête, jusqu'à la réponse) | 281 s (4 min 41 s, création Terraform ; la première requête a répondu en 1,06 s, à chaud) |
| Requête à chaud (même requête, renvoyée juste après) | 0,74 s |
| GPU lu dans la console | 1 × NVIDIA L4, sans redondance zonale |
| Instances au maximum lues dans la console | 1 |
| Concurrence lue dans la console | 16 |

## Une requête (étape 1)

Médiane de trois mesures par ligne, mesure à froid écartée.

| Prompt (tokens) | Sortie (tokens) | Premier token (ms) | Tokens/s | Durée totale (s) | Contrôle (s) : premier token (ms) ÷ 1 000 + sortie ÷ tokens/s |
| --- | --- | --- | --- | --- | --- |
| 200 | 50 | 152 | 51,8 | 1,10 | 1,12 |
| 200 | 200 | 152 | 51,4 | 4,03 | 4,04 |
| 1 500 | 50 | 564 | 50,7 | 1,54 | 1,55 |
| 1 500 | 200 | 576 | 50,4 | 4,53 | 4,54 |

Écart entre la durée mesurée et le contrôle : 0,3 % à 1,5 %.

Conclusion : ce qui allonge le délai avant le premier token est la **lecture du prompt** (152 ms à
200 tokens, 564–576 ms à 1 500) ; ce qui allonge la durée totale est la **génération de la sortie**
(50 tokens → ~1,1–1,5 s ; 200 tokens → ~4,0–4,5 s), à débit par requête presque constant (~51 tokens/s).

## Plusieurs requêtes (étape 2)

Prompt de 200 tokens, réponse de 200 tokens. Colonnes de `load.py`.

| concurrence | prompt (tokens) | sortie (tokens) | premier token médian (ms) | premier token max (ms) | tokens/s par requête | durée totale (s) | débit total (tokens/s) | erreurs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 209 | 200 | 159 | 159 | 51,8 | 4,00 | 50,0 | 0 |
| 4 | 208 | 200 | 259 | 357 | 39,2 | 5,36 | 149,4 | 0 |
| 8 | 209 | 200 | 583 | 710 | 24,8 | 8,64 | 185,3 | 0 |
| 16 | 209 | 200 | 1 253 | 1 444 | 26,1 | 8,92 | 358,8 | 0 |
| 32 | 209 | 200 | 5 532 | 10 167 | 25,4 | 17,66 | 362,5 | 0 |

Lecture faite pendant le palier à 8 (jamais à 16 : le `curl` serait la 17ᵉ requête d'un service à
concurrence 16 et attendrait). Créneaux occupés (`/slots`) : **8 / 16** ; `n_ctx` par créneau lu dans
`/slots` : **2 048 tokens** ; requêtes en attente (`/metrics`) : `requests_processing 8`,
`requests_deferred 0`.

Saturation : le débit total ne monte plus à partir de **16 requêtes simultanées**, à **358,8
tokens/s** (32 requêtes donnent 362,5 tokens/s, +1 %, pour un premier token qui passe de 1,3 s à
5,5–10,2 s).

Sort des requêtes au-delà de 16 (palier à 32) : elles attendent un créneau puis sont servies ;
**aucune erreur**, mais elles se répartissent en deux vagues (durées ~8,8 s et ~17,6 s) et le premier
token atteint 5,5 à 10,2 s.

## Tracer (étape 4)

Trace `315e8a2bfbbc95468fda3c2d09e317da`, `docs/seance-7/trace.png`.

| Étape du span | Durée (ms) | Tokens d'entrée | Tokens de sortie |
| --- | --- | --- | --- |
| `load_context` | 0,4 | - | - |
| `chat qwen2.5-7b-instruct-q4_k_m` | 1 629,5 | 584 | 73 |
| `validate_json` | 0,0 | - | - |

Étape la plus lente : **l'appel au modèle** (1 629,5 ms sur 1 630,1 ms de trace) ; le chargement du
contexte et la validation du JSON sont négligeables.

Coût d'une alerte, à partir de ses tokens : **0,0003577 $** (584 × 0,30 ÷ 10⁶ + 73 × 2,50 ÷ 10⁶).
L'hypothèse de l'étape 3 (800 entrée / 150 sortie) donnait 0,000615 $ : la mesure est **42 % plus
basse**. Cela change les nombres de l'étape 3 : coût API par jour **31,20 $** au lieu de 53,64 $, et
volume de bascule **70 218 alertes/jour** au lieu de 40 839. Le GPU reste moins cher au volume du fil
rouge (25,12 $/jour contre 31,20 $, soit ~19 % de moins), et un seul L4 suffit toujours
(151,4 tokens/s requis contre 358,8 mesurés).

## Juger un candidat (étape 5)

Règle écrite avant de lancer le jeu d'évaluation, à 2026-11-25 15:32 UTC :

- gain de score minimal exigé : **5 points** (5 champs sur 100)
- perte de débit tolérée : **30 %** (le 8 bits doit garder au moins 70 % du débit du 4 bits, soit
  ≥ 251 tokens/s)

| Modèle | Score (champs correctement extraits) | Débit (tokens/s) | Mémoire |
| --- | --- | --- | --- |
| 4 bits (notre service) | **87,0 %** (20 documents, 5 champs) | 358,8 (saturation, étape 2) | 5,96 Gio GPU (4,07 poids + 1,75 KV + 0,14 calcul) |
| 8 bits (service de l'enseignant) | **87,0 %** (mêmes 20 documents) | non mesuré par `load.py` ; sur `eval.py`, 65,7 s contre 27,6 s pour le 4 bits, soit ~42 % du débit, sous le seuil de 70 % | 8,89 Gio GPU (7,00 poids + 1,75 KV + 0,14 calcul) |

Décision, appliquée à la règle : **garder le 4 bits**. Le 8 bits n'apporte aucun point de score
(87,0 % = 87,0 %, gain 0 < 5), il est environ 2,4× plus lent sur le jeu d'évaluation (perte > 30 %) et
il consomme 49 % de mémoire GPU en plus. Les erreurs sont les mêmes des deux côtés : le champ `amount`
n'est correct qu'à 45 % (formats `strconv(...)` ou `None`), et `doc_type` à 90 % ; ce n'est pas un
effet de quantification, mais un problème de format dans l'extraction.
