import 'package:drag_split_layout/drag_split_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SplitNode', () {
    test('creates leaf node correctly', () {
      final node = SplitNode.leaf(
        id: 'test_leaf',
        widgetBuilder: (_) => const SizedBox(),
      );

      expect(node.isLeaf, isTrue);
      expect(node.isBranch, isFalse);
      expect(node.id, equals('test_leaf'));
      expect(node.flex, equals(1.0));
      expect(node.children, isEmpty);
    });

    test('creates branch node correctly', () {
      final leaf1 = SplitNode.leaf(
        id: 'leaf1',
        widgetBuilder: (_) => const SizedBox(),
      );
      final leaf2 = SplitNode.leaf(
        id: 'leaf2',
        widgetBuilder: (_) => const SizedBox(),
      );

      final branch = SplitNode.branch(
        id: 'test_branch',
        axis: SplitAxis.horizontal,
        children: [leaf1, leaf2],
      );

      expect(branch.isBranch, isTrue);
      expect(branch.isLeaf, isFalse);
      expect(branch.axis, equals(SplitAxis.horizontal));
      expect(branch.children.length, equals(2));
    });

    test('findPath returns correct path', () {
      final leaf1 = SplitNode.leaf(id: 'leaf1', widgetBuilder: (_) => const SizedBox());
      final leaf2 = SplitNode.leaf(id: 'leaf2', widgetBuilder: (_) => const SizedBox());
      final branch = SplitNode.branch(
        id: 'branch',
        axis: SplitAxis.horizontal,
        children: [leaf1, leaf2],
      );

      expect(branch.findPath('branch'), equals(<int>[]));
      expect(branch.findPath('leaf1'), equals([0]));
      expect(branch.findPath('leaf2'), equals([1]));
      expect(branch.findPath('nonexistent'), isNull);
    });

    test('nodeAtPath returns correct node', () {
      final leaf1 = SplitNode.leaf(id: 'leaf1', widgetBuilder: (_) => const SizedBox());
      final leaf2 = SplitNode.leaf(id: 'leaf2', widgetBuilder: (_) => const SizedBox());
      final branch = SplitNode.branch(
        id: 'branch',
        axis: SplitAxis.horizontal,
        children: [leaf1, leaf2],
      );

      expect(branch.nodeAtPath([])?.id, equals('branch'));
      expect(branch.nodeAtPath([0])?.id, equals('leaf1'));
      expect(branch.nodeAtPath([1])?.id, equals('leaf2'));
      expect(branch.nodeAtPath([2]), isNull);
    });
  });

  group('DropZone', () {
    test('isEdge returns correct values', () {
      expect(DropZone.left.isEdge, isTrue);
      expect(DropZone.right.isEdge, isTrue);
      expect(DropZone.top.isEdge, isTrue);
      expect(DropZone.bottom.isEdge, isTrue);
      expect(DropZone.center.isEdge, isFalse);
    });

    test('splitAxis returns correct axis', () {
      expect(DropZone.left.splitAxis, equals(SplitAxis.horizontal));
      expect(DropZone.right.splitAxis, equals(SplitAxis.horizontal));
      expect(DropZone.top.splitAxis, equals(SplitAxis.vertical));
      expect(DropZone.bottom.splitAxis, equals(SplitAxis.vertical));
      expect(DropZone.center.splitAxis, isNull);
    });
  });

  group('HoverZoneDetector', () {
    test('detects center zone', () {
      const detector = HoverZoneDetector();
      final zone = detector.detectZone(
        const Offset(50, 50),
        const Size(100, 100),
      );
      expect(zone, equals(DropZone.center));
    });

    test('detects left zone', () {
      const detector = HoverZoneDetector();
      final zone = detector.detectZone(
        const Offset(5, 50),
        const Size(100, 100),
      );
      expect(zone, equals(DropZone.left));
    });

    test('detects right zone', () {
      const detector = HoverZoneDetector();
      final zone = detector.detectZone(
        const Offset(95, 50),
        const Size(100, 100),
      );
      expect(zone, equals(DropZone.right));
    });

    test('detects top zone', () {
      const detector = HoverZoneDetector();
      final zone = detector.detectZone(
        const Offset(50, 5),
        const Size(100, 100),
      );
      expect(zone, equals(DropZone.top));
    });

    test('detects bottom zone', () {
      const detector = HoverZoneDetector();
      final zone = detector.detectZone(
        const Offset(50, 95),
        const Size(100, 100),
      );
      expect(zone, equals(DropZone.bottom));
    });
  });

  group('SplitLayoutController', () {
    test('initializes with root node', () {
      final rootNode = SplitNode.leaf(
        id: 'root',
        widgetBuilder: (_) => const SizedBox(),
      );
      final controller = SplitLayoutController(rootNode: rootNode);

      expect(controller.rootNode.id, equals('root'));
      expect(controller.editMode, isTrue);
      expect(controller.preview, isNull);
      expect(controller.activeDragItem, isNull);
    });

    test('edit mode can be toggled', () {
      final rootNode = SplitNode.leaf(
        id: 'root',
        widgetBuilder: (_) => const SizedBox(),
      );
      final controller = SplitLayoutController(rootNode: rootNode);

      controller.editMode = false;
      expect(controller.editMode, isFalse);

      controller.editMode = true;
      expect(controller.editMode, isTrue);
    });

    test('clearPreview clears the preview', () {
      final rootNode = SplitNode.leaf(
        id: 'root',
        widgetBuilder: (_) => const SizedBox(),
      );
      final controller = SplitLayoutController(rootNode: rootNode);

      // Start a drag to allow hover updates
      controller.onDragStart(
        const DragItemModel(
          id: 'other',
          widgetType: 'pane',
          originalPath: [0],
        ),
      );

      // Update hover to create a preview
      controller.onHoverUpdate(
        localPosition: const Offset(10, 50),
        paneSize: const Size(100, 100),
        targetNodeId: 'root',
        targetNodePath: [],
      );

      expect(controller.preview, isNotNull);

      controller.clearPreview();
      expect(controller.preview, isNull);
    });

    group('onBeforeReplace callback', () {
      SplitNode createTwoLeafBranch() {
        return SplitNode.branch(
          id: 'root',
          axis: SplitAxis.horizontal,
          children: [
            SplitNode.leaf(
              id: 'leaf1',
              widgetBuilder: (_) => const SizedBox(),
            ),
            SplitNode.leaf(
              id: 'leaf2',
              widgetBuilder: (_) => const SizedBox(),
            ),
          ],
        );
      }

      void setupReplacePreview(SplitLayoutController controller) {
        // Start a drag operation
        controller.onDragStart(
          const DragItemModel(
            id: 'leaf1',
            widgetType: 'pane',
            originalPath: [0],
          ),
        );

        // Hover in the center of leaf2 to trigger replace preview
        controller.onHoverUpdate(
          localPosition: const Offset(50, 50),
          paneSize: const Size(100, 100),
          targetNodeId: 'leaf2',
          targetNodePath: [1],
        );
      }

      test('onBeforeReplace callback is called for replace actions', () {
        var callbackInvoked = false;
        String? capturedTargetId;

        final controller = SplitLayoutController(
          rootNode: createTwoLeafBranch(),
          onBeforeReplace: (draggedItem, targetNodeId, preview) {
            callbackInvoked = true;
            capturedTargetId = targetNodeId;
            return ReplaceInterceptResult.allow;
          },
        );

        setupReplacePreview(controller);

        // Verify we have a replace preview
        expect(controller.preview, isNotNull);
        expect(controller.preview!.action, equals(DropAction.replace));

        // Execute the drop
        controller.onDrop(
          draggedItem: const DragItemModel(
            id: 'leaf1',
            widgetType: 'pane',
            originalPath: [0],
          ),
          newNodeBuilder: () => SplitNode.leaf(
            id: 'new_leaf',
            widgetBuilder: (_) => const SizedBox(),
          ),
        );

        expect(callbackInvoked, isTrue);
        expect(capturedTargetId, equals('leaf2'));
      });

      test('ReplaceInterceptResult.cancel prevents replace action', () {
        final controller = SplitLayoutController(
          rootNode: createTwoLeafBranch(),
          onBeforeReplace: (_, __, ___) => ReplaceInterceptResult.cancel,
        );

        setupReplacePreview(controller);

        // Try to execute the drop
        final result = controller.onDrop(
          draggedItem: const DragItemModel(
            id: 'leaf1',
            widgetType: 'pane',
            originalPath: [0],
          ),
          newNodeBuilder: () => SplitNode.leaf(
            id: 'new_leaf',
            widgetBuilder: (_) => const SizedBox(),
          ),
        );

        // Drop should be cancelled
        expect(result, isFalse);
        // Original structure should be unchanged
        expect(controller.rootNode.children.length, equals(2));
        expect(controller.rootNode.children[0].id, equals('leaf1'));
        expect(controller.rootNode.children[1].id, equals('leaf2'));
      });

      test('ReplaceInterceptResult.handled cleans up state without replacing', () {
        var handlerCalled = false;

        final controller = SplitLayoutController(
          rootNode: createTwoLeafBranch(),
          onBeforeReplace: (_, __, ___) {
            handlerCalled = true;
            return ReplaceInterceptResult.handled;
          },
        );

        setupReplacePreview(controller);

        final result = controller.onDrop(
          draggedItem: const DragItemModel(
            id: 'leaf1',
            widgetType: 'pane',
            originalPath: [0],
          ),
          newNodeBuilder: () => SplitNode.leaf(
            id: 'new_leaf',
            widgetBuilder: (_) => const SizedBox(),
          ),
        );

        // Drop should report as successful
        expect(result, isTrue);
        expect(handlerCalled, isTrue);
        // Original structure should be unchanged (handler took care of it)
        expect(controller.rootNode.children.length, equals(2));
        expect(controller.rootNode.children[0].id, equals('leaf1'));
        expect(controller.rootNode.children[1].id, equals('leaf2'));
        // State should be cleaned up
        expect(controller.preview, isNull);
        expect(controller.activeDragItem, isNull);
      });

      test('ReplaceInterceptResult.allow proceeds with normal replace', () {
        final controller = SplitLayoutController(
          rootNode: createTwoLeafBranch(),
          onBeforeReplace: (_, __, ___) => ReplaceInterceptResult.allow,
        );

        setupReplacePreview(controller);

        final result = controller.onDrop(
          draggedItem: const DragItemModel(
            id: 'external',
            widgetType: 'pane',
            originalPath: [], // New item, not from tree
          ),
          newNodeBuilder: () => SplitNode.leaf(
            id: 'new_leaf',
            widgetBuilder: (_) => const SizedBox(),
          ),
        );

        // Drop should succeed
        expect(result, isTrue);
        // leaf2 should be replaced with new_leaf
        expect(controller.rootNode.children[1].id, equals('new_leaf'));
      });

      test('split actions bypass onBeforeReplace callback', () {
        var callbackInvoked = false;

        final controller = SplitLayoutController(
          rootNode: createTwoLeafBranch(),
          onBeforeReplace: (_, __, ___) {
            callbackInvoked = true;
            return ReplaceInterceptResult.cancel;
          },
        );

        // Start a drag operation
        controller.onDragStart(
          const DragItemModel(
            id: 'leaf1',
            widgetType: 'pane',
            originalPath: [0],
          ),
        );

        // Hover on the left edge (split zone, not replace)
        controller.onHoverUpdate(
          localPosition: const Offset(5, 50),
          paneSize: const Size(100, 100),
          targetNodeId: 'leaf2',
          targetNodePath: [1],
        );

        expect(controller.preview!.action, equals(DropAction.split));

        controller.onDrop(
          draggedItem: const DragItemModel(
            id: 'external',
            widgetType: 'pane',
            originalPath: [],
          ),
          newNodeBuilder: () => SplitNode.leaf(
            id: 'new_leaf',
            widgetBuilder: (_) => const SizedBox(),
          ),
        );

        // Callback should not be invoked for split actions
        expect(callbackInvoked, isFalse);
      });

      test('no callback means replace proceeds normally', () {
        final controller = SplitLayoutController(
          rootNode: createTwoLeafBranch(),
          // No onBeforeReplace callback
        );

        setupReplacePreview(controller);

        final result = controller.onDrop(
          draggedItem: const DragItemModel(
            id: 'external',
            widgetType: 'pane',
            originalPath: [],
          ),
          newNodeBuilder: () => SplitNode.leaf(
            id: 'new_leaf',
            widgetBuilder: (_) => const SizedBox(),
          ),
        );

        expect(result, isTrue);
        expect(controller.rootNode.children[1].id, equals('new_leaf'));
      });
    });
  });

  group('DragItemModel', () {
    test('creates model correctly', () {
      const model = DragItemModel(
        id: 'test_id',
        widgetType: 'panel',
        originalPath: [0, 1],
      );

      expect(model.id, equals('test_id'));
      expect(model.widgetType, equals('panel'));
      expect(model.originalPath, equals([0, 1]));
    });

    test('copyWith creates modified copy', () {
      const model = DragItemModel(
        id: 'test_id',
        widgetType: 'panel',
        originalPath: [0, 1],
      );

      final modified = model.copyWith(id: 'new_id');

      expect(modified.id, equals('new_id'));
      expect(modified.widgetType, equals('panel'));
      expect(modified.originalPath, equals([0, 1]));
    });
  });
}
