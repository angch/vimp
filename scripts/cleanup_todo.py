#!/usr/bin/env python3
import sys
import os

class Node:
    def __init__(self, line, level=-1, type='text'):
        self.line = line
        self.level = level # 1 for #, 2 for ##, etc. 0 for root, -1 for text/items
        self.type = type # 'root', 'header', 'task_done', 'task_todo', 'text', 'separator'
        self.children = []

    def add_child(self, node):
        self.children.append(node)

def parse_markdown(filepath):
    if not os.path.exists(filepath):
        return Node("", level=0, type='root')

    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    root = Node("", level=0, type='root')
    stack = [root]

    for line in lines:
        sline = line.strip()

        # Determine type and level
        if sline.startswith('#'):
            level = len(sline.split(' ')[0])
            node = Node(line, level=level, type='header')

            # Pop stack until parent level is strictly less than current level
            while stack[-1].level >= level:
                stack.pop()

            stack[-1].add_child(node)
            stack.append(node)

        elif sline.startswith('- [x]'):
            node = Node(line, type='task_done')
            stack[-1].add_child(node)
        elif sline.startswith('- [ ]'):
            node = Node(line, type='task_todo')
            stack[-1].add_child(node)
        elif sline.startswith('---'):
            node = Node(line, type='separator')
            stack[-1].add_child(node)
        else:
            # Text or blank
            node = Node(line, type='text')
            stack[-1].add_child(node)

    return root

def merge_trees(base_node, new_node):
    # Merge new_node children into base_node
    # We want to maintain order of base_node, and append new stuff?
    # Or merge into appropriate sections.

    for new_child in new_node.children:
        found = False
        for base_child in base_node.children:
            # Match headers strictly. Match items?
            # If it's a header, we merge.
            # If it's an item, we append (unless duplicate?).
            # Let's assume strict equality for identification.
            if base_child.type == new_child.type and base_child.line.strip() == new_child.line.strip():
                if base_child.type == 'header':
                    merge_trees(base_child, new_child)
                    found = True
                    break
                # For tasks/text, we might allow duplicates or not.
                # Assuming history is append-only, duplicates shouldn't happen unless we re-run on same data.
                # But since we strip [x] from TODO, we won't re-run on same data.
                # So we can just check existence to avoid duplication if user manually edits?
                # Let's simple append for non-headers if not exact match.
                # Actually, simpler: if exact line match, assume it's the same item and don't duplicate.
                elif base_child.type == new_child.type: # task or text
                    found = True
                    break

        if not found:
            base_node.children.append(new_child)

def filter_history(node):
    if node.type == 'task_done':
        # Transform to bullet
        new_line = node.line.replace('- [x]', '-')
        return Node(new_line, node.level, node.type)

    if node.type == 'task_todo':
        return None
    if node.type == 'text' or node.type == 'separator':
        # Skip text in history
        return None

    # Header or Root
    new_children = []
    for child in node.children:
        res = filter_history(child)
        if res:
            new_children.append(res)

    if new_children:
        new_node = Node(node.line, node.level, node.type)
        new_node.children = new_children
        return new_node
    return None

def filter_todo(node):
    if node.type == 'task_done':
        return None
    if node.type == 'task_todo':
        return Node(node.line, node.level, node.type)
    if node.type == 'text' or node.type == 'separator':
        return Node(node.line, node.level, node.type)

    # Header or Root
    new_children = []
    for child in node.children:
        res = filter_todo(child)
        if res:
            new_children.append(res)

    # Pruning: Remove headers that only contain meaningless text (whitespace or separators)

    meaningful_children = False
    for child in new_children:
        if child.type == 'task_todo':
            meaningful_children = True
            break
        if child.type == 'header':
            meaningful_children = True # If header kept, it must be meaningful (recursive)
            break
        if child.type == 'text':
             if child.line.strip():
                 meaningful_children = True
                 break
        # Separators are NOT meaningful on their own for keeping a header.
        # But if we keep the header, we keep the separators attached to it.

    if meaningful_children:
        new_node = Node(node.line, node.level, node.type)
        new_node.children = new_children
        return new_node

    return None

def flatten_tree(node):
    lines = []
    if node.type != 'root':
        lines.append(node.line)
    for child in node.children:
        lines.extend(flatten_tree(child))
    return lines

def count_todos(node):
    count = 0
    if node.type == 'task_todo':
        count = 1
    for child in node.children:
        count += count_todos(child)
    return count

def main():
    todo_path = 'TODO.md'
    history_path = 'archived/HISTORY.md'

    # Ensure archived directory exists
    os.makedirs(os.path.dirname(history_path), exist_ok=True)

    root = parse_markdown(todo_path)

    # Extract new history from TODO
    new_history_root = filter_history(root)

    # Load existing history
    existing_history_root = parse_markdown(history_path)

    # Merge if there is something to merge
    if new_history_root:
        # If existing history is empty/new, use new root directly (but check title)
        if not existing_history_root.children:
             existing_history_root = new_history_root
        else:
            merge_trees(existing_history_root, new_history_root)

    # Filter TODO
    todo_root = filter_todo(root)

    # Fix History Title logic
    # If root has no title, or we want to ensure a specific title.
    # Check if first child is a header with "History"
    # Or if it's "TODO.md".
    if existing_history_root.children:
        first = existing_history_root.children[0]
        if first.type == 'header' and 'TODO.md' in first.line:
            first.line = '# Project History\n'

    history_lines = flatten_tree(existing_history_root)
    todo_lines = flatten_tree(todo_root) if todo_root else []

    with open(history_path, 'w', encoding='utf-8') as f:
        f.writelines(history_lines)

    with open(todo_path, 'w', encoding='utf-8') as f:
        f.writelines(todo_lines)

    remaining = count_todos(todo_root) if todo_root else 0
    print(f"Cleanup complete.")
    print(f"History written to {history_path} ({len(history_lines)} lines)")
    print(f"TODO updated {todo_path} ({len(todo_lines)} lines)")
    print(f"Remaining items: {remaining}")

if __name__ == "__main__":
    main()
