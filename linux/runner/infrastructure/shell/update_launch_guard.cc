#include "runner/infrastructure/shell/update_launch_guard.h"

#include <cerrno>

#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

namespace phonolite {

bool update_allows_launch() {
  const int descriptor = open("/var/lib/phonolite-updates/transaction.lock", O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  if (descriptor < 0) {
    return errno == ENOENT;
  }
  struct stat metadata{};
  const bool valid = fstat(descriptor, &metadata) == 0 && S_ISREG(metadata.st_mode) && metadata.st_uid == 0 &&
                     (metadata.st_mode & 022) == 0;
  const bool available = valid && flock(descriptor, LOCK_SH | LOCK_NB) == 0;
  close(descriptor);
  return available;
}

} // namespace phonolite
