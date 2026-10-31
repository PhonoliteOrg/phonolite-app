#ifndef PHONOLITE_RUNNER_INFRASTRUCTURE_FLUTTER_METHOD_RESPONSE_SENDER_H_
#define PHONOLITE_RUNNER_INFRASTRUCTURE_FLUTTER_METHOD_RESPONSE_SENDER_H_

#include <flutter_linux/flutter_linux.h>

namespace phonolite {

// Borrows the call/response and sends once. On failure, the caller owns *error.
gboolean send_method_response(FlMethodCall* method_call, FlMethodResponse* response, GError** error);

} // namespace phonolite

#endif // PHONOLITE_RUNNER_INFRASTRUCTURE_FLUTTER_METHOD_RESPONSE_SENDER_H_
