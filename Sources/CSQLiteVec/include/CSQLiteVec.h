#ifndef CSQLITEVEC_H
#define CSQLITEVEC_H

/// Enregistre les fonctions vec_* et la table virtuelle vec0 sur une connexion SQLite.
/// `db` est le `sqlite3 *` de la connexion (OpaquePointer côté Swift). Retourne un code SQLite.
int bgm_sqlite_vec_register(void *db);

/// Version de sqlite-vec intégrée au binaire (ex. "v0.1.9").
const char *bgm_sqlite_vec_version(void);

#endif
