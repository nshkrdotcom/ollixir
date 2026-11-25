defmodule Ollixir.Types.SystemOneResponse do
  @moduledoc """
  System One response. Answer values retain their native JSON fields; in
  particular, `noul` is a numeric probability, not a boolean, and score
  answers may include a legend and per-choice probabilities.
  """
  use Ollixir.Types.Base

  @type t :: %__MODULE__{
          model: String.t() | nil,
          answers: %{optional(String.t()) => map()},
          usage: map() | nil,
          prompt_eval_cached_count: non_neg_integer() | nil
        }

  defstruct [:model, :usage, :prompt_eval_cached_count, answers: %{}]

  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      model: map["model"],
      answers: map["answers"] || %{},
      usage: map["usage"],
      prompt_eval_cached_count: map["prompt_eval_cached_count"]
    }
  end
end
