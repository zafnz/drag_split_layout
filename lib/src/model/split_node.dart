import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Represents the axis direction for a split.
///
/// Used to specify whether child nodes should be arranged
/// horizontally (side by side) or vertically (stacked).
enum SplitAxis {
  /// Children are arranged horizontally (side by side).
  horizontal,

  /// Children are arranged vertically (stacked top to bottom).
  vertical;

  /// Converts to MultiSplitView's Axis
  Axis toAxis() => this == horizontal ? Axis.horizontal : Axis.vertical;

  /// Creates from MultiSplitView's Axis
  static SplitAxis fromAxis(Axis axis) =>
      axis == Axis.horizontal ? horizontal : vertical;
}

/// Represents a node in the split layout tree.
///
/// A node can either be a leaf (containing a widget) or a branch
/// (containing child nodes arranged in a split view).
@immutable
class SplitNode {
  /// Creates a leaf node containing a single widget.
  const SplitNode.leaf({
    required this.id,
    required this.widgetBuilder,
    this.flex = 1.0,
  })  : axis = null,
        children = const [],
        _isLeaf = true;

  /// Creates a branch node containing multiple child nodes.
  const SplitNode.branch({
    required this.id,
    required this.axis,
    required this.children,
    this.flex = 1.0,
  })  : widgetBuilder = null,
        _isLeaf = false;

  /// Unique identifier for this node
  final String id;

  /// The axis along which children are arranged (null for leaf nodes)
  final SplitAxis? axis;

  /// Child nodes (empty for leaf nodes)
  final List<SplitNode> children;

  /// Builder function for the widget content (null for branch nodes)
  final Widget Function(BuildContext context)? widgetBuilder;

  /// The flex weight for this node in its parent's layout
  final double flex;

  final bool _isLeaf;

  /// Whether this is a leaf node (contains a widget, not children)
  bool get isLeaf => _isLeaf;

  /// Whether this is a branch node (contains children)
  bool get isBranch => !_isLeaf;

  /// Returns the path to a node with the given id, or null if not found.
  /// The path is a list of indices representing the traversal path.
  List<int>? findPath(String nodeId) {
    if (id == nodeId) return [];

    for (var i = 0; i < children.length; i++) {
      final childPath = children[i].findPath(nodeId);
      if (childPath != null) {
        return [i, ...childPath];
      }
    }
    return null;
  }

  /// Returns the node at the given path, or null if the path is invalid.
  SplitNode? nodeAtPath(List<int> path) {
    if (path.isEmpty) return this;

    final index = path.first;
    if (index < 0 || index >= children.length) return null;

    return children[index].nodeAtPath(path.sublist(1));
  }

  /// Creates a copy of this node with the specified changes.
  SplitNode copyWith({
    String? id,
    SplitAxis? axis,
    List<SplitNode>? children,
    Widget Function(BuildContext context)? widgetBuilder,
    double? flex,
  }) {
    if (_isLeaf) {
      return SplitNode.leaf(
        id: id ?? this.id,
        widgetBuilder: widgetBuilder ?? this.widgetBuilder!,
        flex: flex ?? this.flex,
      );
    } else {
      return SplitNode.branch(
        id: id ?? this.id,
        axis: axis ?? this.axis!,
        children: children ?? this.children,
        flex: flex ?? this.flex,
      );
    }
  }

  /// Creates a new tree with the node at the given path replaced.
  SplitNode replaceAtPath(List<int> path, SplitNode newNode) {
    if (path.isEmpty) return newNode;

    final index = path.first;
    if (index < 0 || index >= children.length) return this;

    final newChildren = List<SplitNode>.from(children);
    newChildren[index] = children[index].replaceAtPath(path.sublist(1), newNode);

    return copyWith(children: newChildren);
  }

  /// Creates a new tree with a node inserted at the given path and index.
  SplitNode insertAtPath(List<int> path, int insertIndex, SplitNode newNode) {
    if (path.isEmpty) {
      if (isBranch) {
        final newChildren = List<SplitNode>.from(children);
        final clampedIndex = insertIndex.clamp(0, newChildren.length);
        newChildren.insert(clampedIndex, newNode);
        return copyWith(children: newChildren);
      }
      return this;
    }

    final index = path.first;
    if (index < 0 || index >= children.length) return this;

    final newChildren = List<SplitNode>.from(children);
    newChildren[index] =
        children[index].insertAtPath(path.sublist(1), insertIndex, newNode);

    return copyWith(children: newChildren);
  }

  /// Creates a new tree with the node at the given path removed.
  SplitNode? removeAtPath(List<int> path) {
    if (path.isEmpty) return null;

    final index = path.first;
    if (index < 0 || index >= children.length) return this;

    if (path.length == 1) {
      final newChildren = List<SplitNode>.from(children)..removeAt(index);

      // If only one child remains, collapse the branch
      if (newChildren.length == 1) {
        return newChildren.first.copyWith(flex: flex);
      }

      return copyWith(children: newChildren);
    }

    final newChildren = List<SplitNode>.from(children);
    final updatedChild = children[index].removeAtPath(path.sublist(1));

    if (updatedChild == null) {
      newChildren.removeAt(index);
      if (newChildren.length == 1) {
        return newChildren.first.copyWith(flex: flex);
      }
    } else {
      newChildren[index] = updatedChild;
    }

    return copyWith(children: newChildren);
  }

  /// Wraps the node at the given path in a new branch with the specified axis.
  SplitNode wrapInBranch(
    List<int> path,
    SplitAxis newAxis,
    SplitNode newSibling,
    bool insertBefore,
  ) {
    final targetNode = nodeAtPath(path);
    if (targetNode == null) return this;

    final wrappedChildren = insertBefore
        ? [newSibling, targetNode.copyWith(flex: 1)]
        : [targetNode.copyWith(flex: 1), newSibling];

    final wrapper = SplitNode.branch(
      id: 'branch_${DateTime.now().microsecondsSinceEpoch}',
      axis: newAxis,
      children: wrappedChildren,
      flex: targetNode.flex,
    );

    return replaceAtPath(path, wrapper);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitNode &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          axis == other.axis &&
          flex == other.flex &&
          _isLeaf == other._isLeaf &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(id, axis, flex, _isLeaf, Object.hashAll(children));

  /// Converts this node to a JSON-serializable map.
  ///
  /// For leaf nodes, returns `{id, flex}`.
  /// For branch nodes, returns `{id, axis, flex, children}`.
  ///
  /// Note: The [widgetBuilder] is not serialized. When deserializing,
  /// use [fromJson] with a widget builder resolver.
  Map<String, dynamic> toJson() {
    if (isLeaf) {
      return {
        'id': id,
        'flex': flex,
      };
    }
    return {
      'id': id,
      'axis': axis!.name,
      'flex': flex,
      'children': children.map((c) => c.toJson()).toList(),
    };
  }

  /// Creates a [SplitNode] from a JSON map.
  ///
  /// The [widgetBuilderResolver] is called for each leaf node to provide
  /// the widget builder based on the node's id.
  ///
  /// Returns null if the JSON is invalid.
  static SplitNode? fromJson(
    Map<String, dynamic> json,
    Widget Function(BuildContext)? Function(String id) widgetBuilderResolver,
  ) {
    final id = json['id'] as String?;
    if (id == null) return null;

    final flex = (json['flex'] as num?)?.toDouble() ?? 1.0;
    final axisStr = json['axis'] as String?;
    final childrenJson = json['children'] as List<dynamic>?;

    // If has axis and children, it's a branch
    if (axisStr != null && childrenJson != null) {
      final axis = SplitAxis.values.where((a) => a.name == axisStr).firstOrNull;
      if (axis == null) return null;

      final children = <SplitNode>[];
      for (final childJson in childrenJson) {
        if (childJson is! Map<String, dynamic>) return null;
        final child = fromJson(childJson, widgetBuilderResolver);
        if (child == null) return null;
        children.add(child);
      }

      if (children.isEmpty) return null;

      return SplitNode.branch(
        id: id,
        axis: axis,
        children: children,
        flex: flex,
      );
    }

    // Otherwise it's a leaf
    final widgetBuilder = widgetBuilderResolver(id);
    if (widgetBuilder == null) return null;

    return SplitNode.leaf(
      id: id,
      widgetBuilder: widgetBuilder,
      flex: flex,
    );
  }

  @override
  String toString() {
    if (isLeaf) {
      return 'SplitNode.leaf(id: $id, flex: $flex)';
    }
    return 'SplitNode.branch(id: $id, axis: $axis, flex: $flex, '
        'children: $children)';
  }
}
