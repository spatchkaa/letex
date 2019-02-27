# Letex

Letex provides a Lisp-esque let macro in order to support easy stateful lexical closures.

Use of this library undermines the nature of immutable data in elixir. This should not be
done lightly. I find it mainly useful in development for rapidly prototyping a solution in
the repl. Use in production at your own peril.

Examples:
A function which creates a counter might look something like this in Common Lisp:
```
(defun make-counter ()
  (let ((counter 0))
    (lambda ()
      (incf counter))))

CL-USER> (defvar *counter* (make-counter))
CL-USER> (funcall *counter*)
1
CL-USER> (funcall *counter*)
2
```

We can achieve similar functionality in elixir fairly easily using an Agent to store our state.
```
defmodule CounterMaker do
  def make_counter do
    {:ok, pid} = Agent.start(fn -> 0 end)
    fn -> Agent.get_and_update(pid, fn x -> {x+1, x+1} end) end
  end
end
iex> counter = CounterMaker.make_counter.()
iex> counter.()
1
iex> counter.()
2
```

However, suppose now we want a counter-maker-maker-maker which makes counter-maker-makers which
each create counter-makers which can create counters with initial values which depend on how
many times the counters they have created have counted. Here is what this might look like in
Common Lisp:
```
(defun make-counter-maker-maker (initial-iv)
  (let ((iv initial-iv))
    (lambda ()
      (let ((inner-iv iv))
        (lambda ()
          (let ((counter inner-iv))
            (lambda ()
              (progn
                (incf iv)
                (incf inner-iv)
                (incf counter)))))))))
```

And here is what a usage example might look like:
```
CL-USER> (defvar *counter-maker-maker* (make-counter-maker-maker 0))
CL-USER> (defvar *counter-maker-1* (funcall *counter-maker-maker*))
CL-USER> (defvar *counter-1* (funcall *counter-maker-1*))
CL-USER> (funcall *counter-1*)
1
CL-USER> (funcall *counter-1*)
2
CL-USER> (defvar *counter-2* (funcall *counter-maker-1*))
CL-USER> (funcall *counter-2*)
3
CL-USER> (funcall *counter-2*)
4
CL-USER> (funcall *counter-1*)
3
CL-USER> (defvar *counter-maker-2* (funcall *counter-maker-maker*))
CL-USER> (defvar *counter-3* (funcall *counter-maker-2*))
CL-USER> (funcall *counter-3*)
6
CL-USER> (funcall *counter-3*)
7
CL-USER> (defvar *counter-4* (funcall *counter-maker-2*))
CL-USER> (funcall *counter-4*)
8
CL-USER> (defvar *counter-5* (funcall *counter-maker-1*))
CL-USER> (funcall *counter-5*)
6
```

Implementing this same functionality in elixir is suddenly much more cumbersome. It is
certainly possible to achieve this functionality using Genservers, but the solution would
be significantly more complex than the lisp alternative.

The deeper these things nest, the more cumbersome the elixir implementation gets.
Letex makes this easy by abstracting away the creating/managing of processes to hold
state, and providing us with a simulation of mutable lexical data. This lets us very closely
mirror the Lisp implementation.
```
use Letex

defun make_counter_maker_maker(initial_iv) do
  let [iv: initial_iv] do
    fn ->
      let [inner_iv: get(:iv)] do
        fn ->
          let [counter: get(:inner_iv)] do
            fn ->
              update(:iv, &(&1 + 1))
              update(:inner_iv, &(&1 + 1))
              update(:counter, &(&1 + 1))
            end
          end
        end
      end
    end
  end
end
```

## Installation

add `letex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:letex, "~> 0.1.0"}
  ]
end
```

## Copyright and License

Copyright (c) 2019, Richard Claus.

Letex source code is licensed under the [MIT License](LICENSE.md).
