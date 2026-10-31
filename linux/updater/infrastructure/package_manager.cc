#include "infrastructure/package_manager.h"

#include <sstream>
#include <stdexcept>
#include <utility>

namespace phonolite {
namespace updates {
namespace {

std::string trim(std::string value) {
  const auto first = value.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) {
    return "";
  }

  return value.substr(first, value.find_last_not_of(" \t\r\n") - first + 1);
}

std::string field(const std::string& output, const std::string& name) {
  std::istringstream input(output);
  std::string line;
  while (std::getline(input, line)) {
    const auto colon = line.find(':');
    if (colon != std::string::npos && trim(line.substr(0, colon)) == name) {
      return trim(line.substr(colon + 1));
    }
  }

  throw std::runtime_error("Missing native package field: " + name);
}

} // namespace

PackageManager::PackageManager(std::string format, Runner runner)
    : format_(std::move(format)), runner_(std::move(runner)) {
  if (format_ != "deb" && format_ != "rpm" && format_ != "archlinux") {
    throw std::runtime_error("Unsupported native package manager.");
  }
}

std::string PackageManager::command(const std::vector<std::string>& arguments, unsigned timeout) const {
  auto result = runner_(arguments, timeout);
  if (result.exit_code != 0) {
    throw std::runtime_error("The package manager could not complete the operation. " + result.error + result.output);
  }

  return trim(result.output);
}

void PackageManager::verify_installed(const Installation& installation, const std::string& executable) const {
  std::string identity;
  if (format_ == "deb") {
    const std::string owner = command({"/usr/bin/dpkg-query", "-S", executable});
    if (owner != "phonolite: " + executable) {
      throw std::runtime_error("The running executable is not owned by the Phonolite package.");
    }
    identity = command(
        {"/usr/bin/dpkg-query", "-W", "-f=${Package}\t${Version}\t${Architecture}\t${db:Status-Status}", "phonolite"});
    if (identity != "phonolite\t" + installation.package_version + "\tamd64\tinstalled") {
      throw std::runtime_error("Installed Debian package metadata does not match this application.");
    }
  } else if (format_ == "rpm") {
    identity = command({"/usr/bin/rpm", "-qf", "--qf", "%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}", executable});
    if (identity != "phonolite\t" + installation.package_version + "\tx86_64") {
      throw std::runtime_error("Installed RPM package metadata does not match this application.");
    }
  } else {
    if (command({"/usr/bin/pacman", "-Qoq", executable}) != "phonolite" ||
        command({"/usr/bin/pacman", "-Q", "phonolite"}) != "phonolite " + installation.package_version) {
      throw std::runtime_error("Installed Arch package metadata does not match this application.");
    }
  }
}

void PackageManager::verify_candidate(const Asset& asset, const std::string& path) const {
  std::string identity;
  if (format_ == "deb") {
    if (command({"/usr/bin/dpkg-deb", "-f", path, "Package"}) != "phonolite" ||
        command({"/usr/bin/dpkg-deb", "-f", path, "Version"}) != asset.package_version ||
        command({"/usr/bin/dpkg-deb", "-f", path, "Architecture"}) != "amd64") {
      throw std::runtime_error("Downloaded Debian package identity does not match its signed manifest.");
    }
  } else if (format_ == "rpm") {
    const auto signature = command({"/usr/bin/rpm", "--checksig", "--verbose", path});
    if (signature.find("Signature") == std::string::npos || signature.find(": OK") == std::string::npos ||
        signature.find("NOKEY") != std::string::npos || signature.find("NOT OK") != std::string::npos) {
      throw std::runtime_error("A trusted native RPM signature is required.");
    }
    identity = command({"/usr/bin/rpm", "-qp", "--qf", "%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}", path});
    if (identity != "phonolite\t" + asset.package_version + "\tx86_64") {
      throw std::runtime_error("Downloaded RPM identity does not match its signed manifest.");
    }
  } else {
    command({"/usr/bin/pacman-key", "--verify", path + ".sig", path});
    identity = command({"/usr/bin/pacman", "-Qip", path});
    if (field(identity, "Conflicts With") != "None" || field(identity, "Replaces") != "None") {
      throw std::runtime_error("The Arch package requests conflicts or replacements outside this update.");
    }
    if (field(identity, "Name") != "phonolite" || field(identity, "Version") != asset.package_version ||
        field(identity, "Architecture") != "x86_64") {
      throw std::runtime_error("Downloaded Arch identity does not match its signed manifest.");
    }
  }
}

void PackageManager::preflight(const std::string& path) const {
  if (format_ == "deb") {
    command({"/usr/bin/apt-get", "--simulate", "--no-remove", "install", path});
  } else if (format_ == "rpm") {
    command({"/usr/bin/rpm", "-U", "--test", path});
  } else {
    // No repository refresh is performed: unmet dependencies require a normal
    // full system upgrade, never a forced or partial system upgrade here.
    const auto dependencies = command({"/usr/bin/pacman", "-Up", "--print-format", "%D", path});
    std::istringstream input(dependencies);
    std::string dependency;
    std::vector<std::string> check{"/usr/bin/pacman", "-T"};
    while (input >> dependency) {
      if (dependency != "None")
        check.push_back(dependency);
    }
    if (check.size() > 2) {
      try {
        command(check);
      } catch (const std::exception&) {
        throw std::runtime_error(
            "Arch dependencies are not satisfied. Complete normal full system maintenance before updating Phonolite.");
      }
    }
    if (command({"/usr/bin/pacman", "-Up", "--print-format", "%n", path}) != "phonolite") {
      throw std::runtime_error("The Arch transaction would affect an unexpected package.");
    }
  }
}

std::vector<std::string> PackageManager::install_arguments(const std::string& path) const {
  if (format_ == "deb") {
    return {"/usr/bin/apt-get", "-y", "--no-remove", "install", path};
  }
  if (format_ == "rpm") {
    return {"/usr/bin/dnf", "-y", "--setopt=localpkg_gpgcheck=1", "install", path};
  }

  return {"/usr/bin/pacman", "-U", "--noconfirm", path};
}

void PackageManager::install(const std::string& path) const {
  // Never kill a native transaction while it may be changing package state.
  // Query/preflight commands retain deadlines; committed installs own completion.
  command(install_arguments(path), 0);
}

} // namespace updates
} // namespace phonolite
