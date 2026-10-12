// AppDock, MIT. Calls the separately installed libimobiledevice at runtime.
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (argc != 3) return 2;
    alarm(25);
    void *lib = dlopen("/opt/homebrew/lib/libimobiledevice-1.0.dylib", RTLD_NOW);
    if (!lib) lib = dlopen("/usr/local/lib/libimobiledevice-1.0.dylib", RTLD_NOW);
    if (!lib) { fprintf(stderr,"Установите libimobiledevice через Homebrew.\n"); return 3; }
    int (*device_new)(void **, const char *) = dlsym(lib,"idevice_new");
    int (*device_free)(void *) = dlsym(lib,"idevice_free");
    int (*start)(void *, void **, const char *) = dlsym(lib,"sbservices_client_start_service");
    int (*client_free)(void *) = dlsym(lib,"sbservices_client_free");
    int (*wallpaper)(void *, char **, uint64_t *) = dlsym(lib,"sbservices_get_home_screen_wallpaper_pngdata");
    if (!device_new || !device_free || !start || !client_free || !wallpaper) { dlclose(lib); return 4; }
    void *device = NULL, *client = NULL; char *png = NULL; uint64_t size = 0; int result = 5;
    if (device_new(&device,argv[1]) != 0) { fprintf(stderr,"iPhone не подключён по USB.\n"); goto cleanup; }
    if (start(device,&client,"AppDock") != 0) { fprintf(stderr,"Служба SpringBoard недоступна. Разблокируйте iPhone и подтвердите доверие.\n"); goto cleanup; }
    if (wallpaper(client,&png,&size) != 0 || !png || size < 8 || size > 32*1024*1024) {
        fprintf(stderr,"Эта версия iOS не отдала обои через SpringBoard. Можно выбрать изображение вручную.\n"); goto cleanup;
    }
    FILE *file = fopen(argv[2],"wb");
    if (!file) goto cleanup;
    size_t written = fwrite(png,1,(size_t)size,file); int closed = fclose(file);
    if (written != size || closed != 0) { unlink(argv[2]); goto cleanup; }
    result = 0; puts("Обои получены по USB.");
cleanup:
    free(png); if (client) client_free(client); if (device) device_free(device); dlclose(lib); return result;
}
