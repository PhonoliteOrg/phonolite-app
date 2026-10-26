#ifndef RUNNER_INFRASTRUCTURE_UPDATES_UPDATE_SERVICE_H_
#define RUNNER_INFRASTRUCTURE_UPDATES_UPDATE_SERVICE_H_

#include <string>

class UpdateService {
 public:
  virtual ~UpdateService() = default;

  virtual bool initialize() = 0;
  virtual std::string feed_url() const = 0;
  virtual std::string current_version() const = 0;
  virtual void show_update() = 0;
  virtual void cleanup() = 0;
};

#endif // RUNNER_INFRASTRUCTURE_UPDATES_UPDATE_SERVICE_H_
