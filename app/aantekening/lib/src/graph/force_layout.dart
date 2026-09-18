/// Laying a graph out by simulating it: nodes push one another apart, links
/// pull what they join together, and the whole cools until it settles.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'note_graph.dart';

/// A force-directed layout of a [NoteGraph], after d3-force.
///
/// Every node repels every other, so the work per step grows with the square
/// of the nodes — a few milliseconds for a thousand, which covers a large
/// personal workspace. The simulation starts hot and cools with every step;
/// taking hold of a node warms it again, so the rest move out of the way.
class ForceLayout {
  /// Lays out [graph], starting nodes it shares with an earlier layout where
  /// they were, [previous], and new ones beside what they are in.
  ForceLayout(this.graph, {Map<String, Offset> previous = const {}})
    : positions = List<Offset>.filled(graph.nodes.length, Offset.zero),
      _velocities = List<Offset>.filled(graph.nodes.length, Offset.zero),
      _degree = List<int>.filled(graph.nodes.length, 0) {
    for (final (parent, child) in graph.links) {
      _degree[parent]++;
      _degree[child]++;
    }
    final parentOf = <int, int>{
      for (final (parent, child) in graph.links) child: parent,
    };
    var fresh = 0;
    for (var i = 0; i < positions.length; i++) {
      final kept = previous[graph.nodes[i].id];
      if (kept != null) {
        positions[i] = kept;
        continue;
      }
      // Nodes are placed in order, so a node's parent, placed before it,
      // is where it starts beside; the rest spiral out from the middle.
      final parent = parentOf[i];
      final angle = fresh * _goldenAngle;
      final radius = parent != null && parent < i
          ? 12.0
          : 10 * math.sqrt(fresh + 0.5);
      final around = parent != null && parent < i
          ? positions[parent]
          : Offset.zero;
      positions[i] = around + Offset(math.cos(angle), math.sin(angle)) * radius;
      fresh++;
    }
    // A graph that only lost nodes and links has less to settle.
    if (fresh == 0) _alpha = 0.3;
  }

  final NoteGraph graph;

  /// Where each node is, by its index in the graph.
  final List<Offset> positions;

  final List<Offset> _velocities;

  /// How many links each node has, which weighs how hard its links pull.
  final List<int> _degree;

  /// The node held where the pointer is, which the forces do not move.
  int? _held;

  /// How hot the simulation is: how far a step moves things.
  double _alpha = 1;

  static const double _alphaMin = 0.001;

  /// Cools to [_alphaMin] in about three hundred steps, five seconds at sixty
  /// frames a second.
  static final double _alphaDecay = 1 - math.pow(_alphaMin, 1 / 300).toDouble();

  /// The share of its speed a node loses every step.
  static const double _drag = 0.4;

  /// How strongly each node is drawn to the middle, which keeps notebooks
  /// that share nothing from drifting apart.
  static const double _gravity = 0.05;

  static final double _goldenAngle = math.pi * (3 - math.sqrt(5));

  /// Whether the layout has come to rest.
  bool get isSettled => _alpha < _alphaMin && _held == null;

  /// How big a node is drawn, in layout units.
  static double radiusOf(GraphNode node) => switch (node.kind) {
    GraphNodeKind.notebook => 10,
    GraphNodeKind.section => 7,
    GraphNodeKind.page => 4.5,
  };

  static double _charge(GraphNode node) => switch (node.kind) {
    GraphNodeKind.notebook => -300,
    GraphNodeKind.section => -140,
    GraphNodeKind.page => -50,
  };

  static double _linkLength(GraphNode child) =>
      child.kind == GraphNodeKind.page ? 36 : 64;

  /// Warms the simulation to at least [alpha], to set it moving again.
  void reheat([double alpha = 0.3]) => _alpha = math.max(_alpha, alpha);

  /// Holds [node] at [at], as a pointer dragging it does.
  void hold(int node, Offset at) {
    _held = node;
    positions[node] = at;
    _velocities[node] = Offset.zero;
    reheat();
  }

  /// Lets go of the node held.
  void release() => _held = null;

  /// The node drawn at [point], if any, allowing [slop] around small ones.
  int? nodeAt(Offset point, {double slop = 4}) {
    int? best;
    var bestDistance = double.infinity;
    for (var i = 0; i < positions.length; i++) {
      final distance = (positions[i] - point).distance;
      if (distance <= radiusOf(graph.nodes[i]) + slop &&
          distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// Where each node is, by its id, for a layout of a changed graph to start
  /// from.
  Map<String, Offset> get positionsById => <String, Offset>{
    for (var i = 0; i < positions.length; i++) graph.nodes[i].id: positions[i],
  };

  /// Moves the simulation on by one step.
  void step() {
    final nodes = graph.nodes;
    final count = nodes.length;

    // Every node pushes every other away, harder the closer they are.
    for (var i = 0; i < count; i++) {
      final charge = _charge(nodes[i]) * _alpha;
      for (var j = 0; j < count; j++) {
        if (i == j) continue;
        var dx = positions[i].dx - positions[j].dx;
        var dy = positions[i].dy - positions[j].dy;
        if (dx == 0 && dy == 0) {
          // Nodes on top of one another are nudged apart in a fixed way,
          // so the layout does not depend on chance.
          dx = (j - i) * 1e-3;
          dy = (i + j) % 2 == 0 ? 1e-3 : -1e-3;
        }
        final squared = math.max(dx * dx + dy * dy, 1.0);
        _velocities[j] -= Offset(dx, dy) * (-charge / squared);
      }
    }

    // Links pull towards their length, the lighter end moving the more.
    for (final (parent, child) in graph.links) {
      final delta =
          positions[child] +
          _velocities[child] -
          positions[parent] -
          _velocities[parent];
      final length = math.max(delta.distance, 1e-6);
      final strength = 1 / math.min(_degree[parent], _degree[child]);
      final pull =
          delta *
          ((length - _linkLength(nodes[child])) / length * _alpha * strength);
      final bias = _degree[parent] / (_degree[parent] + _degree[child]);
      _velocities[child] -= pull * bias;
      _velocities[parent] += pull * (1 - bias);
    }

    for (var i = 0; i < count; i++) {
      if (i == _held) {
        _velocities[i] = Offset.zero;
        continue;
      }
      _velocities[i] =
          (_velocities[i] - positions[i] * (_gravity * _alpha)) * (1 - _drag);
      positions[i] += _velocities[i];
    }

    _alpha *= 1 - _alphaDecay;
  }
}
