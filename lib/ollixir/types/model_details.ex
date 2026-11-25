defmodule Ollixir.Types.ModelDetails do
  @moduledoc """
  Model details structure.
  """

  use Ollixir.Types.Base

  @type t :: %__MODULE__{
          embedding_length: integer() | nil,
          context_length: integer() | nil,
          runner: String.t() | nil,
          parent_model: String.t() | nil,
          format: String.t() | nil,
          family: String.t() | nil,
          families: [String.t()] | nil,
          parameter_size: String.t() | nil,
          quantization_level: String.t() | nil
        }

  defstruct [
    :embedding_length,
    :context_length,
    :runner,
    :parent_model,
    :format,
    :family,
    :families,
    :parameter_size,
    :quantization_level
  ]

  def from_map(nil), do: nil

  def from_map(map) do
    %__MODULE__{
      embedding_length: map["embedding_length"],
      context_length: map["context_length"],
      runner: map["runner"],
      parent_model: map["parent_model"],
      format: map["format"],
      family: map["family"],
      families: map["families"],
      parameter_size: map["parameter_size"],
      quantization_level: map["quantization_level"]
    }
  end
end
