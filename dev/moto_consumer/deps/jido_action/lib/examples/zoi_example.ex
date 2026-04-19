# covers: jido_action.scaffolding.examples_and_support
defmodule Jido.Examples.ZoiExample do
  @moduledoc """
  Production-quality example demonstrating Zoi schema features in Jido actions.

  This action showcases best practices for using Zoi schemas:
  - Email validation with transformations (trim, downcase)
  - Password validation with refinements
  - Enums for constrained choices
  - Optional fields with defaults
  - Nested object schemas
  - Output validation
  - Custom refinements for business logic

  ## Example Usage

      iex> params = %{
      ...>   user: %{
      ...>     email: "  JOHN@EXAMPLE.COM  ",
      ...>     password: "SecurePass123!",
      ...>     name: "John Doe"
      ...>   },
      ...>   priority: :high,
      ...>   metadata: %{source: "web"}
      ...> }
      iex> {:ok, result} = Jido.Examples.ZoiExample.run(params, %{})
      iex> result.user.email
      "john@example.com"
      iex> result.status
      :validated

  ## Zoi Features Demonstrated

  ### Transformations
  - `Zoi.trim/1` - Remove leading/trailing whitespace
  - `Zoi.to_downcase/1` - Convert to lowercase

  ### Validators
  - `Zoi.email/1` - Email format validation
  - `Zoi.min/2` and `Zoi.max/2` - Length/value constraints
  - `Zoi.regex/2` - Pattern matching

  ### Refinements
  - `Zoi.refine/2` - Custom validation logic

  ### Type System
  - `Zoi.object/1` - Nested object schemas
  - `Zoi.enum/1` - Enumerated values
  - `Zoi.optional/1` - Optional fields
  - `Zoi.default/2` - Default values
  """

  use Jido.Action,
    name: "zoi_example",
    description: "Demonstrates Zoi schema capabilities with user registration validation",
    category: "examples",
    tags: ["zoi", "validation", "example"],
    vsn: "2.0.0",
    schema:
      Zoi.object(%{
        user:
          Zoi.object(%{
            email:
              Zoi.string()
              |> Zoi.trim()
              |> Zoi.to_downcase()
              |> Zoi.regex(Zoi.Regexes.email(), message: "Invalid email format"),
            password:
              Zoi.string(description: "User password")
              |> Zoi.min(8, message: "Password must be at least 8 characters")
              |> Zoi.max(128)
              |> Zoi.regex(~r/[A-Z]/, message: "Password must contain uppercase letter")
              |> Zoi.regex(~r/[a-z]/, message: "Password must contain lowercase letter")
              |> Zoi.regex(~r/[0-9]/, message: "Password must contain digit")
              |> Zoi.refine(fn password ->
                if String.contains?(password, ["password", "123456", "qwerty"]) do
                  {:error, "Password is too common"}
                else
                  :ok
                end
              end),
            name:
              Zoi.string(description: "User's full name")
              |> Zoi.trim()
              |> Zoi.min(1)
              |> Zoi.max(100),
            age:
              Zoi.integer(description: "User's age")
              |> Zoi.min(13, message: "Must be at least 13 years old")
              |> Zoi.max(120)
              |> Zoi.optional()
          }),
        priority:
          Zoi.enum([:low, :normal, :high], description: "Registration priority")
          |> Zoi.default(:normal)
          |> Zoi.optional(),
        metadata:
          Zoi.object(%{
            source:
              Zoi.enum([:web, :mobile, :api], description: "Registration source")
              |> Zoi.default(:web)
              |> Zoi.optional(),
            referrer:
              Zoi.string(description: "Referral code")
              |> Zoi.trim()
              |> Zoi.to_upcase()
              |> Zoi.optional()
          })
          |> Zoi.optional()
      }),
    output_schema:
      Zoi.object(%{
        user:
          Zoi.object(%{
            email: Zoi.string(),
            name: Zoi.string(),
            age: Zoi.integer() |> Zoi.optional()
          }),
        priority: Zoi.enum([:low, :normal, :high]),
        status: Zoi.enum([:validated, :pending, :approved]),
        timestamp: Zoi.integer()
      })

  @doc """
  Validates user registration data with comprehensive checks.

  This action demonstrates how validated and transformed parameters
  flow through the action pipeline. The input params are automatically:
  - Validated against schema constraints
  - Transformed (trimmed, case-converted)
  - Checked against custom refinements

  ## Parameters

  - `:user` - User object with email, password, name, and optional age
  - `:priority` - Registration priority (defaults to :normal)
  - `:metadata` - Optional metadata about the registration

  ## Returns

  - `{:ok, result}` - Validated user data with status and timestamp
  - `{:error, reason}` - Validation or processing errors
  """
  def run(params, _context) do
    # At this point, params are already validated and transformed:
    # - email is trimmed and lowercased
    # - password passed all refinements
    # - name is trimmed
    # - priority has default if not provided
    # - metadata.source has default if not provided
    # - metadata.referrer is uppercased if provided

    result = %{
      user: %{
        email: params.user.email,
        name: params.user.name,
        age: Map.get(params.user, :age)
      },
      priority: params[:priority] || :normal,
      status: determine_status(params[:priority]),
      timestamp: System.system_time(:second)
    }

    {:ok, result}
  end

  # Private helper to demonstrate business logic after validation
  defp determine_status(:high), do: :approved
  defp determine_status(_), do: :pending
end
