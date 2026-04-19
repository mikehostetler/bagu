defmodule Picosat.Solver do
  @moduledoc false

  @type reason :: :unsatisfiable
                | :unknown
                | :picosat_error
  @type clauses :: [clause]
  @type clause :: [variable]
  @type variable :: integer
  @type solution :: [variable]

  @spec solve(clauses) :: {:ok, solution} | {:error, reason}
  def solve(args) do
    case :picosat_nif.solve(args) do
      err when err in [:unsatisfiable, :unknown, :picosat_error] -> 
        {:error, err}
      solution when is_list(solution) ->
        {:ok, solution}
    end
  end
end
