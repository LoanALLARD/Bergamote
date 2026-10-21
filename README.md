# Bergamote

GED sémantique 100 % locale pour macOS : on dépose des documents (PDF, scans, images, Word),
ils deviennent cherchables par mots et par sens, avec extraction d'entités et classement
automatique. Aucune donnée ne quitte le Mac, et la sandbox interdit tout accès réseau.

Squelette de POC : SwiftUI, Vision, PDFKit, Core ML, GRDB + sqlite-vec.

## Démarrer

Prérequis : macOS 14+, Xcode 16+ (développé avec Xcode 26.5 / Swift 6.3).

```bash
swift test                 # tests unitaires et pipeline de bout en bout
swift run Bergamote        # lance l'app (hors sandbox, pratique en développement)
scripts/make-app.sh        # build/Bergamote.app : release, sandbox sans réseau, signature ad hoc
```

On peut aussi ouvrir `Package.swift` dans Xcode et lancer le schéma `Bergamote`.

### Corpus d'essai et rendus de l'interface

```bash
swift scripts/make-samples.swift SampleDocs   # 7 documents fictifs : PDF, scan, image, .docx, .txt
BERGAMOTE_SAMPLES_DIR=SampleDocs BERGAMOTE_SNAPSHOT_DIR=build/snapshots swift test
open -a build/Bergamote.app SampleDocs/*      # « Ouvrir avec » sur l'app sandboxée
```

- `SampleCorpusTests` mesure le classement (au moins 6 sur 7), le premier résultat de 8 requêtes et la
  propreté des entités.
- `SnapshotTests` rend la bibliothèque, les résultats, la palette ⌘K et la barre des menus dans des
  fenêtres hors écran. Il vérifie aussi le surlignage dans PDFView et rend les pages surlignées en PNG.
  Les zones en verre (barre latérale, champ de recherche) et l'aperçu PDF sortent blancs dans ce mode
  de rendu : c'est une limite de la capture, pas de l'app.
- Pour suivre l'indexation de l'app :
  `/usr/bin/log stream --predicate 'subsystem == "com.example.bergamote"'`.

## Architecture

```
Sources/
  CSQLiteVec/              sqlite-vec 0.1.9 compilé dans le binaire (pas de dylib à charger)
  BergamoteKit/            tout le métier, sans UI, testable
    Database/              AppDatabase (migrations, index vec0), enregistrements GRDB
    Library/               bibliothèque adressée par SHA-256, import de fichiers et dossiers
    Pipeline/              JobQueue (file persistante avec bail), PipelineRunner, DocumentIndexer, IndexingPolicy
    Extraction/            PDFKit (couche texte + positions), Vision (OCR), NSAttributedString (.docx/.odt/.rtf)
    Text/                  Chunker (passages ≤ 1 100 caractères, par page), FrenchNormalizer (lemmes pour FTS5)
    NLP/                   EmbeddingProvider, CoreMLSentenceEncoder, UnigramTokenizer, EntityExtractor, DocTypeClassifier
    Search/                recherche hybride BM25 + KNN fusionnés par RRF, documents similaires
    BergamoteEngine.swift  assemblage et API pour l'UI
  Bergamote/               app SwiftUI : bibliothèque, aperçu PDF surligné, palette ⌘K, dépôt dans la barre des menus
scripts/
  convert_camembert.py     CamemBERT → Core ML (+ tokenizer, manifeste, jeu de parité)
  tokenizer_fixture.py     jeu de référence 🤗 tokenizers pour le test de parité
  make-app.sh              assemblage et signature du .app
Packaging/                 Info.plist, entitlements (sandbox, lecture des fichiers choisis, aucun réseau)
```

### Pipeline en deux phases

1. **extract** (2 workers, QoS utility) : texte natif ou OCR Vision, découpage, index FTS5.
   Le document est **cherchable par mots en quelques secondes**.
2. **enrich** (1 worker, QoS background, mis en pause en mode économie d'énergie ou si le Mac chauffe) :
   embeddings, entités, type de document. La recherche sémantique rattrape son retard en arrière-plan.

Les jobs vivent dans la table `job` : un worker pose un bail, un crash le libère, un échec est
rejoué avec backoff exponentiel, puis le document passe en `failed` (bouton « Réessayer »).

### Un seul fichier SQLite

`~/Library/Application Support/Bergamote/index.sqlite` (dans le conteneur de l'app quand elle est
sandboxée) contient métadonnées, `chunk_fts` (FTS5), `chunk_vec` (vec0) et la file de jobs.
Si le modèle d'embedding change, `chunk_vec` est recréée et les documents sont ré-embeddés en fond,
pendant que la recherche lexicale continue de fonctionner.

## Modèles

| Rôle | Par défaut (aucun téléchargement) | Avec CamemBERT |
|---|---|---|
| Recherche | par mots : BM25 sur texte lemmatisé | hybride : mots + sens (KNN), fusion RRF |
| Vecteurs | `HashingEmbedder` (sac de lemmes, lexical) | `CoreMLSentenceEncoder` |
| Entités | NER NaturalLanguage filtrée + règles validées (IBAN mod 97, SIRET/SIREN Luhn, dates, montants) | idem, NER CamemBERT à brancher |
| Type de document | prototypes par mots-clés (zero-shot puis apprentissage local) | prototypes sémantiques |

Pourquoi pas les embeddings de phrases de macOS (`NLEmbedding.sentenceEmbedding(for: .french)`) ?
Mesurés sur le corpus d'essai, ils placent le bon document en tête pour 1 requête sur 7 seulement,
et ce avec ou sans moyenne par phrase ou recentrage des vecteurs. Ils mesurent le style du texte
plus que son sens, donc ils dégradaient la recherche au lieu de l'aider.

Limite connue du mode par mots : « montant total à payer pour l'électricité » renvoie le bulletin de
paie (« net à payer ») avant la facture. Le test du corpus la signale comme problème connu, et
avertira dès qu'un modèle sémantique la corrige.

Le classement réutilise le vecteur de recherche, sans deuxième passe d'encodeur. Chaque type
validé dans l'inspecteur devient un exemple, et le prototype est recalculé immédiatement.
L'application automatique exige une confiance ≥ 90 % **et** au moins 3 exemples validés pour
la classe. Avant ça, le modèle ne fait que suggérer.

### Installer CamemBERT en Core ML

```bash
python3.12 -m venv .venv-convert
.venv-convert/bin/pip install -r scripts/requirements-convert.txt
.venv-convert/bin/python scripts/convert_camembert.py --out Models/sentence-camembert-base
BERGAMOTE_MODELS_DIR=Models swift run Bergamote
```

- Le script télécharge `dangvantuan/sentence-camembert-base` (Apache-2.0, environ 440 Mo) et
  produit un graphe FP16 de longueur fixe 256, avec le mean pooling inclus. Il refuse le résultat
  si la parité PyTorch / Core ML descend sous 0,99 en cosinus.
- `scripts/make-app.sh` copie `Models/` dans le bundle. L'app prend le premier modèle trouvé.
- Le tokenizer est implémenté en Swift (`UnigramTokenizer`), sans dépendance ni code réseau.
  Pour vérifier sa parité avec 🤗 tokenizers sur un modèle :
  `BERGAMOTE_TOKENIZER_DIR=Models/sentence-camembert-base swift test --filter Tokenizer`.
  Sur le vocabulaire de sentence-camembert-base, les 14 phrases de référence (ligatures,
  pleine chasse, émoji, espaces multiples) donnent des identifiants identiques.
- Attention : `swift-transformers` ne connaît pas `CamembertTokenizer` et retombe sur un
  tokenizer BPE, ce qui donne des identifiants faux. C'est la raison du tokenizer maison.

## État et prochaines étapes

**Vérifié :**
- compilation en Swift 6 strict, sans avertissement ;
- 27 tests verts, dont le corpus d'essai et les rendus hors écran ;
- `.app` sandboxé sans droit réseau, lancé pour de vrai : 7 documents importés via « Ouvrir avec »,
  cherchables en moins de 0,6 s (scans OCR compris) et analysés en 2,5 s au total.

**Pas encore vérifié :**
- les interactions à la souris et au clavier dans l'app réelle (glisser-déposer, ⌘K) n'ont pas été rejouées ;
  seuls leurs rendus et la logique derrière ont été testés ;
- la conversion Core ML n'a pas été lancée : le chemin `CoreMLSentenceEncoder` compile, mais n'a pas tourné sur un vrai modèle.

**À faire pour passer du POC au produit :**
1. **Extraction dans un service XPC.** Aujourd'hui, un timeout rend la main mais laisse tourner
   un PDFKit bloqué. Un XPC permettrait de tuer le process et d'isoler les crashs.
2. **NER CamemBERT en Core ML** (classification de tokens, par exemple `Jean-Baptiste/camembert-ner-with-dates`),
   en complément des règles validées.
3. **Dossiers surveillés** : FSEvents + bookmarks à portée de sécurité (l'entitlement est déjà présent).
4. **Chiffrement de l'index** : GRDB + SQLCipher demande un SQLite personnalisé, et sqlite-vec doit
   alors être compilé contre ses en-têtes.
5. **Filtrer pendant le KNN** avec les colonnes de métadonnées de vec0 (type, date) plutôt qu'après la fusion.
6. **Couche texte pour les scans** (comme OCRmyPDF) : les mots de la requête pourraient alors y être
   surlignés, au lieu du cadre autour de la zone reconnue.
7. **Intégration système** : Core Spotlight, Quick Look, icône. Sur macOS 26, FoundationModels pour
   extraire des champs structurés (`@Generable`).
8. **Bundle identifier :** remplacer `com.example.bergamote` (Info.plist, Logger) par le vôtre.
