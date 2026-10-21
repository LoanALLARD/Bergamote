// Unité de compilation unique pour sqlite-vec.
//
// On l'intègre au binaire (SQLITE_CORE) au lieu de le charger comme extension :
// pas de dylib à signer ni à charger dynamiquement, ce qui reste compatible avec
// le hardened runtime et la sandbox. L'enregistrement se fait connexion par connexion
// (voir AppDatabase.configuration()).
#define SQLITE_CORE 1
#define SQLITE_VEC_STATIC 1
#define SQLITE_VEC_OMIT_FS 1
#if defined(__aarch64__)
#define SQLITE_VEC_ENABLE_NEON 1
#endif

#include "vendor/sqlite-vec.c"
#include "CSQLiteVec.h"

int bgm_sqlite_vec_register(void *db) {
    char *error = NULL;
    int rc = sqlite3_vec_init((sqlite3 *)db, &error, NULL);
    if (error != NULL) {
        sqlite3_free(error);
    }
    return rc;
}

const char *bgm_sqlite_vec_version(void) {
    return SQLITE_VEC_VERSION;
}
