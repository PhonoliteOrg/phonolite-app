#include "infrastructure/update_json.h"

#include <stdexcept>

namespace phonolite {
namespace updates {
namespace {

JsonNode* required(JsonObject* object, const char* name) {
  JsonNode* value = json_object_get_member(object, name);
  if (value == nullptr) {
    throw std::runtime_error(std::string("Missing update field: ") + name);
  }

  return value;
}

} // namespace

JsonDocument::JsonDocument(const std::string& source) {
  if (source.size() > 1024 * 1024) {
    throw std::runtime_error("Update JSON exceeds its size limit.");
  }

  unsigned depth = 0;
  bool quoted = false;
  bool escaped = false;
  for (const char character : source) {
    if (character == '\0')
      throw std::runtime_error("NUL bytes are not valid update JSON.");
    if (quoted) {
      if (!escaped && character == '"')
        quoted = false;
      if (!escaped && character == '\\')
        escaped = true;
      else
        escaped = false;
    } else if (character == '"') {
      quoted = true;
    } else if (character == '{' || character == '[') {
      if (++depth > 32)
        throw std::runtime_error("Update JSON nesting exceeds its limit.");
    } else if (character == '}' || character == ']') {
      if (depth == 0)
        throw std::runtime_error("Unbalanced update JSON.");
      --depth;
    }
  }
  parser_ = json_parser_new();
#if JSON_CHECK_VERSION(1, 10, 0)
  json_parser_set_strict(parser_, TRUE);
#endif
  g_signal_connect(parser_, "object-member", G_CALLBACK(member), this);
  g_autoptr(GError) error = nullptr;
  if (!json_parser_load_from_data(parser_, source.data(), source.size(), &error) || duplicate_ ||
      !JSON_NODE_HOLDS_OBJECT(json_parser_get_root(parser_))) {
    const std::string message = duplicate_ ? "Duplicate update JSON field." : "Invalid update JSON object.";
    g_clear_object(&parser_);

    throw std::runtime_error(message);
  }
}

JsonDocument::~JsonDocument() {
  g_clear_object(&parser_);
}

void JsonDocument::member(JsonParser*, JsonObject* object, const gchar* name, gpointer data) {
  auto* self = static_cast<JsonDocument*>(data);
  try {
    if (!self->members_[object].insert(name).second)
      self->duplicate_ = true;
  } catch (...) {
    // Signal callbacks must never unwind through GLib. Reject the document.
    self->duplicate_ = true;
  }
}

JsonObject* JsonDocument::object() const {
  return json_node_get_object(json_parser_get_root(parser_));
}

std::string string_value(JsonObject* object, const char* name) {
  JsonNode* node = required(object, name);
  if (json_node_get_value_type(node) != G_TYPE_STRING) {
    throw std::runtime_error(std::string("Expected update string: ") + name);
  }

  return json_node_get_string(node);
}

gint64 integer_value(JsonObject* object, const char* name) {
  JsonNode* node = required(object, name);
  if (json_node_get_value_type(node) != G_TYPE_INT64 || json_node_get_int(node) < 0) {
    throw std::runtime_error(std::string("Expected nonnegative update integer: ") + name);
  }

  return json_node_get_int(node);
}

bool boolean_value(JsonObject* object, const char* name) {
  JsonNode* node = required(object, name);
  if (json_node_get_value_type(node) != G_TYPE_BOOLEAN) {
    throw std::runtime_error(std::string("Expected update boolean: ") + name);
  }

  return json_node_get_boolean(node);
}

JsonArray* array_value(JsonObject* object, const char* name) {
  JsonNode* node = required(object, name);
  if (!JSON_NODE_HOLDS_ARRAY(node)) {
    throw std::runtime_error(std::string("Expected update array: ") + name);
  }

  return json_node_get_array(node);
}

JsonObject* object_value(JsonObject* object, const char* name) {
  JsonNode* node = required(object, name);
  if (!JSON_NODE_HOLDS_OBJECT(node)) {
    throw std::runtime_error(std::string("Expected update object: ") + name);
  }

  return json_node_get_object(node);
}

std::string serialize(JsonNode* node) {
  g_autoptr(JsonGenerator) generator = json_generator_new();
  json_generator_set_root(generator, node);
  g_autofree gchar* value = json_generator_to_data(generator, nullptr);

  return value;
}

std::string json_string(const std::string& value) {
  g_autoptr(JsonNode) node = json_node_new(JSON_NODE_VALUE);
  json_node_set_string(node, value.c_str());

  return serialize(node);
}

} // namespace updates
} // namespace phonolite
