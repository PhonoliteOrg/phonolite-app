#include "runner/infrastructure/flutter/method_response_sender.h"

namespace phonolite {

gboolean send_method_response(FlMethodCall* method_call, FlMethodResponse* response, GError** error) {
  // Typed responders pass transport errors directly to the caller, avoiding the
  // generic responder's intermediate GError ownership in the current embedding.
  if (FL_IS_METHOD_SUCCESS_RESPONSE(response)) {
    return fl_method_call_respond_success(
        method_call, fl_method_success_response_get_result(FL_METHOD_SUCCESS_RESPONSE(response)), error);
  }

  if (FL_IS_METHOD_ERROR_RESPONSE(response)) {
    auto* failure = FL_METHOD_ERROR_RESPONSE(response);

    return fl_method_call_respond_error(method_call, fl_method_error_response_get_code(failure),
                                       fl_method_error_response_get_message(failure),
                                       fl_method_error_response_get_details(failure), error);
  }

  g_return_val_if_fail(FL_IS_METHOD_NOT_IMPLEMENTED_RESPONSE(response), FALSE);

  return fl_method_call_respond_not_implemented(method_call, error);
}

} // namespace phonolite
