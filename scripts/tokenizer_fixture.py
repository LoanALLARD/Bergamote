#!/usr/bin/env python3
"""Produit `tokenizer_fixture.json` : identifiants de référence calculés par 🤗 tokenizers.

Le test Swift `matchesHuggingFaceOnCamembertVocabulary` compare UnigramTokenizer à ces valeurs.

Usage :
    python3 -m venv .venv-tok && .venv-tok/bin/pip install tokenizers
    .venv-tok/bin/python scripts/tokenizer_fixture.py Models/sentence-camembert-base
    BERGAMOTE_TOKENIZER_DIR=Models/sentence-camembert-base swift test --filter Tokenizer
"""

import json
import pathlib
import sys

MAX_LENGTH = 256

SAMPLES = [
    "Bonjour, voici la facture d'électricité de février.",
    "FACTURE N° 2025-118 – Total TTC : 1 234,56 € (TVA 20 %)",
    "L’échéance est fixée au 15 mars 2025 ; merci de régler par virement.",
    "IBAN : FR76 3000 6000 0112 3456 7890 189 — BIC : AGRIFRPP",
    "Contrat de bail d'habitation : le locataire s'engage à payer le loyer.",
    "Œuvre, cœur, sœur : ligatures et « guillemets » français.",
    "Le bénéficiaire reçoit 3 500 euros nets après cotisations.",
    "Contact : facturation@volt-fils.fr ou 04 72 00 11 22.",
    "Plusieurs   espaces\tet\nretours à la ligne.",
    "Fichier ﬁnal : ½ page, 2ᵉ étage, ＡＢＣ pleine chasse.",
    "Émoji 📄 et caractères rares : ğ, ß, ø, 漢字.",
    "attestation d'assurance habitation pour l'année 2026",
    "Madame, Monsieur, veuillez agréer l'expression de nos salutations distinguées.",
    "",
]


def write_fixture(directory: pathlib.Path) -> pathlib.Path:
    from tokenizers import Tokenizer

    tokenizer = Tokenizer.from_file(str(directory / "tokenizer.json"))
    tokenizer.enable_truncation(max_length=MAX_LENGTH)
    fixture = [{"text": text, "ids": tokenizer.encode(text).ids} for text in SAMPLES]
    path = directory / "tokenizer_fixture.json"
    path.write_text(json.dumps(fixture, ensure_ascii=False, indent=1), encoding="utf-8")
    return path


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    print(write_fixture(pathlib.Path(sys.argv[1])))
