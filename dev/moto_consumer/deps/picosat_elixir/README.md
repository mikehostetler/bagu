# Picosat

PicoSAT is a satisfiability (SAT) solver for boolean variables in boolean expressions. 

A SAT solver can determine if it is possible to find assignments to boolean variables that would 
make a given set of expressions true. If it's satisfiable, it can also show a set of assignments 
that make the expression true. Many problems can be broken down into a large SAT problem 
(perhaps with thousands of variables), so SAT solvers have a variety of uses.

Like many SAT solvers, PicoSAT requires input in [CNF (conjunctive normal form)](https://en.wikipedia.org/wiki/Conjunctive_normal_form).
CNF is built from these building blocks:

  
* _R term_: A term is either a boolean variable (in this library, expressed as an integer value), 
e.g, `4` or a negated boolean variable, e.g., `-4`. 
* _R clause_: A clause is a set of one or more terms, connected with OR (written here as |); boolean variables may not repeat inside a clause. 
* _R expression_: An expression is a set of one or more clauses, each connected by AND (written here as &).

Any boolean expression can be converted into CNF.

The output of the solver is in terms of satisfiability, either an expression is _satisfiable_, or _not satisfiable_;
an expression which cannot be solved for is considered _unknown_.

If satisfiable, the value returned is a list of the variable settings that satisfy all formulas.
For example, the result `{:ok, [1, -2, -3, -4, 5]}` shows that there is a solution with variables
`1` and `5` set to true, `2-4` set to false.

An example of an unsatisfiable formula is `[[-1], [1]]` which states that variable `1` must always be true,
and always be false at the same time, which is obviously impossible.

PicoSAT was written by Armin Biere, and this documentation is derived from the PicoSAT man page written
by David A. Wheeler.

## Example

Consider a group of people (Bob, Alice, Paul, Jane) who want to eat dinner. They have three restaurants to choose
from, and they will only be able to sate their hunger if they can all agree on at least one place to eat.

We define variables for each restaurant, `1` through `3`. A vote for the restaurant is a positive number, and
a vote against is negative.

So each person gives their votes to a neutral third party (the solver), and their votes are either for,
or against, one or more restaurants. Given a vote of `[1, 2, -3]`, this is saying that the person is fine with
either restaurant `1`, or `2`, but not `3`.

Let's see what happens for the following votes:

(x₁ ∨ x₂ ∨ ¬x₃) ∧ (x₂ ∨ x₃) ∧ (¬x₂) ∧ (¬x₁ ∨ x₃) 

```elixir
iex> votes = [ [1, 2, -3], [2, 3], [-2], [-1, 3] ]
...> Picosat.solve(votes)
{:ok, [1, -2, 3]}
```

Nice! We have a solution, this tells us that visiting restaurant `1` and `3` but not `2` will satisfy everyone.

Happy solving!

## Installation

PicoSAT can be installed by adding `picosat_elixir` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:picosat_elixir, "~> 0.2.0"}
  ]
end
```

## Building on Windows

Building on windows requires the Microsoft build tools (for C++/C) and `mix deps.compile` being run in a shell where the environment is set up correctly. This can be done by running the `vcvarsall.bat` script provided by the framework. The quickest way to get that is to paste this (replace the visual studio installation path accordingly) into the `run` dialog (<kbd>Win</kbd>+<kbd>R</kbd>).

```bat
cmd /K "C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\vcvarsall.bat" amd64
```

## License

Apache 2.0, see `LICENSE.md`
