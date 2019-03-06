defmodule Letex do
  @moduledoc """
  Lisp-esque Let to support easy stateful lexical closures in Elixir
  """
  defmacro __using__(_opts) do
    quote do
      require unquote(__MODULE__)
      import unquote(__MODULE__)
      var!(state_agent, Letex) = nil
    end
  end

  @doc """
  Accepts a keyword-list and a do block. Initializes all the keys in the list to their associated
  values. Calls to get(key) within the let will retrieve the value bound to key.
  Calls to set(key, val) will update the state of key to val.
  Calls to update(key, arity_1_function) will update the state of key to the result of calling the
  function on the current state of the key.

  The unique feature of these lets is that they create a stateful execution context, allowing for
  the easy creation of stateful lexical closures.

  This macro achieves this by spawning agents to hold the lexical scope in which the body executes.
  However, these agents are not linked to the calling process in order to allow for the lexical
  scope to out-live the calling process. This means this state must be manually freed, or it will
  live forever using memory. If you do not need the scope to out-live the calling process, then
  you should use let_link instead (It behaves the same as let except that the agents are created
  with start_link instead of start). Otherwise you can use the free macro within the body of
  your lets in order to manage this.

  ## Examples:
  ```
  iex> use Letex
  iex> {counter, free} = let [count: 0] do
  ...> {fn -> update(:count, &(&1 + 1)) end, fn -> free() end}
  ...> end
  iex> counter.()
  1
  iex> counter.()
  2
  iex> free.()
  :ok
  ```

  Inner bindings with the same variable name as an outer binding will "shadow" the outer
  binding, meaning all references within the inner let will resolve the variable to the inner
  version (which has its own state storage), where all references within the outer let, but
  outside of the inner one will use the outer version.
  ```
  iex> use Letex
  iex> let [x: 5] do {let [x: 10] do get(:x) end, get(:x)} end
  {10, 5}
  ```
  """
  defmacro let(bindings, do: body) do
    quote do
      with {:ok, pid} <-
             Agent.start(fn ->
               Keyword.merge(unquote(bindings),
                 __parent_state_agent__: var!(state_agent, Letex),
                 __child_state_agents__: []
               )
             end),
           :ok <- add_child(var!(state_agent, Letex), pid),
           var!(state_agent, Letex) <- pid do
        unquote(body)
      end
    end
  end

  @doc """
  Takes a parent agent pid, and a child agent pid. Adds the child agent pid to the parents
  list of child agents. This is done so that when we free a parent, we can walk down the
  tree and free all of its children as well.
  """
  def add_child(nil, _), do: :ok

  def add_child(parent, child) do
    Agent.update(parent, fn state ->
      children = Keyword.get(state, :__child_state_agents__)
      Keyword.merge(state, [{:__child_state_agents__, [child | children]}])
    end)
  end

  @doc """
  Variant of let which automatically wraps the return of the let to be a pair. The first element
  is the result of evaluating the body passed to the let, and the second is a 0-arity
  function which frees the agent (and all of its children) created by the let.

  ## Examples:
  ```
  iex> use Letex
  iex> {counter, free} = let_wrapped [count: 0] do
  ...> fn -> set(:count, get(:count) + 1) end
  ...> end
  iex> counter.()
  1
  iex> counter.()
  2
  iex> free.()
  :ok
  ```
  """
  defmacro let_wrapped(bindings, do: body) do
    quote do
      let unquote(bindings) do
        {unquote(body), fn -> free() end}
      end
    end
  end

  @doc """
  A variant of let which links the agents it spawns to the current process in order to make managing
  resource utilization easier. This means that the lexical context created by the let_link will
  not be able to out-live the calling process (e.g. if you create a counter in the current process,
  hand it off to some other process to use, and then the original process ends, subsequent calls to
  the counter from the other process will fail). However if the context does not need to out-live
  the calling process, this can make it much easier to avoid leaking agents.

  ## Examples:
  ```
  iex> use Letex
  iex> counter = let_link [count: 0] do fn -> update(:count, &(&1 + 1)) end end
  iex> counter.()
  1
  iex> counter.()
  2
  ```
  """
  defmacro let_link(bindings, do: body) do
    quote do
      with {:ok, pid} <-
             Agent.start_link(fn ->
               Keyword.merge(unquote(bindings),
                 __parent_state_agent__: var!(state_agent, Letex),
                 __child_state_agents__: []
               )
             end),
           :ok <- add_child(var!(state_agent, Letex), pid),
           var!(state_agent, Letex) <- pid do
        unquote(body)
      end
    end
  end

  @doc """
  When this macro is called, it sends a stop signal to all children of the nearest layered agent,
  followed by sending a stop signal to the nearest layered agent.
  """
  defmacro free do
    quote do
      do_free(var!(state_agent, Letex))
    end
  end

  @doc """
  Function to perform the recursive freeing of agents. It recursively calls do_free for each child
  in the current Agents list of children, removes the current agent from it's parents list of
  children, and then finally stops the current Agent.
  """
  def do_free(nil), do: :ok

  def do_free(agent) do
    {children, parent} =
      Agent.get(agent, fn state ->
        {Keyword.get(state, :__child_state_agents__), Keyword.get(state, :__parent_state_agent__)}
      end)

    # Free all children recursively
    Enum.each(children, &do_free/1)

    # Remove this agent from its parents list of children
    remove_from_parent(parent, agent)

    # Stop the current agent
    Agent.stop(agent)
  end

  defp remove_from_parent(nil, _), do: :ok

  defp remove_from_parent(parent, child) do
    Agent.update(parent, fn state ->
      Keyword.merge(state, [
        {:__child_state_agents__,
         Enum.filter(Keyword.get(state, :__child_state_agents__), &(&1 != child))}
      ])
    end)
  end

  @doc """
  Accepts a symbol of a let-bound variable, and a new value. Binds the variable to the new value.
  Returns the newly set value. If the symbol passed does not match a let-bound variable in scope,
  will return an error.

  ## Examples:
  ```
  iex> use Letex
  iex> let [x: 5] do set(:x, 10) end
  10

  iex> use Letex
  iex> let [x: 5] do set(:y, 10) end
  {:error, "Unable to set binding: Binding not found"}
  ```
  """
  defmacro set(var, val) do
    quote do
      do_set(var!(state_agent, Letex), unquote(var), unquote(val))
    end
  end

  @doc """
  This function is used to actually set the variable to the new value in the appropriate agent.
  It searches for the variable to be present in the agents from the bottom to top of the hierarchy
  of the surrounding lets.
  """
  def do_set(nil, _, _), do: {:error, "Unable to set binding: Binding not found"}

  def do_set(pid, var, val) do
    pid
    |> Agent.get_and_update(fn state ->
      if var in Keyword.keys(state) do
        {val, Keyword.merge(state, [{var, val}])}
      else
        {do_set(Keyword.get(state, :__parent_state_agent__), var, val), state}
      end
    end)
  end

  @doc """
  Update the given let-bound variable by calling the given 1-arity function on it. Returns the
  result, or an error if the binding was not found in the current scope.

  ## Examples:

  ```
  iex> use Letex
  iex> let [x: 5] do update(:x, &(&1 + 1)) end
  6

  iex> use Letex
  iex> let [x: 5] do update(:y, &(&1 + 1)) end
  {:error, "Unable to update binding: Binding not found"}
  ```
  """
  defmacro update(var, func) do
    quote do
      do_update(var!(state_agent, Letex), unquote(var), unquote(func))
    end
  end

  @doc """
  This function is used to actually perform the updating action on the correct value in the
  appropriate agent.
  """
  def do_update(nil, _, _), do: {:error, "Unable to update binding: Binding not found"}

  def do_update(pid, var, func) do
    pid
    |> Agent.get_and_update(fn state ->
      if var in Keyword.keys(state) do
        val = func.(Keyword.get(state, var))
        {val, Keyword.merge(state, [{var, val}])}
      else
        {do_update(Keyword.get(state, :__parent_state_agent__), var, func), state}
      end
    end)
  end

  @doc """
  Accepts a symbol of a let-bound variable. Returns the value bound to that variable.
  If a let binds a variable that is already bound by an outer let, the inner binding will
  shadow the outer binding.

  ## Examples:
  ```
  iex> use Letex
  iex> let [x: 5] do get(:x) end
  5

  iex> use Letex
  iex> let [x: 5] do let [x: 10] do get(:x) end end
  10

  iex> use Letex
  iex> let [x: 5] do let [x: 10] do get(:y) end end
  {:error, "Failed to get value for binding: Binding not found"}
  ```
  """
  defmacro get(var) do
    quote do
      do_get(var!(state_agent, Letex), unquote(var))
    end
  end

  @doc """
  This function is used to actually retrieve the requested value from the appropriate agent.
  It fetches values in the different agents from bottom to top in the hierarchy of lets.
  Returns an error if the value is not found anywhere in the hierarchy.
  """
  def do_get(nil, _), do: {:error, "Failed to get value for binding: Binding not found"}

  def do_get(pid, val) do
    Agent.get(pid, fn state ->
      if val in Keyword.keys(state) do
        Keyword.get(state, val)
      else
        do_get(Keyword.get(state, :__parent_state_agent__), val)
      end
    end)
  end

  @doc """
  When using def to create a named function, the var used to store the current leaf of the
  tree of agents (or nil to represent the root) is not initialized to nil as it needs to be.
  This macro wraps def with a call to initialize this var to nil beforehand so that calls to let
  will function correctly within the def body.

  Apart from allowing let forms within the body of a def, they behave identically to a normal def

  ## Examples:

  ```
  defun make_counter_maker(initial_iv) do
    # Here we use let because we want this counter maker to live forever
    let [iv: initial_iv] do
      fn ->
        # Here we use let because these counters need to out-live their calling processes for
        # whatever reason. However, we want to be able to kill the agents eventually, so we
        # return a pair of functions, the first of which calls the counter, and the second
        # of which frees the agent wrapping the counter.
        let [count: get(:iv)] do
          {fn -> set(:iv, update(:count, &(&1 + 1))) end, fn -> free() end}
        end
      end
    end
  end
  ```
  """
  defmacro defun(args, do: body) do
    quote do
      def unquote(args) do
        var!(state_agent, Letex) = nil
        unquote(body)
      end
    end
  end
end
