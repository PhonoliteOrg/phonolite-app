#include <algorithm>
#include <fstream>
#include <iostream>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include "ax/ax_node.h"
#include "ax/ax_tree.h"
#include "ax/ax_tree_update.h"

ui::AXNodeData node(int id, std::vector<int> children = {}) {
  ui::AXNodeData data;
  data.id = id;
  data.role = ax::mojom::Role::kGenericContainer;
  data.child_ids = std::move(children);
  return data;
}

bool run(bool include_descendant) {
  ui::AXTree tree;
  ui::AXTreeUpdate initial;
  initial.root_id = 0;
  initial.nodes = {node(0, {1, 2}), node(1, {3}), node(3, {31}), node(31), node(2)};
  if (!tree.Unserialize(initial)) {
    std::cerr << "Initial update failed: " << tree.error() << '\n';
    return false;
  }

  ui::AXTreeUpdate remove;
  remove.nodes = {node(1)};
  if (!tree.Unserialize(remove)) {
    std::cerr << "Removal failed: " << tree.error() << '\n';
    return false;
  }

  ui::AXTreeUpdate update;
  update.nodes = {node(1), node(2, {3}), node(3, {31})};
  if (include_descendant) update.nodes.push_back(node(31));
  bool success = tree.Unserialize(update);
  std::cout << (include_descendant ? "Complete subtree" : "Missing unchanged descendant")
            << ": " << (success ? "PASS" : tree.error()) << '\n';
  return success;
}

// Replays the structural operations in AccessibilityBridge::CommitUpdates.
// Input is R to reset a tree, or B N followed by N records: id child_count ids...
class BridgeReplay {
 public:
  BridgeReplay() { reset(); }

  void reset() {
    tree_ = std::make_unique<ui::AXTree>();
    batch_ = 0;
  }

  bool commit(const std::vector<ui::AXNodeData>& nodes) {
    batch_++;
    if (nodes.empty()) return true;
    std::unordered_map<int32_t, ui::AXNodeData> pending;
    for (const auto& data : nodes) pending[data.id] = data;

    std::unordered_map<int32_t, ui::AXNodeData> removals;
    for (const auto& entry : pending) {
      for (int child_id : entry.second.child_ids) {
        ui::AXNode* child = tree_->GetFromId(child_id);
        if (!child) continue;
        if (!child->parent()) {
          std::cerr << "Cannot reparent the root node " << child_id << '\n';
          return false;
        }
        if (child->parent()->id() == entry.first) continue;
        if (!pending.contains(child_id)) {
          std::cerr << "Batch " << batch_ << ": reparented node " << child_id
                    << " has no corresponding pending update (debug assertion)\n";
          // Shipped engines compile out this assertion and continue to AXTree.
        }
        int parent_id = child->parent()->id();
        if (!removals.contains(parent_id)) removals[parent_id] = tree_->GetFromId(parent_id)->data();
        auto& children = removals[parent_id].child_ids;
        const auto at = std::find(children.begin(), children.end(), child_id);
        if (at != children.end()) children.erase(at);
      }
    }
    if (!removals.empty()) {
      ui::AXTreeUpdate remove;
      for (auto& entry : removals) remove.nodes.push_back(std::move(entry.second));
      if (!tree_->Unserialize(remove)) return failure("remove reparented nodes", remove);
    }

    std::vector<std::vector<ui::AXNodeData>> results;
    while (!pending.empty()) {
      const auto begin = pending.begin();
      std::vector<ui::AXNodeData> subtree;
      flatten(begin->second, pending, subtree);
      results.push_back(std::move(subtree));
      pending.erase(begin);
    }
    ui::AXTreeUpdate update;
    for (size_t i = results.size(); i > 0; i--) {
      for (const auto& data : results[i - 1]) update.nodes.push_back(data);
    }
    if (!results.empty() && tree_->root()->id() == ui::AXNode::kInvalidAXID) {
      update.root_id = results.back().front().id;
    }
    if (!tree_->Unserialize(update)) return failure("main update", update);
    return true;
  }

 private:
  std::unique_ptr<ui::AXTree> tree_;
  int batch_ = 0;

  static void flatten(const ui::AXNodeData& target,
                      std::unordered_map<int32_t, ui::AXNodeData>& pending,
                      std::vector<ui::AXNodeData>& result) {
    result.push_back(target);
    for (int child_id : target.child_ids) {
      auto child = pending.find(child_id);
      if (child == pending.end()) continue;
      const auto data = child->second;
      flatten(data, pending, result);
      pending.erase(child);
    }
  }

  bool failure(const char* phase, const ui::AXTreeUpdate& update) {
    std::cerr << "Batch " << batch_ << " (" << phase << "): " << tree_->error() << '\n';
    std::cerr << update.ToString();
    return false;
  }
};

int replay(std::istream& input) {
  BridgeReplay bridge;
  std::string command;
  int batches = 0;
  while (input >> command) {
    if (command == "R") {
      bridge.reset();
      continue;
    }
    if (command != "B") {
      std::cerr << "Expected R or B, received " << command << '\n';
      return 2;
    }
    size_t count;
    if (!(input >> count) || count > 100000) return 2;
    std::vector<ui::AXNodeData> nodes;
    for (size_t i = 0; i < count; i++) {
      int id;
      size_t children_count;
      if (!(input >> id >> children_count) || id < 0 || children_count > 100000) return 2;
      std::vector<int> children(children_count);
      for (int& child : children) input >> child;
      nodes.push_back(node(id, std::move(children)));
    }
    if (!input || !bridge.commit(nodes)) return 1;
    batches++;
  }
  std::cout << "Native AXTree replay passed " << batches << " batches\n";
  return 0;
}

int main(int argc, char** argv) {
  if (argc == 2) {
    std::ifstream input(argv[1]);
    if (!input) return 2;
    return replay(input);
  }
  const bool incomplete = run(false);
  const bool complete = run(true);
  return !incomplete && complete ? 0 : 1;
}
