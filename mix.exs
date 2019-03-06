defmodule Letex.MixProject do
  use Mix.Project

  def project do
    [
      app: :letex,
      version: "0.1.1",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Docs
      name: "Letex",
      source_url: "https://github.com/spatchkaa/letex",
      docs: [
        main: "Letex",
        extras: ["README.md"]
      ],

      # Hex
      description: "Lisp-esque Let to support easy stateful lexical closures in Elixir",
      package: [
        maintainers: ["Richard Claus"],
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/spatchkaa/letex"}
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
    ]
  end
end
