defmodule Ollixir.Types.ModelRecommendationsResponse do
  @moduledoc "Experimental recommendations and optional application mappings."
  use Ollixir.Types.Base

  @type t :: %__MODULE__{recommendations: [map()], mappings: map() | nil}
  defstruct [:mappings, recommendations: []]

  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      recommendations: map["recommendations"] || [],
      mappings: map["mappings"]
    }
  end
end
