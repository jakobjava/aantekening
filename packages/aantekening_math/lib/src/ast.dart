/// The syntax tree the linear math parser produces, and its LaTeX emission.
library;

/// A node in a parsed math expression.
///
/// The tree is the intermediate form between what the user types and the LaTeX
/// the renderer consumes. Keeping it explicit — rather than rewriting the input
/// with regular expressions — is what makes constructs like nested fractions,
/// limits on big operators and bracket elision behave predictably.
sealed class MathNode {
  const MathNode();

  /// Appends this node's LaTeX to [out].
  void writeLatex(StringBuffer out);

  /// The LaTeX for this node alone.
  String toLatex() {
    final buffer = StringBuffer();
    writeLatex(buffer);
    return buffer.toString();
  }

  /// Wraps [node] in braces unless it is already a single LaTeX token.
  ///
  /// Used wherever LaTeX needs a group (`^`, `_`, `\frac`); skipping the braces
  /// for single characters keeps the output close to what a person would write
  /// by hand, which matters because users switch between the two modes.
  static void writeGrouped(StringBuffer out, MathNode node) {
    final latex = node.toLatex();
    if (_isSingleToken(latex)) {
      out.write(latex);
    } else {
      out
        ..write('{')
        ..write(latex)
        ..write('}');
    }
  }

  static bool _isSingleToken(String latex) {
    if (latex.length == 1) return true;
    // A lone control sequence such as `\alpha` also needs no braces.
    return RegExp(r'^\\[a-zA-Z]+$').hasMatch(latex);
  }
}

/// A numeric literal.
final class NumberNode extends MathNode {
  const NumberNode(this.text);

  final String text;

  @override
  void writeLatex(StringBuffer out) => out.write(text);
}

/// A single-letter variable.
final class VariableNode extends MathNode {
  const VariableNode(this.name);

  final String name;

  @override
  void writeLatex(StringBuffer out) => out.write(name);
}

/// A recognised symbol, function name or big operator, already in LaTeX form.
final class SymbolNode extends MathNode {
  const SymbolNode(this.latex);

  final String latex;

  @override
  void writeLatex(StringBuffer out) => out.write(latex);
}

/// Literal prose inside an expression, typed between double quotes.
final class TextNode extends MathNode {
  const TextNode(this.text);

  final String text;

  @override
  void writeLatex(StringBuffer out) {
    out
      ..write(r'\text{')
      ..write(text)
      ..write('}');
  }
}

/// Juxtaposed nodes: implicit multiplication, or a function and its argument.
final class SequenceNode extends MathNode {
  const SequenceNode(this.children);

  final List<MathNode> children;

  @override
  void writeLatex(StringBuffer out) {
    for (var i = 0; i < children.length; i++) {
      if (i > 0) out.write(' ');
      children[i].writeLatex(out);
    }
  }
}

/// An infix operator such as `+`, `=` or `\cdot`.
final class BinaryNode extends MathNode {
  const BinaryNode(this.operatorLatex, this.left, this.right);

  final String operatorLatex;
  final MathNode left;
  final MathNode right;

  @override
  void writeLatex(StringBuffer out) {
    left.writeLatex(out);
    out
      ..write(' ')
      ..write(operatorLatex)
      ..write(' ');
    right.writeLatex(out);
  }
}

/// A prefix operator, such as negation.
final class UnaryNode extends MathNode {
  const UnaryNode(this.operatorLatex, this.operand);

  final String operatorLatex;
  final MathNode operand;

  @override
  void writeLatex(StringBuffer out) {
    out.write(operatorLatex);
    operand.writeLatex(out);
  }
}

/// A built-up fraction.
final class FractionNode extends MathNode {
  const FractionNode(this.numerator, this.denominator);

  final MathNode numerator;
  final MathNode denominator;

  @override
  void writeLatex(StringBuffer out) {
    out
      ..write(r'\frac{')
      ..write(numerator.toLatex())
      ..write('}{')
      ..write(denominator.toLatex())
      ..write('}');
  }
}

/// A base carrying a subscript, a superscript, or both.
final class ScriptNode extends MathNode {
  const ScriptNode(this.base, {this.subscript, this.superscript});

  final MathNode base;
  final MathNode? subscript;
  final MathNode? superscript;

  @override
  void writeLatex(StringBuffer out) {
    base.writeLatex(out);
    final sub = subscript;
    if (sub != null) {
      out.write('_');
      MathNode.writeGrouped(out, sub);
    }
    final sup = superscript;
    if (sup != null) {
      out.write('^');
      MathNode.writeGrouped(out, sup);
    }
  }
}

/// A square or nth root.
final class RootNode extends MathNode {
  const RootNode(this.radicand, {this.index});

  final MathNode radicand;

  /// The root's degree, or null for a square root.
  final MathNode? index;

  @override
  void writeLatex(StringBuffer out) {
    out.write(r'\sqrt');
    final degree = index;
    if (degree != null) {
      out
        ..write('[')
        ..write(degree.toLatex())
        ..write(']');
    }
    out
      ..write('{')
      ..write(radicand.toLatex())
      ..write('}');
  }
}

/// An accent or decoration applied over its operand: `\vec`, `\hat`, `\overline`.
final class AccentNode extends MathNode {
  const AccentNode(this.command, this.operand);

  final String command;
  final MathNode operand;

  @override
  void writeLatex(StringBuffer out) {
    out
      ..write(command)
      ..write('{')
      ..write(operand.toLatex())
      ..write('}');
  }
}

/// A two-argument construct such as `\binom`.
final class BinaryConstructNode extends MathNode {
  const BinaryConstructNode(this.command, this.first, this.second);

  final String command;
  final MathNode first;
  final MathNode second;

  @override
  void writeLatex(StringBuffer out) {
    out
      ..write(command)
      ..write('{')
      ..write(first.toLatex())
      ..write('}{')
      ..write(second.toLatex())
      ..write('}');
  }
}

/// A bracketed group, rendered with delimiters that grow with their contents.
final class FencedNode extends MathNode {
  const FencedNode(
    this.left,
    this.right,
    this.child, {
    this.isRoundParen = false,
  });

  final String left;
  final String right;
  final MathNode child;

  /// Whether these are ordinary round parentheses.
  ///
  /// Constructs that supply their own visual grouping — fractions, roots,
  /// scripts — drop a redundant pair, so `(a+b)/c` renders as a fraction with
  /// a bare numerator rather than one wrapped in parentheses.
  final bool isRoundParen;

  @override
  void writeLatex(StringBuffer out) {
    out
      ..write(r'\left')
      ..write(left)
      ..write(' ')
      ..write(child.toLatex())
      ..write(r' \right')
      ..write(right);
  }
}

/// An invisible group, from braces the user typed.
final class GroupNode extends MathNode {
  const GroupNode(this.child);

  final MathNode child;

  @override
  void writeLatex(StringBuffer out) {
    out
      ..write('{')
      ..write(child.toLatex())
      ..write('}');
  }
}

/// A placeholder standing in for a missing operand.
///
/// Emitted instead of failing so that a half-typed expression still renders and
/// the live preview keeps up with the user.
final class EmptyNode extends MathNode {
  const EmptyNode();

  @override
  void writeLatex(StringBuffer out) => out.write(r'\square');
}

/// A comma-separated list, such as the arguments of `f(x, y)`.
final class ListNode extends MathNode {
  const ListNode(this.items);

  final List<MathNode> items;

  @override
  void writeLatex(StringBuffer out) {
    for (var i = 0; i < items.length; i++) {
      if (i > 0) out.write(', ');
      items[i].writeLatex(out);
    }
  }
}

/// A named function applied to a bracketed argument, such as `\sin(x)`.
///
/// Kept as one node rather than two juxtaposed ones so that a following `/`
/// treats the whole application as the numerator: `sin(x)/x` is a fraction of
/// the function's value, not of its bracket.
final class ApplicationNode extends MathNode {
  const ApplicationNode(this.function, this.argument);

  final MathNode function;
  final MathNode argument;

  @override
  void writeLatex(StringBuffer out) {
    function.writeLatex(out);
    out.write(' ');
    argument.writeLatex(out);
  }
}
