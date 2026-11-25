# Fiche de dimensionnement du LLM du fil rouge — groupe : team-really-cool

## Usage et volume (étapes 3 et 4)

Alertes par jour : **87 216** ; tokens d'entrée par alerte : **584** ; tokens de sortie par alerte :
**73** (mesurés dans la trace `315e8a2bfbbc95468fda3c2d09e317da`, `docs/seance-7/trace.png`).

## Modèle et précision (étape 5)

Modèle retenu : **Qwen2.5-7B-Instruct en 4 bits (Q4_K_M)**. Score qui le justifie : **87,0 %** des
champs corrects sur 20 documents KYC, contre **87,0 %** pour le 8 bits de l'enseignant. Règle écrite
avant l'évaluation (25/11 à 15:32 UTC) : gain de score ≥ 5 points et perte de débit ≤ 30 %. Le 8 bits
n'apporte aucun point, est ~2,4× plus lent sur le jeu d'évaluation (65,7 s contre 27,6 s) et consomme
8,89 Gio de GPU contre 5,96 Gio : le 4 bits est retenu.

## Performance (étapes 0, 1 et 2)

Démarrage à froid : **281 s** (4 min 41 s, création Terraform ; première requête à chaud 1,06 s).
Délai avant le premier token (prompt de 200 tokens) : **152 ms** ; à 1 500 tokens : **564–576 ms**.
Débit à saturation : **358,8 tokens/s** à **16 requêtes simultanées** (32 requêtes : 362,5 tokens/s,
+1 %, mais premier token à 5,5–10,2 s).

## Lieu de service et coût (étape 3)

Choix : **GPU** (L4 Cloud Run, 1,0465 $/h). Coût par jour de l'API : **31,20 $** avec les tokens
mesurés (53,64 $ avec l'hypothèse 800/150) ; du GPU : **25,12 $**. Volume de bascule : **70 218
alertes/jour** (mesuré) ; 40 839 avec l'hypothèse.

Débit de sortie requis (87 216 × 150 ÷ 86 400) : **151,4 tokens/s**, contre un débit total mesuré à
l'étape 2 de **358,8 tokens/s**. Le GPU ne gagne sur le coût que si un seul L4 tient ce débit :
**oui**, avec une marge d'environ 2,4×. Le GPU reste moins cher que l'API d'environ 19 % au volume du
fil rouge.

## Trois nombres à surveiller (étapes 2 et 4)

1. **Premier token (TTFT)**, seuil : **< 1 500 ms** au palier de 16 requêtes (mesuré 1 253 ms ;
   5 532 ms à 32).
2. **Requêtes en attente** (`requests_deferred` / `requests_processing`), seuil : **deferred > 0**
   durablement, ou plus de **16** requêtes en cours (le service n'a qu'un L4 et 16 créneaux).
3. **Tokens par alerte** (entrée + sortie), seuil : **> 1 000 tokens** par alerte, ce qui augmente
   le coût API et le prefill ; surveiller aussi le coût par million de tokens à 100 % (0,81 $) et à
   20 % d'occupation (4,05 $).
