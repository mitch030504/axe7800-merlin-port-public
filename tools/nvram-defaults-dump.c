/* Print name<TAB>value of every entry in a libshared.so's router_defaults[] (read-only). */
#include <stdio.h>
#include <dlfcn.h>
struct nvram_tuple { char *name; char *value; unsigned short len, type, acc_level, enc; struct nvram_tuple *next; };
int main(int argc, char **argv) {
    void *h = dlopen(argc > 1 ? argv[1] : "/usr/lib/libshared.so", RTLD_LAZY | RTLD_GLOBAL);
    if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 2; }
    struct nvram_tuple *t = dlsym(h, "router_defaults");
    if (!t) { fprintf(stderr, "dlsym: %s\n", dlerror()); return 2; }
    for (; t->name; t++) printf("%s\t%s\n", t->name, t->value ? t->value : "(null)");
    return 0;
}
