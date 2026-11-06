/*
 * Interface C du cœur partagé de Bergamote (core/src/ffi.rs).
 *
 * Chaînes en UTF-8. Une chaîne renvoyée par le cœur se libère avec bgm_string_free ; le tampon
 * de bgm_click_wav avec bgm_bytes_free. Les modificateurs sont des bits : 1 Maj, 2 Ctrl,
 * 4 Option/Alt, 8 Commande/Windows. Les camemberts : 1 conversion, 2 outils.
 */
#ifndef BERGAMOTE_CORE_H
#define BERGAMOTE_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct BgmDetector BgmDetector;

const char *bgm_core_version(void);
void bgm_string_free(char *text);

/* Geste */
BgmDetector *bgm_detector_new(void);
void bgm_detector_free(BgmDetector *detector);
void bgm_detector_clear_bindings(BgmDetector *detector);
bool bgm_detector_set_binding(BgmDetector *detector, uint32_t modifiers, uint8_t kind);
/* 0 rien, 1 ouvrir la conversion, 2 ouvrir les outils, 3 fermer. */
int32_t bgm_detector_update(BgmDetector *detector, bool is_mouse_down, int64_t drag_generation, uint32_t modifiers);
/* 0 aucun, 1 conversion, 2 outils. */
uint8_t bgm_detector_visible(const BgmDetector *detector);
void bgm_detector_dismiss(BgmDetector *detector);

/* Géométrie : repère centré sur le camembert, y vers le haut. -1 hors des parts. */
int32_t bgm_slice_at(double x, double y, int32_t count, double inner_radius, double outer_radius);
double bgm_center_angle(int32_t index, int32_t count);

/* Catalogue : requête et réponse JSON (voir ffi.rs). NULL si la requête est invalide. */
char *bgm_catalog(const char *request_json);
char *bgm_input_for_extension(const char *extension);

/* Nommage et textes */
char *bgm_unique_output_path(const char *source, const char *suffix, const char *extension, const char *output_dir);
char *bgm_created_summary(uint32_t count);
char *bgm_files_summary(const char *extensions_json, int64_t total_bytes);

/* Son du clic (WAV) */
uint8_t *bgm_click_wav(size_t *length);
void bgm_bytes_free(uint8_t *bytes, size_t length);

#ifdef __cplusplus
}
#endif

#endif
