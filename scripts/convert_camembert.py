#!/usr/bin/env python3
"""Convertit un encodeur de phrases CamemBERT en Core ML pour Bergamote.

À lancer sur la machine de développement uniquement : rien de tout ça n'est livré avec l'app.

    python3.12 -m venv .venv-convert
    .venv-convert/bin/pip install -r scripts/requirements-convert.txt
    .venv-convert/bin/python scripts/convert_camembert.py --out Models/sentence-camembert-base

Produit dans --out :
    Encoder.mlpackage        graphe Core ML, mean pooling et normalisation inclus (FP16 par défaut)
    tokenizer.json           vocabulaire SentencePiece, lu par UnigramTokenizer.swift
    bergamote-model.json     manifeste, lu par CoreMLSentenceEncoder.swift
    tokenizer_fixture.json   jeu de référence pour le test de parité du tokenizer

Le script vérifie la parité PyTorch / Core ML (cosinus >= 0,99) et échoue sinon.
"""

import argparse
import json
import pathlib
import shutil
import sys

import coremltools as ct
import numpy as np
import torch
from transformers import AutoModel, AutoTokenizer

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from tokenizer_fixture import write_fixture  # noqa: E402

PARITY_TEXTS = [
    "La facture d'électricité est à payer avant le 15 mars.",
    "Contrat de bail : le loyer est payable d'avance, charges en sus.",
    "Bulletin de salaire : net à payer après cotisations sociales.",
    "Le chat dort sur le canapé.",
]


class SentenceEncoder(torch.nn.Module):
    """CamemBERT + mean pooling + normalisation L2 : le modèle renvoie directement le vecteur de phrase."""

    def __init__(self, base: torch.nn.Module):
        super().__init__()
        self.base = base

    def forward(self, input_ids, attention_mask):
        hidden = self.base(input_ids=input_ids, attention_mask=attention_mask)[0]
        mask = attention_mask.unsqueeze(-1).to(hidden.dtype)
        pooled = (hidden * mask).sum(dim=1) / mask.sum(dim=1).clamp(min=1e-6)
        return torch.nn.functional.normalize(pooled, p=2, dim=-1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--model", default="dangvantuan/sentence-camembert-base",
                        help="modèle sentence-transformers basé sur CamemBERT (Hugging Face)")
    parser.add_argument("--out", type=pathlib.Path, required=True)
    parser.add_argument("--seq-len", type=int, default=256,
                        help="longueur fixe de séquence (le Neural Engine préfère les formes fixes)")
    parser.add_argument("--precision", choices=["fp16", "fp32"], default="fp16")
    parser.add_argument("--query-prefix", default="", help="ex. 'query: ' pour les modèles de type E5")
    parser.add_argument("--passage-prefix", default="", help="ex. 'passage: ' pour les modèles de type E5")
    args = parser.parse_args()
    out: pathlib.Path = args.out
    out.mkdir(parents=True, exist_ok=True)

    tokenizer = AutoTokenizer.from_pretrained(args.model, use_fast=True)
    encoder = SentenceEncoder(AutoModel.from_pretrained(args.model, torchscript=True).eval()).eval()

    def encode(text: str):
        return tokenizer(text, padding="max_length", truncation=True, max_length=args.seq_len, return_tensors="pt")

    example = encode(PARITY_TEXTS[0])
    with torch.no_grad():
        traced = torch.jit.trace(encoder, (example["input_ids"], example["attention_mask"]))

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, args.seq_len), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, args.seq_len), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="embedding", dtype=np.float32)],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16 if args.precision == "fp16" else ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.macOS14,
    )
    mlmodel.short_description = f"Bergamote sentence encoder ({args.model})"
    package = out / "Encoder.mlpackage"
    if package.exists():
        shutil.rmtree(package)
    mlmodel.save(str(package))

    worst, dimension = 1.0, 0
    for text in PARITY_TEXTS:
        inputs = encode(text)
        with torch.no_grad():
            reference = encoder(inputs["input_ids"], inputs["attention_mask"]).numpy()[0]
        predicted = mlmodel.predict({
            "input_ids": inputs["input_ids"].numpy().astype(np.int32),
            "attention_mask": inputs["attention_mask"].numpy().astype(np.int32),
        })["embedding"].reshape(-1)
        dimension = predicted.shape[-1]
        cosine = float(np.dot(reference, predicted) / (np.linalg.norm(reference) * np.linalg.norm(predicted)))
        worst = min(worst, cosine)
    print(f"Parité PyTorch / Core ML ({args.precision}) : cosinus minimal = {worst:.5f}")
    if worst < 0.99:
        sys.exit("Écart trop important entre PyTorch et Core ML : essayer --precision fp32.")

    tokenizer.backend_tokenizer.save(str(out / "tokenizer.json"))
    manifest = {
        "modelID": args.model,
        "dimension": int(dimension),
        "sequenceLength": args.seq_len,
        "queryPrefix": args.query_prefix,
        "passagePrefix": args.passage_prefix,
        "outputName": "embedding",
    }
    (out / "bergamote-model.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    write_fixture(out)
    print(f"Modèle prêt : {out}")


if __name__ == "__main__":
    main()
