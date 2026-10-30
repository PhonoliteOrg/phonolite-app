#if defined(_MSC_VER)
/* Visibility attributes have no effect in the standalone test executable. */
#define __attribute__(attributes)
#endif
