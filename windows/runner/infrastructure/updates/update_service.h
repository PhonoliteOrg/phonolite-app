#ifndef RUNNER_INFRASTRUCTURE_UPDATES_UPDATE_SERVICE_H_
#define RUNNER_INFRASTRUCTURE_UPDATES_UPDATE_SERVICE_H_

#include <string>

class UpdateService {
 public:
  virtual ~UpdateService() = default;

  virtual bool initialize() = 0;
  virtual std::string feed_url() const = 0;
  virtual std::string current_version() const = 0;
  virtual std::string public_key() const = 0;
  // Lock the candidate against replacement and validate its embedded version.
  virtual unsigned long stage_update(const std::wstring& path, const std::string& version) = 0;
  // Returns zero only after the staged silent installer process has been created.
  virtual unsigned long install_update() = 0;
  virtual void release_update() = 0;
  virtual void cleanup() = 0;
};

#endif // RUNNER_INFRASTRUCTURE_UPDATES_UPDATE_SERVICE_H_
