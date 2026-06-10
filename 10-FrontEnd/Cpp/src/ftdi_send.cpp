//! \file ftdi_send.cpp
//! \brief Herramienta de test — manda bytes raw al FT232H sin imagen.
//! Uso: ftdi_send <b0> <b1> ... <bN>
//! Ejemplo: ftdi_send 0xCC 0x01 0x00 0x20

#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "ftd2xx.h"

int main(int argc, char* argv[])
{
    if (argc < 2) {
        printf("Uso: ftdi_send <b0> <b1> ... <bN>\n");
        printf("Ejemplo: ftdi_send 0xCC 0x01 0x00 0x20\n");
        return 1;
    }

    // ─── Construir array de bytes ─────────────────────────────────────────────
    int n = argc - 1;
    uint8_t* bytes = new uint8_t[n];
    printf("Enviando %d bytes:", n);
    for (int i = 0; i < n; i++) {
        bytes[i] = (uint8_t)strtoul(argv[i + 1], nullptr, 0);
        printf(" 0x%02X", bytes[i]);
    }
    printf("\n");

    // ─── Abrir FT232H ─────────────────────────────────────────────────────────
    FT_HANDLE handle;
    if (FT_Open(0, &handle) != FT_OK) {
        printf("Error abriendo FT232H\n");
        delete[] bytes;
        return 1;
    }
    FT_SetBitMode(handle, 0xFF, FT_BITMODE_SYNC_FIFO);
    FT_SetLatencyTimer(handle, 1);
    FT_SetUSBParameters(handle, 65536, 65536);
    FT_Purge(handle, FT_PURGE_RX | FT_PURGE_TX);

    // ─── Enviar ───────────────────────────────────────────────────────────────
    DWORD written = 0;
    FT_STATUS st = FT_Write(handle, bytes, (DWORD)n, &written);
    if (st == FT_OK && written == (DWORD)n)
        printf("[OK] %lu bytes enviados correctamente\n", (unsigned long)written);
    else
        printf("[ERR] Solo se enviaron %lu de %d bytes (st=%d)\n",
               (unsigned long)written, n, (int)st);

    FT_Close(handle);
    delete[] bytes;
    return (st == FT_OK && written == (DWORD)n) ? 0 : 1;
}
