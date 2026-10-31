#ifndef PHONOLITE_UPDATER_INFRASTRUCTURE_UPDATE_JSON_H_
#define PHONOLITE_UPDATER_INFRASTRUCTURE_UPDATE_JSON_H_

#include <map>
#include <set>
#include <string>

#include <json-glib/json-glib.h>

namespace phonolite {
namespace updates {

class JsonDocument {
 public:
  explicit JsonDocument(const std::string& source);
  ~JsonDocument();
  JsonDocument(const JsonDocument&) = delete;
  JsonDocument& operator=(const JsonDocument&) = delete;

  JsonObject* object() const;

 private:
  static void member(JsonParser*, JsonObject* object, const gchar* name, gpointer data);

  JsonParser* parser_ = nullptr;
  std::map<JsonObject*, std::set<std::string>> members_;
  bool duplicate_ = false;
};

std::string string_value(JsonObject* object, const char* name);
gint64 integer_value(JsonObject* object, const char* name);
bool boolean_value(JsonObject* object, const char* name);
JsonArray* array_value(JsonObject* object, const char* name);
JsonObject* object_value(JsonObject* object, const char* name);
std::string json_string(const std::string& value);
std::string serialize(JsonNode* node);

} // namespace updates
} // namespace phonolite

#endif
