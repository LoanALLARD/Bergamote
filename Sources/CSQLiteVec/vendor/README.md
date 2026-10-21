# sqlite-vec (vendorisé)

- Projet : https://github.com/asg017/sqlite-vec
- Version : v0.1.9 (release stable du 2026-03-31)
- Archive : `sqlite-vec-0.1.9-amalgamation.tar.gz`
- SHA-256 de l'archive : `3acd67cb4aff080c7050926fd3cf8227905fe5b7ee3829d8ee5024ab1283cf61`
- Licence : MIT ou Apache-2.0, au choix

Les fichiers `sqlite-vec.c` et `sqlite-vec.h` sont recopiés tels quels. Ils ne sont pas compilés
directement : `../csqlitevec.c` les inclut avec `SQLITE_CORE` (et NEON sur arm64).

Pour mettre à jour : télécharger l'amalgamation de la nouvelle release, remplacer les deux fichiers,
mettre à jour ce README, puis relancer `swift test`.
