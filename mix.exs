defmodule Ollixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :ollixir,
      name: "Ollixir",
      description: "Ollixir is a complete Elixir client library for the Ollama API.",
      source_url: "https://github.com/nshkrdotcom/ollixir",
      version: "0.1.1",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: [
        name: "ollixir",
        files:
          ~w(lib assets .formatter.exs mix.exs README.md LICENSE CHANGELOG.md examples guides),
        licenses: ["MIT"],
        links: %{
          "GitHub" => "https://github.com/nshkrdotcom/ollixir"
        }
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
      {:bandit, "~> 1.10", only: :test},
      {:ex_doc, "~> 0.40.0", only: :dev, runtime: false},
      {:hf_hub, "~> 0.1.3", optional: true},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:plug, "~> 1.19"},
      {:req, "~> 0.5"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:supertester, "~> 0.5.1", only: :test}
    ]
  end

  defp docs do
    [
      main: "overview",
      assets: %{"assets" => "assets"},
      logo: "assets/ollixir.svg",
      extras: [
        {"README.md", title: "Overview", filename: "overview"},
        {"guides/getting-started.md", title: "Getting Started"},
        {"guides/ollama-setup.md", title: "Ollama Server Setup"},
        {"guides/streaming.md", title: "Streaming"},
        {"guides/tools.md", title: "Tools"},
        {"guides/structured-outputs.md", title: "Structured Outputs"},
        {"guides/thinking.md", title: "Thinking Mode"},
        {"guides/embeddings.md", title: "Embeddings"},
        {"guides/multimodal.md", title: "Multimodal"},
        {"guides/huggingface.md", title: "HuggingFace Integration"},
        {"guides/cloud-api.md", title: "Cloud API"},
        {"guides/cheatsheet.md", title: "Cheatsheet"},
        {"examples/README.md", title: "Examples", filename: "examples"},
        {"CHANGELOG.md", title: "Changelog"},
        {"LICENSE", title: "License"}
      ],
      groups_for_extras: [
        Overview: ["overview"],
        Guides: ~r/guides\/.*/,
        Examples: ["examples"],
        Project: ["CHANGELOG.md", "LICENSE"]
      ],
      groups_for_modules: [
        Client: [Ollixir],
        Errors: [
          Ollixir.ConnectionError,
          Ollixir.RequestError,
          Ollixir.ResponseError,
          Ollixir.Errors,
          Ollixir.Retry
        ],
        Helpers: [Ollixir.Image, Ollixir.Tool, Ollixir.Options, Ollixir.Options.Presets],
        HuggingFace: [Ollixir.HuggingFace],
        Web: [
          Ollixir.Web,
          Ollixir.Web.SearchResponse,
          Ollixir.Web.SearchResult,
          Ollixir.Web.FetchResponse,
          Ollixir.Web.Tools
        ],
        Types: [
          Ollixir.Types,
          Ollixir.Types.Base,
          Ollixir.Types.Logprob,
          Ollixir.Types.ToolCall,
          Ollixir.Types.Message,
          Ollixir.Types.GenerateResponse,
          Ollixir.Types.ChatResponse,
          Ollixir.Types.EmbedResponse,
          Ollixir.Types.EmbeddingsResponse,
          Ollixir.Types.ModelDetails,
          Ollixir.Types.ModelInfo,
          Ollixir.Types.ListResponse,
          Ollixir.Types.ShowResponse,
          Ollixir.Types.ProcessResponse,
          Ollixir.Types.ProgressResponse,
          Ollixir.Types.StatusResponse
        ],
        Internals: [Ollixir.Blob, Ollixir.Schemas, Ollixir.HTTPError]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test"]
  defp elixirc_paths(_), do: ["lib"]
end
