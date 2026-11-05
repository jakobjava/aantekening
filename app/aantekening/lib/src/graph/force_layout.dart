/// Laying a graph out by simulating it: nodes push one another apart, links
/// pull what they join together, and the whole cools until it settles.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'note_graph.dart';

/// A force-directed layout of a [NoteGraph], after d3-force.
///
/// Every node repels every other. Up to [exactUpTo] nodes each pair is
/// worked out, once for both; past that the nodes are gathered into a
/// quadtree, and a square of them far from a node pushes it as one node
/// would (Barnes and Hut), so a step of a workspace of thousands of pages
/// costs a little more than its nodes rather than their square. The
/// simulation starts hot and cools with every step; taking hold of a node
/// warms it again, so the rest move out of the way.
class ForceLayout {
  /// Lays out [graph], starting nodes it shares with an earlier layout where
  /// they were, [previous], and new ones beside what they are in.
  ForceLayout(
    this.graph, {
    Map<String, Offset> previous = const {},
    @visibleForTesting this.exactUpTo = 500,
  }) : positions = List<Offset>.filled(graph.nodes.length, Offset.zero),
       _velocities = List<Offset>.filled(graph.nodes.length, Offset.zero),
       _degree = List<int>.filled(graph.nodes.length, 0),
       _x = Float64List(graph.nodes.length),
       _y = Float64List(graph.nodes.length),
       _vx = Float64List(graph.nodes.length),
       _vy = Float64List(graph.nodes.length),
       _strength = Float64List(graph.nodes.length) {
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

  /// The most nodes whose every pair is worked out; more are pushed apart
  /// through a quadtree.
  final int exactUpTo;

  /// Where each node is, by its index in the graph.
  final List<Offset> positions;

  final List<Offset> _velocities;

  /// How many links each node has, which weighs how hard its links pull.
  final List<int> _degree;

  /// A step's positions, velocities and charges, unboxed while the nodes
  /// push one another apart.
  final Float64List _x;
  final Float64List _y;
  final Float64List _vx;
  final Float64List _vy;
  final Float64List _strength;

  final _Quadtree _tree = _Quadtree();

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
    GraphNodeKind.page => -80,
  };

  static double _linkLength(GraphNode child) =>
      child.kind == GraphNodeKind.page ? 48 : 72;

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
    for (var i = 0; i < count; i++) {
      _x[i] = positions[i].dx;
      _y[i] = positions[i].dy;
      _vx[i] = _velocities[i].dx;
      _vy[i] = _velocities[i].dy;
      _strength[i] = _charge(nodes[i]) * _alpha;
    }

    // Every node pushes every other away, harder the closer they are.
    if (count <= exactUpTo) {
      _repelEveryPair();
    } else {
      _repelByQuadtree();
    }

    for (var i = 0; i < count; i++) {
      _velocities[i] = Offset(_vx[i], _vy[i]);
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

  /// Pushes each pair of nodes apart, the one by the other's charge and the
  /// other by the one's.
  void _repelEveryPair() {
    final count = graph.nodes.length;
    for (var i = 0; i < count; i++) {
      for (var j = i + 1; j < count; j++) {
        // From j towards i, along which j is pushed back, and from i
        // towards j, along which i is.
        var dx = _x[i] - _x[j];
        var dy = _y[i] - _y[j];
        var ex = -dx;
        var ey = -dy;
        if (dx == 0 && dy == 0) {
          // Nodes on top of one another are nudged apart in a fixed way,
          // so the layout does not depend on chance.
          dx = (j - i) * 1e-3;
          ex = (i - j) * 1e-3;
          dy = ey = (i + j) % 2 == 0 ? 1e-3 : -1e-3;
        }
        final squared = math.max(dx * dx + dy * dy, 1.0);
        final byI = -_strength[i] / squared;
        final byJ = -_strength[j] / squared;
        _vx[j] -= dx * byI;
        _vy[j] -= dy * byI;
        _vx[i] -= ex * byJ;
        _vy[i] -= ey * byJ;
      }
    }
  }

  /// Pushes each node away from the rest as a quadtree of them has them:
  /// by each node near it, and by each square far from it as by one node.
  void _repelByQuadtree() {
    final count = graph.nodes.length;
    _tree.build(_x, _y, _strength, count);
    for (var j = 0; j < count; j++) {
      _tree.push(j, _x, _y, _vx, _vy, _strength);
    }
  }
}

/// Nodes gathered into squares, each split in four while it holds more than
/// one place, and each knowing the charge of everything in it and where that
/// charge is centred. Its lists are kept from step to step, grown when a
/// step needs more.
class _Quadtree {
  /// How small a square must look from a node — its side over its distance
  /// — for what is in it to push as one. Below the square root of a half, a
  /// square never looks that small from a node inside it.
  static const double _theta = 0.7;

  /// How many times a square is split at most; nodes nearer one another
  /// than that are kept together in one square.
  static const int _deepest = 48;

  static const int _empty = -1;
  static const int _split = -2;

  /// By square: its four quarters, the first node in it while it is not
  /// split (or [_empty], or [_split]), its side, its charge, how much charge
  /// regardless of sign, and where that is centred.
  Int32List _quarters = Int32List(0);
  Int32List _first = Int32List(0);
  Float64List _side = Float64List(0);
  Float64List _charge = Float64List(0);
  Float64List _weight = Float64List(0);
  Float64List _cx = Float64List(0);
  Float64List _cy = Float64List(0);
  int _squares = 0;

  /// By node, the next node in the same square.
  Int32List _next = Int32List(0);

  final Int32List _stack = Int32List(4 * _deepest + 8);

  int _newSquare(double side) {
    if (_squares == _first.length) {
      final grown = math.max(16, _first.length * 2);
      _quarters = Int32List(4 * grown)..setAll(0, _quarters);
      _first = Int32List(grown)..setAll(0, _first);
      _side = Float64List(grown)..setAll(0, _side);
      _charge = Float64List(grown);
      _weight = Float64List(grown);
      _cx = Float64List(grown);
      _cy = Float64List(grown);
    }
    final square = _squares++;
    _quarters.fillRange(4 * square, 4 * square + 4, _empty);
    _first[square] = _empty;
    _side[square] = side;
    return square;
  }

  /// Gathers the first [count] nodes, at [x] and [y], of charge [strength].
  void build(Float64List x, Float64List y, Float64List strength, int count) {
    if (_next.length < count) _next = Int32List(count);
    _squares = 0;
    if (count == 0) return;
    var left = x[0];
    var top = y[0];
    var right = x[0];
    var bottom = y[0];
    for (var i = 1; i < count; i++) {
      left = math.min(left, x[i]);
      right = math.max(right, x[i]);
      top = math.min(top, y[i]);
      bottom = math.max(bottom, y[i]);
    }
    final side = math.max(math.max(right - left, bottom - top), 1.0);
    _newSquare(side);
    for (var i = 0; i < count; i++) {
      _insert(i, x, y, left, top, side);
    }

    // A square is made after the square it is in, so going back through
    // them sums each one's quarters before the square that holds them.
    for (var square = _squares - 1; square >= 0; square--) {
      var charge = 0.0;
      var weight = 0.0;
      var cx = 0.0;
      var cy = 0.0;
      final first = _first[square];
      if (first >= 0) {
        for (var node = first; node != _empty; node = _next[node]) {
          final w = strength[node].abs();
          charge += strength[node];
          weight += w;
          cx += w * x[node];
          cy += w * y[node];
        }
      } else {
        for (var q = 4 * square; q < 4 * square + 4; q++) {
          final quarter = _quarters[q];
          if (quarter == _empty) continue;
          final w = _weight[quarter];
          charge += _charge[quarter];
          weight += w;
          cx += w * _cx[quarter];
          cy += w * _cy[quarter];
        }
      }
      _charge[square] = charge;
      _weight[square] = weight;
      _cx[square] = weight == 0 ? 0 : cx / weight;
      _cy[square] = weight == 0 ? 0 : cy / weight;
    }
  }

  void _insert(
    int node,
    Float64List x,
    Float64List y,
    double left,
    double top,
    double side,
  ) {
    final px = x[node];
    final py = y[node];
    var square = 0;
    for (var depth = 0; ; depth++) {
      final first = _first[square];
      if (first == _empty) {
        _first[square] = node;
        _next[node] = _empty;
        return;
      }
      final half = side / 2;
      if (first >= 0) {
        if ((x[first] == px && y[first] == py) || depth >= _deepest) {
          _next[node] = first;
          _first[square] = node;
          return;
        }
        // The square is split, and what was in it, all in one place, goes
        // to its quarter.
        final at =
            4 * square +
            (y[first] >= top + half ? 2 : 0) +
            (x[first] >= left + half ? 1 : 0);
        final quarter = _newSquare(half);
        _quarters[at] = quarter;
        _first[quarter] = first;
        _first[square] = _split;
      }
      final right = px >= left + half;
      final below = py >= top + half;
      final at = 4 * square + (below ? 2 : 0) + (right ? 1 : 0);
      if (right) left += half;
      if (below) top += half;
      side = half;
      if (_quarters[at] == _empty) {
        final quarter = _newSquare(side);
        _quarters[at] = quarter;
        _first[quarter] = node;
        _next[node] = _empty;
        return;
      }
      square = _quarters[at];
    }
  }

  /// Adds to [vx] and [vy] how the rest push node [j].
  void push(
    int j,
    Float64List x,
    Float64List y,
    Float64List vx,
    Float64List vy,
    Float64List strength,
  ) {
    if (_squares == 0) return;
    final stack = _stack;
    final xj = x[j];
    final yj = y[j];
    var vxj = vx[j];
    var vyj = vy[j];
    var height = 0;
    stack[height++] = 0;
    while (height > 0) {
      final square = stack[--height];
      final first = _first[square];
      if (first == _split) {
        final dx = _cx[square] - xj;
        final dy = _cy[square] - yj;
        final squared = dx * dx + dy * dy;
        final side = _side[square];
        if (side * side < _theta * _theta * squared) {
          final by = -_charge[square] / math.max(squared, 1.0);
          vxj -= dx * by;
          vyj -= dy * by;
          continue;
        }
        for (var q = 4 * square; q < 4 * square + 4; q++) {
          final quarter = _quarters[q];
          if (quarter != _empty) stack[height++] = quarter;
        }
        continue;
      }
      for (var i = first; i != _empty; i = _next[i]) {
        if (i == j) continue;
        var dx = x[i] - xj;
        var dy = y[i] - yj;
        if (dx == 0 && dy == 0) {
          dx = (j - i) * 1e-3;
          dy = (i + j) % 2 == 0 ? 1e-3 : -1e-3;
        }
        final by = -strength[i] / math.max(dx * dx + dy * dy, 1.0);
        vxj -= dx * by;
        vyj -= dy * by;
      }
    }
    vx[j] = vxj;
    vy[j] = vyj;
  }
}
