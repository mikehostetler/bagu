defmodule Jido.Instruction do
  @moduledoc """
  Instructions in Jido represent discrete units of work that can be planned, validated, and executed by agents.
  Think of them as "work orders" that tell agents exactly what needs to be done and how to do it.

  ## Core Concepts

  An Instruction wraps an Action module with everything it needs to execute:
  - The Action to perform (required)
  - Parameters for the action
  - Execution context
  - Runtime options

  ## Structure

  Each Instruction contains:

  ```elixir
  %Instruction{
    id: "inst_abc123",           # Unique identifier
    action: MyApp.Actions.DoTask, # The action module to execute
    params: %{value: 42},        # Parameters for the action
    context: %{user_id: "123"},  # Execution context
    opts: [retry: true],         # Runtime options
  }
  ```

  ## Creating Instructions

  Instructions support multiple creation formats for convenience:

  ### 1. Full Struct
  ```elixir
  %Instruction{
    action: MyApp.Actions.ProcessOrder,
    params: %{order_id: "123"},
    context: %{tenant_id: "456"}
  }
  ```

  ### 2. Action Module Only
  ```elixir
  MyApp.Actions.ProcessOrder
  ```

  ### 3. Action With Parameters
  ```elixir
  {MyApp.Actions.ProcessOrder, %{order_id: "123"}}
  ```

  ### 4. Factory Function
  ```elixir
  Instruction.new!(%{
    action: MyApp.Actions.ProcessOrder,
    params: %{order_id: "123"},
    context: %{tenant_id: "456"}
  })
  ```

  ## Working with Instructions

  ### Normalization

  Convert various input formats to standard instruction structs:

  ```elixir
  # Normalize a single instruction
  {:ok, [instruction]} = Instruction.normalize(MyApp.Actions.ProcessOrder)

  # Normalize with context
  {:ok, instructions} = Instruction.normalize(
    [
      MyApp.Actions.ValidateOrder,
      {MyApp.Actions.ProcessOrder, %{priority: "high"}}
    ],
    %{tenant_id: "123"}  # Shared context
  )
  ```

  ### Validation

  Ensure instructions use allowed actions:

  ```elixir
  allowed_actions = [
    MyApp.Actions.ValidateOrder,
    MyApp.Actions.ProcessOrder
  ]

  :ok = Instruction.validate_allowed_actions(instructions, allowed_actions)
  ```

  ## Common Patterns

  ### 1. Exec Definition
  ```elixir
  instructions = [
    MyApp.Actions.ValidateInput,
    {MyApp.Actions.ProcessData, %{format: "json"}},
    MyApp.Actions.SaveResults
  ]
  ```

  ### 2. Conditional Execution
  ```elixir
  instructions = [
    MyApp.Actions.ValidateOrder,
    {MyApp.Actions.CheckInventory, %{strict: true}},
    # Add fulfillment only if in stock
    if has_stock? do
      {MyApp.Actions.FulfillOrder, %{warehouse: "main"}}
    end
  ]
  |> Enum.reject(&is_nil/1)
  ```

  ### 3. Context Sharing
  ```elixir
  # All instructions share common context
  {:ok, instructions} = Instruction.normalize(
    [ValidateUser, ProcessOrder, NotifyUser],
    %{
      request_id: "req_123",
      tenant_id: "tenant_456",
    }
  )
  ```

  ## See Also

  - `Jido.Action` - Action behavior and implementation
  - `Jido.Runner` - Instruction execution
  - `Jido.Agent` - Agent-based execution
  """

  alias Jido.Action.Error
  alias Jido.Instruction

  # Define Zoi schema for instruction
  @schema Zoi.struct(
            __MODULE__,
            %{
              id:
                Zoi.string(description: "Unique instruction identifier")
                |> Zoi.optional(),
              action:
                Zoi.atom(description: "Action module to execute")
                |> Zoi.refine({__MODULE__, :validate_action_module, []}),
              params: Zoi.map(description: "Parameters for the action") |> Zoi.default(%{}),
              context: Zoi.map(description: "Execution context") |> Zoi.default(%{}),
              opts: Zoi.list(Zoi.any(), description: "Runtime options") |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @type action_module :: module()
  @type action_params :: map()
  @type action_tuple :: {action_module(), action_params()}
  @type instruction :: action_module() | action_tuple() | t()
  @type instruction_list :: [instruction()]

  @doc false
  def validate_action_module(value, _opts \\ []) do
    cond do
      not is_atom(value) ->
        {:error, "must be an atom"}

      is_nil(value) ->
        {:error, "cannot be nil"}

      true ->
        :ok
    end
  end

  @doc """
  Creates a new Instruction struct from a map or keyword list of attributes.
  Returns the struct directly or raises an error.

  ## Parameters
    * `attrs` - Map or keyword list containing instruction attributes:
      * `:action` - Action module (required)
      * `:params` - Map of parameters (optional, default: %{})
      * `:context` - Context map (optional, default: %{})
      * `:opts` - Keyword list of options (optional, default: [])

  ## Returns
    * `%Instruction{}` - Successfully created instruction

  ## Raises
    * `Jido.Action.Error` - If action is missing or invalid

  ## Examples

      iex> Instruction.new!(%{action: MyAction, params: %{value: 1}})
      %Instruction{action: MyAction, params: %{value: 1}}

      iex> Instruction.new!(action: MyAction)
      %Instruction{action: MyAction}

      iex> Instruction.new!(%{params: %{value: 1}})
      ** (Jido.Action.Error) missing action
  """
  @spec new!(map() | keyword()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, instruction} ->
        instruction

      {:error, error} when is_exception(error) ->
        raise error

      {:error, reason} ->
        raise Error.validation_error("Invalid instruction configuration", %{
                reason: reason
              })
    end
  end

  @doc """
  Creates a new Instruction struct from a map or keyword list of attributes.

  ## Parameters
    * `attrs` - Map or keyword list containing instruction attributes:
      * `:action` - Action module (required)
      * `:params` - Map of parameters (optional, default: %{})
      * `:context` - Context map (optional, default: %{})
      * `:opts` - Keyword list of options (optional, default: [])
      * `:id` - String identifier (optional, defaults to UUID)

  ## Returns
    * `{:ok, %Instruction{}}` - Successfully created instruction
    * `{:error, :missing_action}` - If action is not provided
    * `{:error, :invalid_action}` - If action is not a module

  ## Examples

      iex> Instruction.new(%{action: MyAction, params: %{value: 1}})
      {:ok, %Instruction{action: MyAction, params: %{value: 1}}}

      iex> Instruction.new(action: MyAction)
      {:ok, %Instruction{action: MyAction}}

      iex> Instruction.new(%{params: %{value: 1}})
      {:error, :missing_action}
  """
  @spec new(map() | keyword()) ::
          {:ok, t()} | {:error, :missing_action | :invalid_action | term()}
  def new(attrs) when is_list(attrs) do
    new(Map.new(attrs))
  end

  def new(%{} = attrs) do
    with :ok <- validate_action_present(attrs),
         :ok <- validate_action_is_atom(attrs) do
      attrs
      |> apply_defaults()
      |> parse_with_zoi()
    end
  end

  def new(_), do: {:error, :missing_action}

  @doc """
  Normalizes a single instruction into an instruction struct. Unlike normalize/3,
  this function enforces that the input must be a single instruction and returns
  a single instruction struct rather than a list.

  ## Parameters
    * `input` - One of:
      * Single instruction struct (%Instruction{})
      * Single action module (MyApp.Actions.ProcessOrder)
      * Action tuple with params ({MyApp.Actions.ProcessOrder, %{order_id: "123"}})
      * Action tuple with empty params ({MyApp.Actions.ProcessOrder, %{}})
    * `context` - Optional context map to merge into the instruction (default: %{})
    * `opts` - Optional keyword list of options (default: [])

  ## Returns
    * `{:ok, %Instruction{}}` - Successfully normalized instruction
    * `{:error, term()}` - If normalization fails

  ## Examples

      iex> Instruction.normalize_single(MyApp.Actions.ProcessOrder)
      {:ok, %Instruction{action: MyApp.Actions.ProcessOrder}}

      iex> Instruction.normalize_single({MyApp.Actions.ProcessOrder, %{order_id: "123"}})
      {:ok, %Instruction{action: MyApp.Actions.ProcessOrder, params: %{order_id: "123"}}}
  """
  @spec normalize_single(instruction(), map() | nil, keyword()) :: {:ok, t()} | {:error, term()}
  def normalize_single(input, context \\ %{}, opts \\ [])

  # Already normalized instruction - just merge context and opts
  def normalize_single(%__MODULE__{} = instruction, context, opts) do
    context = context || %{}
    merged_opts = Keyword.merge(instruction.opts, opts)
    {:ok, %{instruction | context: Map.merge(instruction.context, context), opts: merged_opts}}
  end

  # Single action module
  def normalize_single(action, context, opts) when is_atom(action) do
    context = context || %{}
    {:ok, new!(%{action: action, params: %{}, context: context, opts: opts})}
  end

  # Action tuple with params
  def normalize_single({action, params}, context, opts) when is_atom(action) do
    context = context || %{}

    case normalize_params(params) do
      {:ok, normalized_params} ->
        {:ok, new!(%{action: action, params: normalized_params, context: context, opts: opts})}

      error ->
        error
    end
  end

  # Action tuple with context
  def normalize_single({action, params, item_context}, context, opts) when is_atom(action) do
    context = context || %{}
    item_context = item_context || %{}
    merged_context = Map.merge(item_context, context)

    case normalize_params(params) do
      {:ok, normalized_params} ->
        {:ok,
         new!(%{
           action: action,
           params: normalized_params,
           context: merged_context,
           opts: opts
         })}

      error ->
        error
    end
  end

  # Action tuple with context and opts
  def normalize_single({action, params, item_context, item_opts}, context, opts)
      when is_atom(action) do
    context = context || %{}
    item_context = item_context || %{}
    merged_context = Map.merge(item_context, context)

    item_opts = item_opts || []
    merged_opts = Keyword.merge(item_opts, opts)

    case normalize_params(params) do
      {:ok, normalized_params} ->
        {:ok,
         new!(%{
           action: action,
           params: normalized_params,
           context: merged_context,
           opts: merged_opts
         })}

      error ->
        error
    end
  end

  # Invalid format
  def normalize_single(invalid, _context, _opts) do
    {:error, Error.execution_error("Invalid instruction format", %{instruction: invalid})}
  end

  @doc """
  Normalizes instruction shorthand input into instruction structs. Accepts a variety of input formats
  and returns a list of normalized instruction structs.

  ## Parameters
    * `input` - One of:
      * Single instruction struct (%Instruction{})
      * List of instruction structs
      * Single action module (MyApp.Actions.ProcessOrder)
      * Action tuple with params ({MyApp.Actions.ProcessOrder, %{order_id: "123"}})
      * Action tuple with empty params ({MyApp.Actions.ProcessOrder, %{}})
      * Action tuple with context ({MyApp.Actions.ProcessOrder, %{}, %{tenant_id: "123"}})
      * Action tuple with opts ({MyApp.Actions.ProcessOrder, %{}, %{}, [retry: true]})
      * List of any combination of the above formats
    * `context` - Optional context map to merge into all instructions (default: %{})
    * `opts` - Optional keyword list of options (default: [])

  ## Returns
    * `{:ok, [%Instruction{}]}` - List of normalized instruction structs
    * `{:error, term()}` - If normalization fails

  ## Examples

      iex> Instruction.normalize(MyApp.Actions.ProcessOrder)
      {:ok, [%Instruction{action: MyApp.Actions.ProcessOrder}]}

      iex> Instruction.normalize({MyApp.Actions.ProcessOrder, %{order_id: "123"}})
      {:ok, [%Instruction{action: MyApp.Actions.ProcessOrder, params: %{order_id: "123"}}]}

      iex> Instruction.normalize([
      ...>   MyApp.Actions.ValidateOrder,
      ...>   {MyApp.Actions.ProcessOrder, %{priority: "high"}},
      ...>   {MyApp.Actions.NotifyUser, %{}, %{user_id: "123"}}
      ...> ])
      {:ok, [%Instruction{...}, %Instruction{...}, %Instruction{...}]}
  """
  @spec normalize(instruction() | instruction_list(), map() | nil, keyword()) ::
          {:ok, [t()]} | {:error, term()}
  def normalize(input, context \\ %{}, opts \\ [])

  # Handle lists by recursively normalizing each element
  def normalize(instructions, context, opts) when is_list(instructions) do
    with :ok <- validate_no_nested_lists(instructions) do
      normalize_instruction_list(instructions, context || %{}, opts)
    end
  end

  # Single instruction - normalize and wrap in list
  def normalize(instruction, context, opts) do
    case normalize_single(instruction, context, opts) do
      {:ok, normalized} -> {:ok, [normalized]}
      error -> error
    end
  end

  @doc """
  Same as `normalize/3` but raises on error.

  ## Parameters
    * `instruction` - Instruction to normalize
    * `context` - Optional context map to merge
    * `opts` - Optional options to merge

  ## Returns
    * `[t()]` - List of normalized instructions

  ## Raises
    * `Jido.Action.Error` - If instruction cannot be normalized

  ## Examples
      iex> Instruction.normalize!({MyAction, %{value: 42}})
      [%Instruction{action: MyAction, params: %{value: 42}}]

      iex> Instruction.normalize!(MyAction)
      [%Instruction{action: MyAction, params: %{}}]
  """
  @spec normalize!(instruction() | instruction_list(), map() | nil, keyword()) :: [t()]
  def normalize!(instruction, context \\ nil, opts \\ []) do
    case normalize(instruction, context, opts) do
      {:ok, instructions} -> instructions
      {:error, error} -> raise error
    end
  end

  @doc """
  Validates that all instructions use allowed actions.

  ## Parameters
    * `instructions` - List of instruction structs
    * `allowed_actions` - List of allowed action modules

  ## Returns
    * `:ok` - All actions are allowed
    * `{:error, term()}` - If any action is not allowed

  ## Examples
      iex> instructions = [%Instruction{action: MyAction}, %Instruction{action: OtherAction}]
      iex> Instruction.validate_allowed_actions(instructions, [MyAction])
      {:error, "Actions not allowed: OtherAction"}

      iex> instructions = [%Instruction{action: MyAction}]
      iex> Instruction.validate_allowed_actions(instructions, [MyAction])
      :ok
  """
  @spec validate_allowed_actions(t() | [t()], [module()]) :: :ok | {:error, term()}
  def validate_allowed_actions(%Instruction{} = instruction, allowed_actions) do
    validate_allowed_actions([instruction], allowed_actions)
  end

  def validate_allowed_actions(instructions, allowed_actions) when is_list(instructions) do
    unregistered =
      instructions
      |> Enum.map(& &1.action)
      |> Enum.reject(&(&1 in allowed_actions))

    if Enum.empty?(unregistered) do
      :ok
    else
      unregistered_str = Enum.join(unregistered, ", ")

      {:error,
       Error.config_error("Actions not allowed: #{unregistered_str}", %{
         actions: unregistered,
         allowed_actions: allowed_actions
       })}
    end
  end

  # Private helpers

  # Helpers for new/1
  defp validate_action_present(attrs) do
    if Map.has_key?(attrs, :action), do: :ok, else: {:error, :missing_action}
  end

  defp validate_action_is_atom(attrs) do
    if is_atom(Map.get(attrs, :action)), do: :ok, else: {:error, :invalid_action}
  end

  defp apply_defaults(attrs) do
    attrs
    |> Map.put_new_lazy(:id, &Uniq.UUID.uuid7/0)
    |> Map.update(:params, %{}, fn v -> if is_nil(v), do: %{}, else: v end)
    |> Map.update(:context, %{}, fn v -> if is_nil(v), do: %{}, else: v end)
    |> Map.update(:opts, [], fn v -> if is_nil(v), do: [], else: v end)
  end

  defp parse_with_zoi(attrs_with_defaults) do
    case Zoi.parse(@schema, attrs_with_defaults) do
      {:ok, validated_struct} ->
        {:ok, validated_struct}

      {:error, zoi_errors} ->
        error =
          Error.validation_error(
            "Invalid instruction configuration",
            %{errors: format_zoi_errors(zoi_errors)}
          )

        {:error, error}
    end
  end

  # Helpers for normalize/3
  defp validate_no_nested_lists(instructions) do
    if Enum.any?(instructions, &is_list/1) do
      {:error,
       Error.execution_error("Invalid instruction format: nested lists are not allowed", %{
         instructions: instructions
       })}
    else
      :ok
    end
  end

  defp normalize_instruction_list(instructions, context, opts) do
    instructions
    |> Enum.reduce_while({:ok, []}, fn instruction, {:ok, acc} ->
      case normalize_single(instruction, context, opts) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        error -> {:halt, error}
      end
    end)
    |> then(fn
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end)
  end

  defp format_zoi_errors(errors) when is_list(errors) do
    Enum.map(errors, fn
      %{path: path, message: message} = error ->
        %{
          path: path,
          message: message,
          code: Map.get(error, :code)
        }

      error ->
        %{message: inspect(error)}
    end)
  end

  defp normalize_params(nil), do: {:ok, %{}}
  defp normalize_params(params) when is_map(params), do: {:ok, params}

  defp normalize_params(params) when is_list(params) do
    if Keyword.keyword?(params) do
      {:ok, Map.new(params)}
    else
      {:error,
       Error.execution_error(
         "Invalid params format. Params must be a map or keyword list.",
         %{
           params: params,
           expected_format: "%{key: value} or [key: value]"
         }
       )}
    end
  end

  defp normalize_params(invalid) do
    {:error,
     Error.execution_error(
       "Invalid params format. Params must be a map or keyword list.",
       %{
         params: invalid,
         expected_format: "%{key: value} or [key: value]"
       }
     )}
  end
end
