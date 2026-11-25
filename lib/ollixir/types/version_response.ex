defmodule Ollixir.Types.VersionResponse do
  @moduledoc "Version reported by the configured Ollama server."
  use Ollixir.Types.Base

  @type t :: %__MODULE__{version: String.t() | nil}
  defstruct [:version]

  @spec from_map(map()) :: t()
  def from_map(map), do: %__MODULE__{version: map["version"]}
end
