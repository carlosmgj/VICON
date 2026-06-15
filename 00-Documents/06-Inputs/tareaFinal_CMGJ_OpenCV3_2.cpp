// Práctica final de Visión Carlos Manuel Gómez Jiménez
// Incluye las mejoras indicadas en las instrucciones

#include <opencv2/opencv.hpp>
#include <iostream>

using namespace cv;
using namespace std;

bool pausado = false;
bool mostrar_info = false; // Usaremos esta flag para mostrar u ocultar la información
int tipo_filtro = 0; // 0: Gaussian, 1: Blur, 2: Mediana, 3: Bilateral

int main(int argc, char** argv) {
    // Si nose pasan por argumentops cuántos frames seguir con tracking, usamos 20 por defecto
    int N = 20;
    if (argc == 2) {
        N = atoi(argv[1]);
    }

    // Cargamos el detector de caras (usamos Haar cascades como antes)
    String face_cascade_path = "C:/opencv/sources/data/haarcascades/haarcascade_frontalface_alt2.xml";
    CascadeClassifier face_cascade;
    if (!face_cascade.load(face_cascade_path)) {
        cerr << "No se pudo cargar el detector de caras" << endl;
        return -1;
    }

    // Descomentar el siguiente código para abrir la webcam del pc
    /*VideoCapture cap(0);
    if (!cap.isOpened()) {
        cerr << "Algo fue mal al abrir la cámara." << endl;
        return -1;
    }*/

    // Para un archivo de video, cambiar la ruta por la del vídeo en cuestión.
    String video_path = "C:/Users/carlos/Videos/2025-02-05 19-04-07.mkv";
    VideoCapture cap(video_path);
    if (!cap.isOpened()) {
        cerr << "No se pudo abrir el video: " << video_path << endl;
        return -1;
    }

    // Crear el VideoWriter para guardar el video de salida
    int frame_width = (int)cap.get(CAP_PROP_FRAME_WIDTH);  // Ancho del fotograma
    int frame_height = (int)cap.get(CAP_PROP_FRAME_HEIGHT);  // Alto del fotograma
    VideoWriter writer("videosalida.avi", VideoWriter::fourcc('M', 'J', 'P', 'G'), 30, Size(frame_width, frame_height));

    Mat frame, hsv, hue, mask, hist, backproj;
    Mat output;
    Rect tracking_window;
    bool tracking = false;
    int tracking_counter = 0;

    // Parámetros para CamShift, cogemos los mismos del github
    TermCriteria term_crit(TermCriteria::EPS | TermCriteria::COUNT, 10, 1);
    int hsize = 16;
    float hranges[] = { 0,180 };
    const float* phranges = hranges;

    int frame_count = 0; // Contador de fotogramas
    double fps = 0.0;    // Variable para almacenar el FPS
    double time_prev = 0; // Variable para calcular el tiempo transcurrido

    while (true) {

        if (pausado) {
            imshow("Anonimizador con CamShift", output);
            if ((char)waitKey(30) == 'p') pausado = false;
            continue;
        }

        double start_time = (double)getTickCount(); // Tiempo de inicio de procesamiento del fotograma
        cap >> frame;
        if (frame.empty()) break; // Si no llega nada de la cámara, salimos

        output = frame.clone();

        vector<Rect> faces;
        face_cascade.detectMultiScale(frame, faces, 1.4, 4, 0, Size(30, 30)); // Detección de caras

        int num_faces = faces.size(); // Número de caras detectadas

        // Si no estamos siguiendo nada o ya se nos fue de las manos (más de N frames), detectamos otra vez
        if (!tracking || tracking_counter >= N) {
            if (!faces.empty()) {
                Rect largest_face;
                int max_area = 0;
                for (const Rect& f : faces) {
                    int area = f.width * f.height;
                    if (area > max_area) {
                        max_area = area;
                        largest_face = f;
                    }
                }

                tracking_window = largest_face;

                cvtColor(frame, hsv, COLOR_BGR2HSV);
                inRange(hsv, Scalar(0, 10, 0), Scalar(180, 256, 256), mask);
                int ch[] = { 0, 0 };
                hue.create(hsv.size(), hsv.depth());
                mixChannels(&hsv, 1, &hue, 1, ch, 1);

                Mat roi(hue, tracking_window), maskroi(mask, tracking_window);
                calcHist(&roi, 1, 0, maskroi, hist, 1, &hsize, &phranges);
                normalize(hist, hist, 0, 255, NORM_MINMAX); // para que sea más estable

                tracking = true;
                tracking_counter = 0; // empezamos de cero otra vez
            }
        }

        if (tracking) {
            cvtColor(frame, hsv, COLOR_BGR2HSV);
            inRange(hsv, Scalar(0, 30, 10), Scalar(180, 256, 256), mask);
            int ch[] = { 0, 0 };
            mixChannels(&hsv, 1, &hue, 1, ch, 1);
            calcBackProject(&hue, 1, 0, hist, backproj, &phranges);
            backproj &= mask;

            RotatedRect track_box = CamShift(backproj, tracking_window, term_crit);

            if (tracking_window.area() <= 1) {
                tracking = false; // se perdió el rastro
            }
            else {
                Rect roi = tracking_window & Rect(0, 0, frame.cols, frame.rows);
                if (roi.width > 0 && roi.height > 0) {
                    Mat faceROI = output(roi);
                    switch (tipo_filtro) {
                    case 0: // Gausiano
                        GaussianBlur(faceROI, faceROI, Size(55, 55), 0);
                        break;
                    case 1: // Blur normal
                        blur(faceROI, faceROI, Size(55, 55));
                        break;
                    case 2: // Mediana
                        medianBlur(faceROI, faceROI, 25);
                        break;
                    case 3: { // Bilateral
                        Mat faceCopy = faceROI.clone();
                        Mat temp;
                        bilateralFilter(faceCopy, temp, 15, 75, 75);
                        temp.copyTo(faceROI);
                        break;
                    }
                    }
                }
                tracking_counter++;
            }
        }

        // Calcular FPS
        double time_current = (double)getTickCount();
        fps = getTickFrequency() / (time_current - start_time);
        frame_count++;

        // Mostrar/ocultar la información
        if (mostrar_info) {
            putText(output, "Frame: " + to_string(frame_count), Point(10, 30), FONT_HERSHEY_SIMPLEX, 1, Scalar(255, 255, 255), 2);
            putText(output, "FPS: " + to_string((int)fps), Point(10, 60), FONT_HERSHEY_SIMPLEX, 1, Scalar(255, 255, 255), 2);
            putText(output, "Caras detectadas: " + to_string(num_faces), Point(10, 90), FONT_HERSHEY_SIMPLEX, 1, Scalar(255, 255, 255), 2);
        }

        // Escribir el fotograma procesado en el archivo de salida
        writer.write(output);

        // Mostrar el resultado en tiempo real
        imshow("Anonimizador con CamShift", output);
        char key = (char)waitKey(30);

        if (key == 27 || key == 'q' || key == 'Q') break;
        else if (key == 'p' || key == 'P') {
            pausado = !pausado;
            cout << (pausado ? "[Pausado]" : "[Reanudado]") << endl;
        }
        else if (key == 'f' || key == 'F') {
            tipo_filtro = (tipo_filtro + 1) % 4;
            cout << "Filtro cambiado a: " << tipo_filtro << endl;
        }
        else if (key == 'i' || key == 'I') {
            mostrar_info = !mostrar_info; // Incluimos la mejora 3 con la letra i
        }
    }

    // Liberar recursos
    cap.release();
    writer.release(); 
    destroyAllWindows();
    return 0;
}
