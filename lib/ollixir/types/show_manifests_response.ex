defmodule Ollixir.Types.ShowManifestsResponse do
  @moduledoc "Response from showing all manifests of a model."
  use Ollixir.Types.Base

  alias Ollixir.Types.ShowResponse

  @type t :: %__MODULE__{manifests: [ShowResponse.t()], license: String.t() | nil}
  defstruct [:license, manifests: []]

  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      manifests: Enum.map(map["manifests"] || [], &ShowResponse.from_map/1),
      license: map["license"]
    }
  end
end
