#include "infrastructure/manifest_verifier.h"

#include <memory>
#include <regex>
#include <set>
#include <stdexcept>
#include <utility>

#include <gio/gio.h>
#include <openssl/evp.h>

#include "infrastructure/update_json.h"

namespace phonolite {
namespace updates {
namespace {

std::string decode(const std::string& text, std::size_t size) {
  gsize length = 0;
  g_autofree guchar* bytes = g_base64_decode(text.c_str(), &length);
  g_autofree gchar* canonical = g_base64_encode(bytes, length);
  if (length != size || text != canonical) {
    throw std::runtime_error("Invalid signing key or signature encoding.");
  }

  return std::string(reinterpret_cast<char*>(bytes), length);
}

bool valid_signature(const std::string& message, const std::string& signature, const std::string& public_key) {
  const std::string key = decode(public_key, 32);
  const std::string proof = decode(signature, 64);
  std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)> verifier(
      EVP_PKEY_new_raw_public_key(EVP_PKEY_ED25519, nullptr, reinterpret_cast<const unsigned char*>(key.data()),
                                  key.size()),
      EVP_PKEY_free);
  std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> context(EVP_MD_CTX_new(), EVP_MD_CTX_free);

  return verifier && context && EVP_DigestVerifyInit(context.get(), nullptr, nullptr, nullptr, verifier.get()) == 1 &&
         EVP_DigestVerify(context.get(), reinterpret_cast<const unsigned char*>(proof.data()), proof.size(),
                          reinterpret_cast<const unsigned char*>(message.data()), message.size()) == 1;
}

void check_url(const std::string& value) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GUri) uri = g_uri_parse(value.c_str(), G_URI_FLAGS_NONE, &error);
  if (uri == nullptr || g_strcmp0(g_uri_get_scheme(uri), "https") != 0 || g_uri_get_host(uri) == nullptr ||
      *g_uri_get_host(uri) == '\0' || g_uri_get_userinfo(uri) != nullptr || g_uri_get_fragment(uri) != nullptr) {
    throw std::runtime_error("Update assets must use HTTPS without credentials or fragments.");
  }
}

} // namespace

ManifestVerifier::ManifestVerifier(std::map<std::string, std::string> trusted_keys)
    : trusted_keys_(std::move(trusted_keys)) {}

Manifest ManifestVerifier::verify(const std::string& manifest, const std::string& signatures, std::time_t now) const {
  if (manifest.empty() || manifest.size() > 1024 * 1024 || signatures.size() > 8192) {
    throw std::runtime_error("Update metadata exceeds its size limit.");
  }

  JsonDocument proof(signatures);
  if (integer_value(proof.object(), "schema") != 1) {
    throw std::runtime_error("Unsupported signature schema.");
  }

  JsonArray* proofs = array_value(proof.object(), "signatures");
  if (json_array_get_length(proofs) == 0 || json_array_get_length(proofs) > 8) {
    throw std::runtime_error("Invalid update signature list.");
  }

  bool verified = false;
  std::set<std::string> key_ids;
  for (guint index = 0; index < json_array_get_length(proofs); ++index) {
    JsonNode* node = json_array_get_element(proofs, index);
    if (!JSON_NODE_HOLDS_OBJECT(node)) {
      throw std::runtime_error("Invalid update signature object.");
    }
    JsonObject* item = json_node_get_object(node);
    const auto key_id = string_value(item, "key_id");
    if (!key_ids.insert(key_id).second)
      throw std::runtime_error("Duplicate signing identity.");
    auto key = trusted_keys_.find(key_id);
    if (key != trusted_keys_.end() && valid_signature(manifest, string_value(item, "signature"), key->second)) {
      verified = true;
    }
  }

  if (!verified) {
    throw std::runtime_error("The update signature is invalid or its signing key is unknown.");
  }

  JsonDocument document(manifest);
  JsonObject* root = document.object();
  if (integer_value(root, "schema") != 1 || string_value(root, "channel") != "stable" ||
      string_value(root, "package_name") != "phonolite") {
    throw std::runtime_error("Unsupported update schema, channel or package identity.");
  }
  const auto published = integer_value(root, "published_at");
  const auto expires = integer_value(root, "expires_at");
  if (published > now + 300 || expires <= now || expires <= published || expires - published > 366 * 86400) {
    throw std::runtime_error("Update metadata is expired or has invalid publication times.");
  }

  Manifest result;
  result.version = string_value(root, "version");
  result.revision = integer_value(root, "revision");
  const std::string package_version = result.version + "-" + std::to_string(result.revision);
  Version::parse(package_version);
  result.notes_url = string_value(root, "notes_url");
  check_url(result.notes_url);
  JsonArray* assets = array_value(root, "assets");
  if (json_array_get_length(assets) == 0 || json_array_get_length(assets) > 128) {
    throw std::runtime_error("Invalid update asset count.");
  }

  std::set<std::string> targets;
  for (guint index = 0; index < json_array_get_length(assets); ++index) {
    JsonNode* node = json_array_get_element(assets, index);
    if (!JSON_NODE_HOLDS_OBJECT(node)) {
      throw std::runtime_error("Invalid update asset.");
    }
    JsonObject* item = json_node_get_object(node);
    Asset asset;
    asset.target = string_value(item, "target");
    asset.format = string_value(item, "format");
    asset.architecture = string_value(item, "architecture");
    asset.package_version = string_value(item, "package_version");
    asset.url = string_value(item, "url");
    asset.sha256 = string_value(item, "sha256");
    asset.length = integer_value(item, "length");
    if (!std::regex_match(asset.target, std::regex("[a-z0-9][a-z0-9.-]{0,95}")) ||
        !targets.insert(asset.target).second || asset.architecture != "amd64" ||
        (asset.format != "deb" && asset.format != "rpm" && asset.format != "archlinux") ||
        asset.package_version != package_version || !std::regex_match(asset.sha256, std::regex("[a-f0-9]{64}")) ||
        asset.length == 0 || asset.length > 2147483648ULL) {
      throw std::runtime_error("Invalid or duplicate update target, version, digest or package length.");
    }
    check_url(asset.url);
    result.assets.push_back(std::move(asset));
  }

  return result;
}

Asset ManifestVerifier::select(const Manifest& manifest, const Installation& installation) {
  if (!installation.managed) {
    throw std::runtime_error("This installation is not managed by the Phonolite updater.");
  }

  for (const auto& asset : manifest.assets) {
    if (asset.target == installation.target && asset.format == installation.format &&
        asset.architecture == installation.architecture) {
      return asset;
    }
  }

  throw std::runtime_error("This release has no package for the installed target.");
}

std::string ManifestVerifier::asset_json(const Asset& asset, const Manifest& manifest) {
  return "{\"version\":" + json_string(manifest.version) +
         ",\"package_version\":" + json_string(asset.package_version) + ",\"target\":" + json_string(asset.target) +
         ",\"format\":" + json_string(asset.format) + ",\"architecture\":" + json_string(asset.architecture) +
         ",\"url\":" + json_string(asset.url) + ",\"sha256\":" + json_string(asset.sha256) +
         ",\"length\":" + std::to_string(asset.length) + ",\"notes_url\":" + json_string(manifest.notes_url) + "}";
}

} // namespace updates
} // namespace phonolite
