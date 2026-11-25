# Coût séance 7 — groupe : team-really-cool

Prix relevés le 25/11/2026.

## Prix relevés

| Prix | Valeur | Source et date |
| --- | --- | --- |
| Prix horaire du GPU (L4 sur Cloud Run, `europe-west1`) | 1,0465 $ / h | Cloud Run pricing : GPU L4 non-zonal 0,0001867 $/s + 4 vCPU × 0,000018 $/s + 16 GiB × 0,000002 $/s, soit 0,0002907 $/s × 3 600. Relevé le 25/11/2026 |
| Prix d'entrée de l'API (`gemini-3.5-flash-lite`, global) | 0,30 $ par million de tokens | Vertex AI / Gemini pricing, relevé le 25/11/2026 |
| Prix de sortie de l'API | 2,50 $ par million de tokens | idem |

## Hypothèses du fil rouge

| Hypothèse | Valeur |
| --- | --- |
| Alertes par jour | 87 216 (voir ci-dessous) |
| Tokens d'entrée par alerte | 800 |
| Tokens de sortie par alerte | 150 |
| Débit total à saturation (étape 2) | 358,8 tokens/s (palier à 16 requêtes) |

Volume d'alertes : séance 6, 7 268 alertes sur les 72 000 premiers messages du rejeu, soit 10,09 %
(mesuré, seuil 0,0012). À 10 transactions par seconde, une journée compte 864 000 transactions :
864 000 × 7 268 ÷ 72 000 = 87 216 alertes par jour (dérivé ; hypothèse : le taux du 1er octobre tient
toute la journée). Les 800 tokens d'entrée et 150 tokens de sortie par alerte restent l'hypothèse de
départ, à corriger avec la mesure de l'étape 4.

## Formules

```text
coût par million de tokens = prix horaire ÷ (tokens par seconde × 3 600 × taux d'occupation) × 1 000 000
coût API par jour          = alertes × (tokens d'entrée × prix d'entrée + tokens de sortie × prix de sortie) ÷ 1 000 000
coût GPU par jour          = prix horaire × 24
volume de bascule          = coût GPU par jour ÷ coût API d'une alerte
débit moyen nécessaire     = alertes × tokens de sortie ÷ 86 400
```

## Les nombres de la preuve (étape 3)

| Nombre | Valeur |
| --- | --- |
| Coût par million de tokens à 100 % d'occupation | 0,81 $ |
| Coût par million de tokens à 20 % d'occupation | 4,05 $ |
| Coût par jour, API | 53,64 $ |
| Coût par jour, GPU | 25,12 $ |
| Volume de bascule | 40 839 alertes par jour |
| Coût API d'une alerte (formule de la ligne « volume de bascule ») | 0,000615 $ |
| Coût GPU par million de tokens de sortie, à comparer au prix de sortie de l'API (mêmes unités : $ par million de tokens) | 0,81 $ contre 2,50 $ (à 100 % ; 4,05 $ à 20 %) |

## Vérification de capacité

| Mesure | Valeur |
| --- | --- |
| Débit de sortie requis (alertes par jour × 150 ÷ 86 400) | 151,4 tokens/s |
| Débit total mesuré à l'étape 2 | 358,8 tokens/s |
| Un seul L4 suffit au volume ? | **oui** : 151,4 < 358,8, avec une marge d'environ 2,4× |

Le GPU ne gagne sur le coût que si un seul L4 tient ce débit : c'est le cas ici. Attention : le débit
de 358,8 tokens/s a été mesuré avec des prompts de 200 tokens ; une alerte en compte 800, ce qui
ajoute du prefill et réduit la marge. La conclusion reste vraie avec 2,4× de marge, mais elle serait à
revérifier si les prompts dépassaient ~1 500 tokens.

## Décision

Au volume du fil rouge (87 216 alertes/jour), le GPU coûte **25,12 $/jour** contre **53,64 $/jour**
pour l'API Gemini 3.5 Flash-Lite, soit environ **2,1× moins cher**. Le volume de bascule
(40 839 alertes/jour) est **en dessous** du volume du fil rouge, et un seul L4 tient le débit moyen
requis (151,4 tokens/s contre 358,8 mesurés). **Le GPU est donc le choix le moins cher à ce volume**,
à condition que le modèle 4 bits soit assez précis pour la tâche — c'est ce que vérifie l'étape 5.

## Correction après la trace (étape 4)

La trace `315e8a2bfbbc95468fda3c2d09e317da` mesure **584 tokens d'entrée et 73 tokens de sortie** par
alerte, au lieu de l'hypothèse 800 / 150.

- coût API d'une alerte : 584 × 0,30 ÷ 10⁶ + 73 × 2,50 ÷ 10⁶ = **0,0003577 $** ;
- coût API par jour : 87 216 × 0,0003577 = **31,20 $** ;
- volume de bascule : 25,12 ÷ 0,0003577 = **70 218 alertes/jour** ;
- débit de sortie requis : 87 216 × 150 ÷ 86 400 = **151,4 tokens/s**, toujours sous les 358,8
  tokens/s mesurés.

La décision ne change pas : à 87 216 alertes/jour, le GPU (25,12 $/jour) reste moins cher que l'API
(31,20 $/jour), d'environ 19 %, et un seul L4 tient le débit requis. La marge est plus faible que
celle calculée avec l'hypothèse 800 / 150 ; elle dépend surtout du nombre d'alertes par jour.
