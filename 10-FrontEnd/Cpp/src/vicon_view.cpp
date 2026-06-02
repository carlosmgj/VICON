//! \file vicon_view.cpp
//! \brief Visor de imagen VICON en tiempo real usando SDL3 + FT232H.
//! Escala la imagen al tamaño de pantalla manteniendo proporciones.

#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "ftd2xx.h"
#include <SDL3/SDL.h>
#include <string>

// ─── Configuración ────────────────────────────────────────────────────────────
static const int     H           = 480;
static const int     W           = 640;
static const int     FRAME_BYTES = H * W;
static const uint8_t MARKER[4]  = {0xAA, 0x55, 0xAA, 0x55};
static const int     BUF_SIZE    = 65536;
static const int     WIN_W       = 1020;   // 255 * 4
static const int     WIN_H       = 800;    // 200 * 4

// ─── Búsqueda de marcador ─────────────────────────────────────────────────────
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
    printf("Hola mundo \n");

    // ─── Inicializar SDL3 ─────────────────────────────────────────────────────
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        printf("SDL_Init error: %s\n", SDL_GetError());
        return 1;
    }

    SDL_Window*   window = SDL_CreateWindow("VICON cam_sim", WIN_W, WIN_H, 0);
    SDL_Renderer* renderer = SDL_CreateRenderer(window, NULL);
    SDL_Texture*  texture = SDL_CreateTexture(renderer,
                                SDL_PIXELFORMAT_RGB24,
                                SDL_TEXTUREACCESS_STREAMING,
                                W, H);
    if (!window || !renderer || !texture) {
        printf("SDL error: %s\n", SDL_GetError());
        return 1;
    }

    // ─── Abrir FT232H ─────────────────────────────────────────────────────────
    FT_HANDLE handle;
    if (FT_Open(0, &handle) != FT_OK) {
        printf("Error abriendo FT232H\n");
        return 1;
    }
    FT_SetBitMode(handle, 0xFF, FT_BITMODE_SYNC_FIFO);
    FT_SetLatencyTimer(handle, 1);
    FT_SetUSBParameters(handle, 65536, 65536);
    FT_Purge(handle, FT_PURGE_RX | FT_PURGE_TX);
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);

    printf("FT232H listo. Mostrando %dx%d escalado a %dx%d\n", W, H, WIN_W, WIN_H);

    // ─── Buffer de trabajo ────────────────────────────────────────────────────
    uint8_t raw[BUF_SIZE];
    uint8_t accum[BUF_SIZE * 4];
    int     accum_len = 0;
    uint8_t frame[FRAME_BYTES];
    uint8_t rgb[W * H * 3];   // imagen RGB para SDL
    DWORD   bytes_read;

    // ─── Sincronizar ─────────────────────────────────────────────────────────
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
    printf("Sincronizado.\n");

    // ─── Bucle principal ──────────────────────────────────────────────────────
    int      frame_num = 0;
    bool running = true;
    SDL_Event event;

    while (running) {
        // Eventos SDL
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT)
                running = false;
            if (event.type == SDL_EVENT_KEY_DOWN &&
                event.key.key == SDLK_ESCAPE)
                running = false;
        }

        // Leer frame completo
        while (accum_len < FRAME_BYTES) {
            FT_Read(handle, raw, BUF_SIZE, &bytes_read);
            if (bytes_read > 0) {
                memcpy(accum + accum_len, raw, bytes_read);
                accum_len += bytes_read;
            }
        }

        memcpy(frame, accum, FRAME_BYTES);
        accum_len -= FRAME_BYTES;
        memmove(accum, accum + FRAME_BYTES, accum_len);

        // Convertir Y (grayscale) → RGB para SDL
        for (int i = 0; i < FRAME_BYTES; i++) {
            rgb[i * 3 + 0] = frame[i];  // R
            rgb[i * 3 + 1] = frame[i];  // G
            rgb[i * 3 + 2] = frame[i];  // B
        }

        // Actualizar textura y renderizar escalado
        SDL_UpdateTexture(texture, NULL, rgb, W * 3);
        SDL_RenderClear(renderer);

        SDL_FRect dst = {0, 0, (float)WIN_W, (float)WIN_H};
        SDL_RenderTexture(renderer, texture, NULL, &dst);
        SDL_RenderPresent(renderer);

        frame_num++;
        SDL_SetWindowTitle(window,
            (std::string("VICON cam_sim — frame ") + std::to_string(frame_num)).c_str());

        // Buscar siguiente marcador
        int idx = find_marker(accum, accum_len);
        if (idx >= 0) {
            accum_len -= idx + 4;
            memmove(accum, accum + idx + 4, accum_len);
        } else {
            while (running) {
                while (SDL_PollEvent(&event)) {
                    if (event.type == SDL_EVENT_QUIT) running = false;
                    if (event.type == SDL_EVENT_KEY_DOWN && event.key.key == SDLK_ESCAPE) running = false;
                }
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

    SDL_DestroyTexture(texture);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    FT_Close(handle);
    return 0;
}