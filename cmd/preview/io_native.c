#include <moonbit.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

MOONBIT_FFI_EXPORT FILE *moonleaf_preview_fopen(moonbit_bytes_t path,
                                              moonbit_bytes_t mode) {
  return fopen((const char *)path, (const char *)mode);
}

MOONBIT_FFI_EXPORT int32_t moonleaf_preview_file_is_null(FILE *file) {
  return file == NULL;
}

MOONBIT_FFI_EXPORT int32_t moonleaf_preview_fileno(FILE *file) {
  return fileno(file);
}

MOONBIT_FFI_EXPORT int32_t moonleaf_preview_fclose(FILE *file) {
  return fclose(file);
}
