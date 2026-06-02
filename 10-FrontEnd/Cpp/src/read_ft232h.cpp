//! \file vicon_read.cpp
//! \brief Lector básico del FT232H para validación del pipeline VICON.
//!
//! Busca el marcador de frame (AA 55 AA 55), lee H*W bytes y muestra
//! la primera fila en hex para verificar el patrón.

#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include "ftd2xx.h"

// ─── Configuración ────────────────────────────────────────────────────────────
static const int    H           = 200;       // filas
static const int    W           = 250;       // columnas
static const int    FRAME_BYTES = H * W;
static const uint8_t MARKER[4] = {0xAA, 0x55, 0xAA, 0x55};
static const int    BUF_SIZE    = 65536;

// ─── Búsqueda de marcador ────────────────────────────────────────────────────
static int find_marker(const uint8_t* buf, int len)
{
    for (int i = 0; i <= len - 4; i++) {
        if (buf[i]   == MARKER[0] && buf[i+1] == MARKER[1] &&
            buf[i+2] == MARKER[2] && buf[i+3] == MARKER[3])
            return i;
    }
    return -1;
}

int main(void)
{
    FT_HANDLE  handle;
    FT_STATUS  status;
    DWORD      bytes_read;

    // ─── Abrir dispositivo ───────────────────────────────────────────────────
    status = FT_Open(0, &handle);
    if (status != FT_OK) {
        printf("Error abriendo FT232H: %d\n", (int)status);
        return 1;
    }

    // ─── Configurar modo Synchronous FIFO ───────────────────────────────────
    FT_SetBitMode(handle, 0xFF, FT_BITMODE_SYNC_FIFO);
    FT_SetLatencyTimer(handle, 1);
    FT_SetUSBParameters(handle, 65536, 65536);
    FT_Purge(handle, FT_PURGE_RX | FT_PURGE_TX);

    printf("FT232H listo. Leyendo frames %dx%d...\n", W, H);
    printf("Ctrl+C para parar\n\n");

    // ─── Alta prioridad ──────────────────────────────────────────────────────
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);

    // ─── Buffer de trabajo ───────────────────────────────────────────────────
    uint8_t  raw[BUF_SIZE];
    uint8_t  accum[BUF_SIZE * 4];   // buffer acumulador
    int      accum_len  = 0;

    int      frame_num  = 0;
    int      ok_count   = 0;
    int      fail_count = 0;

    // ─── Sincronizar: buscar 2 marcadores consecutivos ───────────────────────
    printf("Sincronizando...\n");
    int synced = 0;
    while (synced < 2) {
        FT_Read(handle, raw, BUF_SIZE, &bytes_read);
        memcpy(accum + accum_len, raw, bytes_read);
        accum_len += bytes_read;

        int idx = find_marker(accum, accum_len);
        if (idx >= 0) {
            accum_len -= idx + 4;
            memmove(accum, accum + idx + 4, accum_len);
            synced++;
        }
    }
    printf("Sincronizado. Leyendo frames...\n\n");

    // ─── Bucle principal ─────────────────────────────────────────────────────
    while (1) {

        // Leer hasta tener un frame completo
        LARGE_INTEGER freq, t0, t1;
        QueryPerformanceFrequency(&freq);
        QueryPerformanceCounter(&t0);

        while (accum_len < FRAME_BYTES) {
            FT_Read(handle, raw, BUF_SIZE, &bytes_read);
            if (bytes_read > 0) {
                memcpy(accum + accum_len, raw, bytes_read);
                accum_len += bytes_read;
            }
        }

        QueryPerformanceCounter(&t1);
        double t_ms  = (double)(t1.QuadPart - t0.QuadPart) / freq.QuadPart * 1000.0;
        double mbps  = (FRAME_BYTES / 1e6) / (t_ms / 1000.0);

        // Extraer frame
        uint8_t frame[FRAME_BYTES];
        memcpy(frame, accum, FRAME_BYTES);
        accum_len -= FRAME_BYTES;
        memmove(accum, accum + FRAME_BYTES, accum_len);

        // Validar primera fila
        int ok = 1;
        for (int col = 0; col < W; col++) {
            uint8_t expected = (uint8_t)(col % 256);
            // Aplicar sustituciones
            if (expected == 0xAA) expected = 0xAB;
            else if (expected == 0x55) expected = 0x56;
            else if (expected == 0xFF) expected = 0xFE;
            if (frame[col] != expected) {
                ok = 0;
                break;
            }
        }

        if (ok) {
            ok_count++;
            printf("\rFrame %5d OK   (%.2f ms, %.2f MB/s)  ok=%d fail=%d   ",
                   frame_num, t_ms, mbps, ok_count, fail_count);
            fflush(stdout);
        } else {
            fail_count++;
            printf("\nFrame %5d FAIL (%.2f ms, %.2f MB/s)\n",
                   frame_num, t_ms, mbps);
            // Mostrar primera fila recibida vs esperada
            printf("  Recibido: ");
            for (int i = 0; i < 16; i++) printf("%02X ", frame[i]);
            printf("...\n");
        }

        frame_num++;

        // Buscar siguiente marcador
        int idx = find_marker(accum, accum_len);
        if (idx >= 0) {
            accum_len -= idx + 4;
            memmove(accum, accum + idx + 4, accum_len);
        } else {
            // No hay marcador en el buffer — leer hasta encontrarlo
            while (1) {
                FT_Read(handle, raw, BUF_SIZE, &bytes_read);
                if (bytes_read > 0) {
                    memcpy(accum + accum_len, raw, bytes_read);
                    accum_len += bytes_read;
                    idx = find_marker(accum, accum_len);
                    if (idx >= 0) {
                        accum_len -= idx + 4;
                        memmove(accum, accum + idx + 4, accum_len);
                        break;
                    }
                }
            }
        }
    }

    FT_Close(handle);
    return 0;
}
