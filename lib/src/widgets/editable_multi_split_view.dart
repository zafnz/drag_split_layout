import 'package:drag_split_layout/src/controller/split_layout_controller.dart';
import 'package:drag_split_layout/src/model/drag_item_model.dart';
import 'package:drag_split_layout/src/model/drop_preview_model.dart';
import 'package:drag_split_layout/src/model/split_node.dart';
import 'package:drag_split_layout/src/widgets/draggable_split_pane.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:multi_split_view/multi_split_view.dart';

/// Configuration for the editable multi split view.
class EditableMultiSplitViewConfig {
  /// Creates a new configuration.
  const EditableMultiSplitViewConfig({
    this.dividerThickness = 8.0,
    this.dividerHandleBuffer = 0.0,
    this.dividerPainter,
    this.antiAliasingWorkaround = true,
    this.paneConfig = const DraggablePaneConfig(),
  });

  /// The visual thickness of dividers between panes.
  final double dividerThickness;

  /// Additional clickable area around the divider.
  ///
  /// This allows having a thin visual divider but a larger draggable area.
  /// For example, with dividerThickness=2 and dividerHandleBuffer=4,
  /// the visual divider is 2px but the draggable area is 10px (2 + 4*2).
  final double dividerHandleBuffer;

  /// Custom divider painter. If null, uses default styling.
  final DividerPainter? dividerPainter;

  /// Whether to enable the anti-aliasing workaround for smooth rendering.
  final bool antiAliasingWorkaround;

  /// Configuration for draggable panes.
  final DraggablePaneConfig paneConfig;
}

/// A widget that renders a [SplitNode] tree using [MultiSplitView]
/// with full drag-and-drop editing capabilities.
///
/// This is the main widget for creating an editable split layout.
/// It recursively builds the layout tree and wraps each leaf node
/// in a [DraggableSplitPane] for drag-and-drop support.
class EditableMultiSplitView extends StatefulWidget {
  /// Creates a new editable multi split view.
  const EditableMultiSplitView({
    required this.controller, super.key,
    this.config = const EditableMultiSplitViewConfig(),
    this.widgetTypeResolver,
    this.onNodeDropped,
    this.onDividerDragEnd,
  });

  /// The controller managing the layout tree.
  final SplitLayoutController controller;

  /// Configuration for the split view appearance and behavior.
  final EditableMultiSplitViewConfig config;

  /// Resolves the widget type string for a node.
  /// If null, defaults to 'pane'.
  final String Function(SplitNode node)? widgetTypeResolver;

  /// Optional callback when a node is dropped.
  /// Return a new node to customize the drop behavior, or null to use default.
  final SplitNode? Function(
    DragItemModel draggedItem,
    DropPreviewModel preview,
    SplitNode targetNode,
  )? onNodeDropped;

  /// Called after a divider drag ends and flex values have been synced
  /// back to the [SplitNode] tree.
  final VoidCallback? onDividerDragEnd;

  @override
  State<EditableMultiSplitView> createState() => _EditableMultiSplitViewState();
}

class _EditableMultiSplitViewState extends State<EditableMultiSplitView> {
  final Map<String, MultiSplitViewController> _controllers = {};
  Set<String> _usedControllerIds = {};

  /// Controllers evicted due to tree restructuring, awaiting disposal.
  ///
  /// These cannot be disposed immediately because old [MultiSplitView] widgets
  /// still reference them until Flutter's element lifecycle calls `deactivate`.
  final List<MultiSplitViewController> _orphanedControllers = [];

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final controller in _orphanedControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _cleanupControllers() {
    // Dispose orphaned controllers from previous tree restructures
    for (final controller in _orphanedControllers) {
      controller.dispose();
    }
    _orphanedControllers.clear();

    // Dispose controllers no longer referenced by any branch node
    final unusedIds = _controllers.keys.where((id) => !_usedControllerIds.contains(id)).toList();
    for (final id in unusedIds) {
      _controllers[id]?.dispose();
      _controllers.remove(id);
    }
  }

  /// Evicts all cached controllers when the tree's branch structure changes.
  ///
  /// During drag operations, multiple `notifyListeners` calls can fire in the
  /// same frame (e.g. `removeNode` then `updateRootNode`). The old
  /// [MultiSplitView] widgets haven't been deactivated yet, so their
  /// controllers still have a `_stateHashCode` set. Reusing those controllers
  /// for new [MultiSplitView] instances triggers a "shared controller" error.
  ///
  /// By evicting all controllers when branch IDs change, we force fresh
  /// controllers to be created for the new tree structure.
  void _evictControllersIfTreeChanged(SplitNode rootNode) {
    final currentBranchIds = _collectBranchIds(rootNode);
    if (!setEquals(currentBranchIds, _controllers.keys.toSet())) {
      _orphanedControllers.addAll(_controllers.values);
      _controllers.clear();
    }
  }

  /// Collects all branch node IDs from the tree.
  Set<String> _collectBranchIds(SplitNode node) {
    final ids = <String>{};
    if (node.isBranch) {
      ids.add(node.id);
      for (final child in node.children) {
        ids.addAll(_collectBranchIds(child));
      }
    }
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        _usedControllerIds = {};
        _evictControllersIfTreeChanged(widget.controller.rootNode);
        final result = _buildNode(widget.controller.rootNode, []);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _cleanupControllers();
          }
        });
        return result;
      },
    );
  }

  Widget _buildNode(SplitNode node, List<int> path) {
    if (node.isLeaf) {
      return _buildLeafNode(node, path);
    } else {
      return _buildBranchNode(node, path);
    }
  }

  Widget _buildLeafNode(SplitNode node, List<int> path) {
    final widgetType = widget.widgetTypeResolver?.call(node) ?? 'pane';

    final childWidget = node.widgetBuilder?.call(context) ??
        Container(
          color: Colors.grey[200],
          child: Center(
            child: Text('Pane: ${node.id}'),
          ),
        );

    return DraggableSplitPane(
      nodeId: node.id,
      nodePath: path,
      widgetType: widgetType,
      controller: widget.controller,
      config: widget.config.paneConfig,
      onDrop: widget.onNodeDropped != null
          ? (draggedItem, preview) {
              return widget.onNodeDropped!(draggedItem, preview, node);
            }
          : null,
      child: childWidget,
    );
  }

  Widget _buildBranchNode(SplitNode node, List<int> path) {
    // Get or create controller for this branch
    final controller = _getOrCreateController(node);

    // Calculate areas from flex values
    final areas = node.children.map((child) {
      return Area(flex: child.flex);
    }).toList();

    // Update controller areas if they don't match
    if (controller.areas.length != areas.length) {
      controller.areas = areas;
    }

    final splitView = MultiSplitView(
      key: ValueKey('msv_${node.id}'),
      controller: controller,
      axis: node.axis!.toAxis(),
      dividerBuilder: (
        axis,
        index,
        resizable,
        dragging,
        highlighted,
        themeData,
      ) {
        return _buildDivider(
          context,
          axis,
          resizable,
          dragging,
          highlighted,
        );
      },
      onDividerDragEnd: widget.onDividerDragEnd != null
          ? (_) {
              widget.controller.syncFlexValues(
                node.id,
                controller.areas,
              );
              widget.onDividerDragEnd!();
            }
          : null,
      antiAliasingWorkaround: widget.config.antiAliasingWorkaround,
      builder: (context, area) {
        // Find the index of this area in the controller
        final index = controller.areas.indexOf(area);
        if (index < 0 || index >= node.children.length) {
          return const SizedBox.shrink();
        }
        final childPath = [...path, index];
        return _buildNode(node.children[index], childPath);
      },
    );

    // Wrap with theme if we need a handle buffer
    if (widget.config.dividerHandleBuffer > 0) {
      return MultiSplitViewTheme(
        data: MultiSplitViewThemeData(
          dividerThickness: widget.config.dividerThickness,
          dividerHandleBuffer: widget.config.dividerHandleBuffer,
        ),
        child: splitView,
      );
    }

    return splitView;
  }

  MultiSplitViewController _getOrCreateController(SplitNode node) {
    // Mark this controller as used in the current build
    _usedControllerIds.add(node.id);

    if (!_controllers.containsKey(node.id)) {
      final areas = node.children.map((child) {
        return Area(flex: child.flex);
      }).toList();

      _controllers[node.id] = MultiSplitViewController(areas: areas);
    }
    return _controllers[node.id]!;
  }

  Widget _buildDivider(
    BuildContext context,
    Axis axis,
    bool resizable,
    bool dragging,
    bool highlighted,
  ) {
    final theme = Theme.of(context);
    final color = dragging || highlighted
        ? theme.colorScheme.primary
        : theme.colorScheme.outline.withValues(alpha: 0.3);

    return ColoredBox(
      color: color,
      child: axis == Axis.horizontal
          ? SizedBox(width: widget.config.dividerThickness)
          : SizedBox(height: widget.config.dividerThickness),
    );
  }
}

/// A simplified builder that creates an editable layout from a list of widgets.
///
/// This is useful when you want to quickly create a draggable layout
/// without manually constructing the node tree.
class SimpleEditableLayout extends StatefulWidget {
  /// Creates a simple editable layout.
  const SimpleEditableLayout({
    required this.children, super.key,
    this.initialAxis = SplitAxis.horizontal,
    this.editMode = true,
    this.config = const EditableMultiSplitViewConfig(),
  });

  /// The child widgets to display in the layout.
  /// Each child will become a leaf node in the tree.
  final List<Widget> children;

  /// The initial axis for arranging children.
  final SplitAxis initialAxis;

  /// Whether edit mode is enabled.
  final bool editMode;

  /// Configuration for the split view.
  final EditableMultiSplitViewConfig config;

  @override
  State<SimpleEditableLayout> createState() => _SimpleEditableLayoutState();
}

class _SimpleEditableLayoutState extends State<SimpleEditableLayout> {
  late SplitLayoutController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SplitLayoutController(
      rootNode: _buildInitialTree(),
    )..editMode = widget.editMode;
  }

  @override
  void didUpdateWidget(SimpleEditableLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editMode != oldWidget.editMode) {
      _controller.editMode = widget.editMode;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  SplitNode _buildInitialTree() {
    if (widget.children.isEmpty) {
      return SplitNode.leaf(
        id: 'empty_0',
        widgetBuilder: (_) => const SizedBox(),
      );
    }

    if (widget.children.length == 1) {
      return SplitNode.leaf(
        id: 'leaf_0',
        widgetBuilder: (_) => widget.children[0],
      );
    }

    final leafNodes = <SplitNode>[];
    for (var i = 0; i < widget.children.length; i++) {
      final index = i;
      leafNodes.add(SplitNode.leaf(
        id: 'leaf_$i',
        widgetBuilder: (_) => widget.children[index],
      ),);
    }

    return SplitNode.branch(
      id: 'root',
      axis: widget.initialAxis,
      children: leafNodes,
    );
  }

  @override
  Widget build(BuildContext context) {
    return EditableMultiSplitView(
      controller: _controller,
      config: widget.config,
    );
  }
}

/// Extension methods for SplitLayoutController to integrate with MultiSplitView.
extension SplitLayoutControllerExtensions on SplitLayoutController {
  /// Synchronizes flex values from MultiSplitView controllers back to the node tree.
  void syncFlexValues(String nodeId, List<Area> areas) {
    final path = findPathById(nodeId);
    if (path == null) return;

    final node = getNodeAtPath(path);
    if (node == null || node.isLeaf) return;

    if (node.children.length != areas.length) return;

    final updatedChildren = <SplitNode>[];
    for (var i = 0; i < node.children.length; i++) {
      updatedChildren.add(
        node.children[i].copyWith(flex: areas[i].flex ?? 1.0),
      );
    }

    final updatedNode = node.copyWith(children: updatedChildren);
    updateRootNode(rootNode.replaceAtPath(path, updatedNode));
  }
}
