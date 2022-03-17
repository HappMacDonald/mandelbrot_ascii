// Has memset()
#include <string.h>

// Has uint64_t
#include <stdint.h>

void notmain(uint64_t buffer[16])
{ memset(buffer, 0, 24);
}