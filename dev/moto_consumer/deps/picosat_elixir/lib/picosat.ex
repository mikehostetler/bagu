defmodule Picosat do
  @moduledoc File.read!("README.md")

  @type clauses :: Picosat.Solver.clauses()
  @type solution :: Picosat.Solver.solution()
  @type reason :: Picosat.Solver.reason()

  @doc """
  Pass a list of clauses to PicoSAT to solve for

  A clause is a list of variables, as integers

  ## Example

      iex> Picosat.solve([[1, 2, -3], [2, 3], [-2], [-1, 3]])
      {:ok, [1, -2, 3]}

  """
  @spec solve(clauses) :: {:ok, solution} | {:error, reason}
  defdelegate solve(clauses), to: Picosat.Solver
end
