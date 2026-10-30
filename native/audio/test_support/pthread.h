#ifndef PHONOLITE_TEST_PTHREAD_H
#define PHONOLITE_TEST_PTHREAD_H
/* The fake executes callbacks synchronously to cover callback reentrancy. */
typedef int pthread_mutex_t;
static inline int pthread_mutex_init(pthread_mutex_t *mutex, const void *attributes) {
  (void)attributes;
  *mutex = 0;
  return 0;
}
static inline int pthread_mutex_destroy(pthread_mutex_t *mutex) { (void)mutex; return 0; }
static inline int pthread_mutex_lock(pthread_mutex_t *mutex) { (void)mutex; return 0; }
static inline int pthread_mutex_unlock(pthread_mutex_t *mutex) { (void)mutex; return 0; }
#endif
