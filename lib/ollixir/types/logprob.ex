defmodule Ollixir.Types.Logprob do
  @moduledoc """
  Log probability for a token.
  """

  @type t :: %__MODULE__{
          token: String.t() | nil,
          bytes: [integer()] | nil,
          logprob: float() | nil,
          top_logprobs: [map()] | nil
        }

  defstruct [:token, :logprob, :bytes, :top_logprobs]

  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      token: map["token"],
      bytes: map["bytes"],
      logprob: map["logprob"],
      top_logprobs: map["top_logprobs"]
    }
  end

  @doc """
  Convert logprob to probability.
  """
  @spec probability(t()) :: float() | nil
  def probability(%__MODULE__{logprob: lp}) when is_number(lp), do: :math.exp(lp)
  def probability(_), do: nil
end
