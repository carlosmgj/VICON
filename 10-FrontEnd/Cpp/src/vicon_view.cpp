//! \file vicon_view.cpp
//! \brief Visor VICON + terminal de comandos (Seguro contra bloqueos de lectura y desalineación).

#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <iostream>
#include "ftd2xx.h"
#include <SDL3/SDL.h>
#include <string>
#include <thread>
#include <atomic>
#include <mutex>
#include <chrono>
#include <deque>
#include <sstream>
#include <vector>

// ─── Configuración ────────────────────────────────────────────────────────────
static const int     H           = 480;
static const int     W           = 640;
static const int     FRAME_BYTES = H * W;
static const uint8_t MARKER[4]   = {0xAA, 0x55, 0xAA, 0x55};
static const int     BUF_SIZE    = 65536;
static const int     WIN_W       = 1020;
static const int     WIN_H       = 800;

// Byte de sincronismo de comandos PC→FPGA
static const uint8_t CMD_SYNC = 0xCC;

// Tipos de comando
static const uint8_t CMD_LED  = 0x01;
static const uint8_t CMD_BCD  = 0x02;
static const uint8_t CMD_I2C  = 0x03;
static const uint8_t CMD_CAP  = 0x04;
static const uint8_t CMD_SIM  = 0x05;

// ─── Estado global ────────────────────────────────────────────────────────────
static FT_HANDLE         g_handle  = nullptr;
static std::mutex        g_write_mtx;  // Protege ÚNICAMENTE el FT_Write de la terminal
static std::atomic<bool> g_running = true;

// Búfer protegido para intercambiar frames entre el hilo de lectura y el de render
static uint8_t           g_frame_buffer[FRAME_BYTES];
static std::mutex        g_frame_mtx;  // Protege el acceso al frame copiado
static std::atomic<bool> g_new_frame_available{false};

// ─── Helpers de protocolo (HILO TERMINAL) ─────────────────────────────────────

static bool send_cmd4(uint8_t cmd, uint16_t data)
{
    uint8_t pkt[4] = {CMD_SYNC, cmd,
                      static_cast<uint8_t>(data >> 8),
                      static_cast<uint8_t>(data & 0xFF)};
    DWORD written = 0;
    std::lock_guard<std::mutex> lk(g_write_mtx); 
    FT_STATUS st = FT_Write(g_handle, pkt, 4, &written);
    return (st == FT_OK && written == 4);
}

static bool send_cmd_i2c(uint8_t page, uint8_t addr, uint16_t data)
{
    uint8_t pkt[6] = {CMD_SYNC, CMD_I2C, page, addr,
                      static_cast<uint8_t>(data >> 8),
                      static_cast<uint8_t>(data & 0xFF)};
    DWORD written = 0;
    std::lock_guard<std::mutex> lk(g_write_mtx);
    FT_STATUS st = FT_Write(g_handle, pkt, 6, &written);
    return (st == FT_OK && written == 6);
}

static bool send_raw(const std::vector<uint8_t>& bytes, DWORD& written)
{
    written = 0;
    std::lock_guard<std::mutex> lk(g_write_mtx);
    FT_STATUS st = FT_Write(g_handle, (void*)bytes.data(),
                            (DWORD)bytes.size(), &written);
    return (st == FT_OK && written == bytes.size());
}

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

// ─── Parser de comandos (HILO TERMINAL) ───────────────────────────────────────
static void parse_and_send(const std::string& line)
{
    std::istringstream iss(line);
    std::string cmd;
    iss >> cmd;

    if (cmd == "help" || cmd == "?") {
        printf("Comandos:\n");
        printf("  led <hex>                -> ej: led 0xFFFF\n");
        printf("  bcd <4digitos>           -> ej: bcd 1234\n");
        printf("  i2c <page> <addr> <data> -> ej: i2c 1 0x37 0x0080\n");
        printf("  cap on|off               -> habilitar/deshabilitar captura\n");
        printf("  sim on|off               -> imagen sintetica / sensor real\n");
        printf("  raw <b0> <b1> ...        -> ej: raw 0xCC 0x05 0x00 0x01\n");
        printf("  quit                     -> salir\n");
        return;
    }

    if (cmd == "quit" || cmd == "exit") {
        g_running = false;
        return;
    }

    if (cmd == "led") {
        std::string val;
        iss >> val;
        uint16_t mask = (uint16_t)strtoul(val.c_str(), nullptr, 0);
        if (send_cmd4(CMD_LED, mask))
            printf("[OK] LED mask = 0x%04X\n", mask);
        else
            printf("[ERR] Fallo enviando comando LED\n");
        return;
    }

    if (cmd == "bcd") {
        std::string val;
        iss >> val;
        if (val.size() != 4) {
            printf("[ERR] bcd necesita exactamente 4 digitos (0-9)\n");
            return;
        }
        uint16_t data = 0;
        for (int i = 0; i < 4; i++) {
            if (val[i] < '0' || val[i] > '9') {
                printf("[ERR] Digito invalido '%c'\n", val[i]);
                return;
            }
            data = (data << 4) | (val[i] - '0');
        }
        if (send_cmd4(CMD_BCD, data))
            printf("[OK] BCD = %s\n", val.c_str());
        else
            printf("[ERR] Fallo enviando comando BCD\n");
        return;
    }

    if (cmd == "i2c") {
        std::string str_page, str_addr, str_data;
        iss >> str_page >> str_addr >> str_data;
        if (str_page.empty() || str_addr.empty() || str_data.empty()) {
            printf("[ERR] Uso: i2c <page> <addr> <data>\n");
            return;
        }
        uint8_t  page = (uint8_t) strtoul(str_page.c_str(), nullptr, 0);
        uint8_t  addr = (uint8_t) strtoul(str_addr.c_str(), nullptr, 0);
        uint16_t data = (uint16_t)strtoul(str_data.c_str(), nullptr, 0);
        if (send_cmd_i2c(page, addr, data))
            printf("[OK] I2C page=%d addr=0x%02X data=0x%04X\n", page, addr, data);
        else
            printf("[ERR] Fallo enviando comando I2C\n");
        return;
    }

    if (cmd == "cap") {
        std::string val;
        iss >> val;
        if (val == "on") {
            if (send_cmd4(CMD_CAP, 1))
                printf("[OK] Captura activada\n");
            else
                printf("[ERR] Fallo enviando cap on\n");
        } else if (val == "off") {
            if (send_cmd4(CMD_CAP, 0))
                printf("[OK] Captura desactivada\n");
            else
                printf("[ERR] Fallo enviando cap off\n");
        } else {
            printf("[ERR] Uso: cap on|off\n");
        }
        return;
    }

    if (cmd == "sim") {
        std::string val;
        iss >> val;
        if (val == "on") {
            if (send_cmd4(CMD_SIM, 1))
                printf("[OK] Imagen sintetica activada\n");
            else
                printf("[ERR] Fallo enviando sim on\n");
        } else if (val == "off") {
            if (send_cmd4(CMD_SIM, 0))
                printf("[OK] Sensor real activado\n");
            else
                printf("[ERR] Fallo enviando sim off\n");
        } else {
            printf("[ERR] Uso: sim on|off\n");
        }
        return;
    }

    if (cmd == "raw") {
        std::vector<uint8_t> bytes;
        std::string tok;
        while (iss >> tok) {
            unsigned long v = strtoul(tok.c_str(), nullptr, 0);
            if (v > 0xFF) {
                printf("[ERR] Byte fuera de rango: '%s' (debe ser 0x00-0xFF)\n",
                       tok.c_str());
                return;
            }
            bytes.push_back((uint8_t)v);
        }
        if (bytes.empty()) {
            printf("[ERR] Uso: raw <byte0> <byte1> ... (hex con 0x o decimal)\n");
            return;
        }
        DWORD written = 0;
        if (send_raw(bytes, written)) {
            printf("[OK] Enviados %lu bytes:", written);
            for (auto b : bytes) printf(" %02X", b);
            printf("\n");
        } else {
            printf("[ERR] Fallo enviando bytes raw (escritos %lu/%zu)\n",
                   written, bytes.size());
        }
        return;
    }

    if (!cmd.empty())
        printf("[ERR] Comando desconocido '%s'. Escribe 'help'.\n", cmd.c_str());
}

// ─── Hilo de terminal ─────────────────────────────────────────────────────────
static void terminal_thread()
{
    printf("Terminal VICON lista. Escribe 'help' para ver los comandos.\n");
    std::string line;
    while (g_running) {
        printf("> ");
        fflush(stdout);
        if (!std::getline(std::cin, line))
            break;
        if (!line.empty())
            parse_and_send(line);
    }
}

// ─── Hilo de adquisición FTDI (Con Sincronización Estricta) ───────────────────
static void ftdi_rx_thread()
{
    SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);

    uint8_t raw[BUF_SIZE];
    uint8_t accum[BUF_SIZE * 8];
    int     accum_len = 0;
    DWORD   bytes_read = 0;

    printf("[RX Thread] Iniciando captura...\n");

    while (g_running) {
        // 1. Leer datos del FTDI si el acumulador no tiene bytes suficientes para un frame entero
        if (accum_len < (FRAME_BYTES + 4)) {
            FT_STATUS st = FT_Read(g_handle, raw, BUF_SIZE, &bytes_read);
            if (st == FT_OK && bytes_read > 0) {
                memcpy(accum + accum_len, raw, bytes_read);
                accum_len += bytes_read;
            } else {
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
                continue;
            }
        }

        // 2. Buscar obligatoriamente el marcador que delimita el inicio real de la imagen
        int idx = find_marker(accum, accum_len);
        
        if (idx < 0) {
            // No hay marcador en el buffer. Si creció demasiado limpiamos basura 
            // dejando los últimos 3 bytes por si el marcador quedó a medias en el extremo.
            if (accum_len > BUF_SIZE * 4) {
                memmove(accum, accum + accum_len - 3, 3);
                accum_len = 3;
            }
            continue; 
        }

        // Si el marcador no está al inicio (idx > 0), tiramos la basura del bus previa a él
        if (idx > 0) {
            accum_len -= idx;
            memmove(accum, accum + idx, accum_len);
        }

        // 3. Una vez alineado (el buffer empieza estrictamente con AA 55 AA 55)
        // comprobamos si ya se han recibido los datos de la imagen completos
        if (accum_len >= (4 + FRAME_BYTES)) {
            
            // Copiamos el frame saltándonos los 4 bytes del marcador
            {
                std::lock_guard<std::mutex> lk(g_frame_mtx);
                memcpy(g_frame_buffer, accum + 4, FRAME_BYTES);
                g_new_frame_available = true;
            }

            // Descartamos del buffer el bloque que ya enviamos a renderizar
            int bytes_to_discard = 4 + FRAME_BYTES;
            accum_len -= bytes_to_discard;
            memmove(accum, accum + bytes_to_discard, accum_len);
        }
    }
}

// ─── Main (HILO PRINCIPAL / RENDERIZADO) ──────────────────────────────────────
int main(void)
{
    printf("VICON viewer + control\n");

    // ─── SDL ─────────────────────────────────────────────────────────────────
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        printf("SDL_Init error: %s\n", SDL_GetError());
        return 1;
    }

    SDL_Window* window   = SDL_CreateWindow("VICON", WIN_W, WIN_H, 0);
    SDL_Renderer* renderer = SDL_CreateRenderer(window, NULL);
    SDL_Texture* texture  = SDL_CreateTexture(renderer,
                                SDL_PIXELFORMAT_RGB24,
                                SDL_TEXTUREACCESS_STREAMING,
                                W, H);
    if (!window || !renderer || !texture) {
        printf("SDL error: %s\n", SDL_GetError());
        return 1;
    }

    // ─── FT232H ──────────────────────────────────────────────────────────────
    if (FT_Open(0, &g_handle) != FT_OK) {
        printf("Error abriendo FT232H\n");
        return 1;
    }
    FT_SetBitMode(g_handle, 0xFF, FT_BITMODE_SYNC_FIFO);
    
    // El timeout evita bloqueos permanentes en el FT_Read al mandar la orden de cierre
    FT_SetTimeouts(g_handle, 200, 200); 
    FT_SetUSBParameters(g_handle, 65536, 65536);

    // Purgar al arrancar de forma segura
    {
        std::lock_guard<std::mutex> lk(g_write_mtx);
        FT_Purge(g_handle, FT_PURGE_RX | FT_PURGE_TX);
    }
    printf("Buffer FT232H purgado.\n");
    printf("FT232H listo. Mostrando %dx%d\n", W, H);

    // ─── Hilos Auxiliares ─────────────────────────────────────────────────────
    std::thread term_thread(terminal_thread);
    term_thread.detach();

    std::thread rx_thread(ftdi_rx_thread);

    // Buffers Locales para este hilo de Render
    uint8_t local_frame[FRAME_BYTES];
    uint8_t rgb[W * H * 3];

    // Control de FPS de SDL
    using Clock = std::chrono::steady_clock;
    std::deque<Clock::time_point> frame_times;
    float fps = 0.0f;
    int   frame_num = 0;
    SDL_Event event;

    // ─── Bucle de refresco de pantalla ────────────────────────────────────────
    while (g_running) {
        // Procesar eventos de la ventana (mantiene Windows feliz y con fluidez)
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT)
                g_running = false;
            if (event.type == SDL_EVENT_KEY_DOWN &&
                event.key.key == SDLK_ESCAPE)
                g_running = false;
        }

        bool draw_frame = false;

        // Intentar capturar la última imagen procesada por el hilo FTDI
        if (g_new_frame_available) {
            std::lock_guard<std::mutex> lk(g_frame_mtx);
            memcpy(local_frame, g_frame_buffer, FRAME_BYTES);
            g_new_frame_available = false;
            draw_frame = true;
        }

        if (draw_frame) {
            // Conversión rápida Y -> RGB de 24 bits
            for (int i = 0; i < FRAME_BYTES; i++) {
                rgb[i*3+0] = local_frame[i];
                rgb[i*3+1] = local_frame[i];
                rgb[i*3+2] = local_frame[i];
            }

            // Dibujar en textura escalada a pantalla completa
            SDL_UpdateTexture(texture, NULL, rgb, W * 3);
            SDL_RenderClear(renderer);
            SDL_FRect dst = {0, 0, (float)WIN_W, (float)WIN_H};
            SDL_RenderTexture(renderer, texture, NULL, &dst);
            SDL_RenderPresent(renderer);

            frame_num++;

            // Contador de FPS reales
            auto now = Clock::now();
            frame_times.push_back(now);
            if (frame_times.size() > 30) frame_times.pop_front();
            if (frame_times.size() >= 2) {
                float elapsed = std::chrono::duration<float>(
                    frame_times.back() - frame_times.front()).count();
                fps = (frame_times.size() - 1) / elapsed;
            }

            char title[64];
            snprintf(title, sizeof(title),
                     "VICON - frame %d | %.1f fps", frame_num, fps);
            SDL_SetWindowTitle(window, title);
        } else {
            // Dormir levemente si el hardware no está inyectando frames (cap off)
            std::this_thread::sleep_for(std::chrono::milliseconds(8));
        }
    }

    // ─── Salida ordenada ──────────────────────────────────────────────────────
    printf("Cerrando aplicación...\n");
    g_running = false;
    
    if (rx_thread.joinable()) {
        rx_thread.join(); 
    }

    SDL_DestroyTexture(texture);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    FT_Close(g_handle);
    return 0;
}