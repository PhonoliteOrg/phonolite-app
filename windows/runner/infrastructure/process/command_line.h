#ifndef RUNNER_INFRASTRUCTURE_PROCESS_COMMAND_LINE_H_
#define RUNNER_INFRASTRUCTURE_PROCESS_COMMAND_LINE_H_

#include <string>
#include <vector>

// Returns UTF-8 arguments without the executable name, or an empty list on failure.
std::vector<std::string> get_command_line_arguments();

#endif // RUNNER_INFRASTRUCTURE_PROCESS_COMMAND_LINE_H_
