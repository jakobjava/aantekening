import 'package:aantekening_core/aantekening_core.dart' show LatexPreamble;
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter_test/flutter_test.dart';

String expand(String latex) => LatexPackages.expand(latex);

/// What keeps [latex], packages and all, from being typeset.
String? problem(String latex) => MathView.problemIn(latex, packages: true);

void main() {
  group('physics', () {
    test('sizes brackets to what they hold', () {
      expect(expand(r'\qty(\frac{a}{b})'), r'\left( \frac{a}{b} \right)');
      expect(expand(r'\qty[x]'), r'\left[ x \right]');
      expect(expand(r'\qty|x|'), r'\left\lvert x \right\rvert');
      expect(expand(r'\abs{x}'), r'\left\lvert x \right\rvert');
      expect(expand(r'\abs*{x}'), r'\lvert x \rvert');
      expect(expand(r'\norm{\vb{v}}'), r'\left\lVert \mathbf{v} \right\rVert');
      expect(expand(r'\eval{x^2}_0^1'), r'\left. x^2 \right|_0^1');
    });

    test('writes derivatives out', () {
      expect(expand(r'\dv{f}{x}'), r'\frac{\mathrm{d} f}{\mathrm{d} x}');
      expect(
        expand(r'\dv[2]{f}{x}'),
        r'\frac{\mathrm{d}^{2} f}{\mathrm{d} x^{2}}',
      );
      expect(expand(r'\dv{x}'), r'\frac{\mathrm{d}}{\mathrm{d} x}');
      expect(
        expand(r'\pdv{f}{x}{y}'),
        r'\frac{\partial^{2} f}{\partial x\,\partial y}',
      );
      expect(expand(r'\int f \dd{x}'), r'\int f \,\mathrm{d} x');
    });

    test("writes vectors, operators and Dirac's notation", () {
      expect(expand(r'\vu{r}'), r'\hat{\mathbf{r}}');
      expect(expand(r'\grad f'), r'\nabla  f');
      expect(expand(r'\div{\vb{E}}'), r'\nabla\cdot{\mathbf{E}}');
      expect(expand(r'\ket{\psi}'), r'\left| \psi \right\rangle');
      expect(
        expand(r'\braket{\phi}{\psi}'),
        r'\left\langle \phi \middle| \psi \right\rangle',
      );
      expect(
        expand(r'\expval{H}{\psi}'),
        r'\left\langle \psi \middle| H \middle| \psi \right\rangle',
      );
    });

    test('writes matrices out', () {
      expect(
        expand(r'\mqty(a & b \\ c & d)'),
        r'\begin{pmatrix}a & b \\ c & d\end{pmatrix}',
      );
      expect(
        expand(r'\mqty[\imat{2}]'),
        r'\begin{bmatrix}1 & 0 \\ 0 & 1\end{bmatrix}',
      );
    });

    test('everything it writes is typeset', () {
      for (final latex in <String>[
        r'\qty(\frac{1}{2}) + \qty{x} + \pqty{a} \bqty{b} \Bqty{c} \vqty{d}',
        r'\abs{x} \norm{v} \eval{f}_a^b \order{x^2}',
        r'\comm{A}{B} \acomm{A}{B} \pb{f}{g}',
        r'\vb{a} \vb*{a} \va{a} \vu{a} \vdot \cross \grad \div \curl \laplacian',
        r'\tr A \Tr \rho \rank M \erf x \Res f \pv \Re z \Im z',
        r'a \qq{for} b \qc c \qif d \qand e',
        r'\dd{x} \dd[3]{x} \dv{f}{x} \dv*{f}{x} \pdv{f}{x} \pdv[2]{f}{x} '
            r'\pdv{f}{x}{y} \fdv{F}{f} \var{x}',
        r'\bra{a} \ket{b} \braket{a}{b} \braket{a} \ketbra{a}{b} \ip{a}{b} '
            r'\expval{A} \expval{A}{\psi} \mel{n}{A}{m}',
        r'\mqty(a & b \\ c & d) \mqty[1] \mqty|1| \pmqty{1} \bmqty{1} '
            r'\vmqty{1} \Pmqty{1} \smqty(a&b) \mqty(\zmat{2}{2}) '
            r'\mqty(\dmat{1,2}) \mqty(\xmat{a}{2}{2})',
      ]) {
        expect(problem(latex), isNull, reason: latex);
      }
    });
  });

  group('siunitx', () {
    test('sets numbers grouped, with powers of ten', () {
      expect(expand(r'\num{12345.678}'), r'12\,345.678');
      expect(expand(r'\num{1234}'), '1234');
      expect(expand(r'\num{1.5e3}'), r'1.5 \times 10^{3}');
      expect(expand(r'\num{1.2+-0.1}'), r'1.2 \pm 0.1');
      expect(expand(r'\num{3,14}'), '3.14');
    });

    test('sets units by name and as written', () {
      expect(
        expand(r'\si{\kilo\metre\per\second\squared}'),
        r'\mathrm{k}\mathrm{m}\,\mathrm{s}^{-2}',
      );
      expect(
        expand(r'\si{\km\per\hour}'),
        r'\mathrm{k}\mathrm{m}\,\mathrm{h}^{-1}',
      );
      expect(
        expand(r'\unit{kg.m/s^2}'),
        r'\mathrm{kg}\,\mathrm{m}/\mathrm{s}^{2}',
      );
      expect(expand(r'\si{\micro\ohm}'), r'\mu\Omega');
    });

    test('sets quantities, a degree without a space', () {
      expect(
        expand(r'\SI{9.81}{\metre\per\second\squared}'),
        r'9.81\,\mathrm{m}\,\mathrm{s}^{-2}',
      );
      expect(expand(r'\qty{3}{\kilo\gram}'), r'3\,\mathrm{k}\mathrm{g}');
      expect(expand(r'\qty{90}{\degree}'), r'90{}^{\circ}');
      expect(expand(r'\ang{30}'), r'30^{\circ}');
      expect(expand(r'\numrange{1}{2}'), r'1\text{ to }2');
      expect(expand(r'\numlist{1;2;3}'), r'1, 2\text{ and }3');
    });

    test('everything it writes is typeset', () {
      for (final latex in <String>[
        r'\num{6.022e23} \num{-1.5} \num{1x2} \num{e-3}',
        r'\si{\joule\per\mole\per\kelvin} \si{\percent} \si{\degreeCelsius}',
        r'\si{\angstrom} \si{\ohm} \si{\uA} \si{\MHz} \si{\kWh} \si{\square\metre}',
        r'\SI{25}{\celsius} \SI{1.2}[\$]{} \qty{3}{\mol\per\litre}',
        r'\ang{12;30;15} \qtyrange{1}{5}{\metre} \SIlist{1;2}{\second}',
      ]) {
        expect(problem(latex), isNull, reason: latex);
      }
    });
  });

  group('mhchem', () {
    test('sets formulas', () {
      expect(expand(r'\ce{H2O}'), r'\mathrm{H}_{2}\mathrm{O}');
      expect(expand(r'\ce{Ca2+}'), r'\mathrm{Ca}^{2+}');
      expect(expand(r'\ce{NO3-}'), r'\mathrm{N}\mathrm{O}_{3}^{-}');
      expect(expand(r'\ce{SO4^2-}'), r'\mathrm{S}\mathrm{O}_{4}^{2-}');
      expect(
        expand(r'\ce{CuSO4*5H2O}'),
        r'\mathrm{Cu}\mathrm{S}\mathrm{O}_{4} \cdot 5\mathrm{H}_{2}\mathrm{O}',
      );
      expect(expand(r'\ce{^{14}_{6}C}'), r'{}^{14}_{6}\mathrm{C}');
      expect(expand(r'\ce{e-}'), r'\mathrm{e}^{-}');
      expect(expand(r'\ce{C=C}'), r'\mathrm{C}{=}\mathrm{C}');
    });

    test('sets equations, their arrows labelled', () {
      expect(
        expand(r'\ce{2H2 + O2 -> 2H2O}'),
        r'2\mathrm{H}_{2} + \mathrm{O}_{2} \xrightarrow{} 2\mathrm{H}_{2}\mathrm{O}',
      );
      expect(
        expand(r'\ce{A ->[\Delta][cat] B}'),
        r'\mathrm{A} \xrightarrow[\mathrm{cat}]{\Delta } \mathrm{B}',
      );
      expect(expand(r'\ce{CO2 ^}'), r'\mathrm{C}\mathrm{O}_{2} \uparrow ');
    });

    test('sets physical units', () {
      expect(expand(r'\pu{123 kJ/mol}'), r'123\,\mathrm{kJ}/\mathrm{mol}');
      expect(expand(r'\pu{1.2e3 kJ}'), r'1.2\cdot 10^{3}\,\mathrm{kJ}');
      expect(
        expand(r'\pu{8.31 J K^-1 mol-1}'),
        r'8.31\,\mathrm{J}\,\mathrm{K}^{-1}\,\mathrm{mol}^{-1}',
      );
    });

    test('everything it writes is typeset', () {
      for (final latex in <String>[
        r'\ce{2H2 + O2 -> 2H2O}',
        r'\ce{N2 + 3H2 <=> 2NH3}',
        r'\ce{A <-> B} \ce{A <- B} \ce{A <--> B} \ce{A <=>> B} \ce{A <<=> B}',
        r'\ce{[Cu(NH3)4]^2+} \ce{(NH4)2S} \ce{Fe^{III}}',
        r'\ce{NaCl(aq) + AgNO3(aq) -> AgCl v + NaNO3(aq)}',
        r'\ce{CaCO3 ->[\Delta] CaO + CO2 ^}',
        r'\ce{1/2 O2} \ce{x Na} \ce{H+ + OH- -> H2O}',
        r'\ce{^{227}_{90}Th+} \ce{C#C} \ce{CH3-CH3}',
        r'\pu{25 °C} \pu{1.5e-3 mol L-1}',
      ]) {
        expect(problem(latex), isNull, reason: latex);
      }
    });
  });

  test('only formulas brought in read the packages', () {
    expect(MathView.problemIn(r'\ce{H2O}'), isNotNull);
    expect(MathView.problemIn(r'\ce{H2O}', packages: true), isNull);
  });

  test('a preamble is written into every formula', () {
    final preamble = LatexPreamble.read(
      r'\newcommand{\Rn}{\mathbb{R}^n} \tikzset{dot/.style={fill}}',
    );
    expect(preamble.leftOver, isEmpty);
    expect(MathView.problemIn(r'x \in \Rn'), isNotNull);
    expect(MathView.problemIn(r'x \in \Rn', preamble: preamble), isNull);
    expect(
      MathView.prepared(
        r'\begin{tikzpicture}\fill[dot] (0,0) circle (1);\end{tikzpicture}',
        preamble: preamble,
      ),
      r'\begin{tikzpicture}[dot/.style={fill}]\fill[dot] (0,0) circle (1);'
      r'\end{tikzpicture}',
    );
  });
}
