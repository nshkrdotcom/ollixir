defmodule Ollixir.Types.ServerStatusResponse do
  @moduledoc "Server status, including the cloud disabled flag and its source."
  use Ollixir.Types.Base

  @type t :: %__MODULE__{cloud: map() | nil}
  defstruct [:cloud]

  @spec from_map(map()) :: t()
  def from_map(map), do: %__MODULE__{cloud: map["cloud"]}
end
