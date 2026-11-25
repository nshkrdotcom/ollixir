defmodule Ollixir.Types.ToolCall do
  @moduledoc """
  Tool call definition.
  """

  use Ollixir.Types.Base

  @type t :: %__MODULE__{
          id: String.t() | nil,
          function: map() | nil
        }

  defstruct [:id, :function]

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    function = map["function"] || map[:function]

    %__MODULE__{
      id: map["id"] || map[:id],
      function: if(is_map(function), do: normalize_function(function))
    }
  end

  defp normalize_function(%{"arguments" => args} = function) do
    Map.put(function, "arguments", parse_arguments(args))
  end

  defp normalize_function(%{arguments: args} = function) do
    Map.put(function, :arguments, parse_arguments(args))
  end

  defp normalize_function(function), do: function

  defp parse_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} when is_map(parsed) -> parsed
      _ -> args
    end
  end

  defp parse_arguments(args) when is_map(args), do: args
  defp parse_arguments(args), do: args

  @doc """
  Get the function name.
  """
  @spec name(t()) :: String.t() | nil
  def name(%__MODULE__{function: %{"name" => name}}), do: name
  def name(%__MODULE__{function: %{name: name}}), do: name
  def name(_), do: nil

  @doc """
  Get the function arguments. Invalid argument values are returned as received.
  """
  @spec arguments(t()) :: term()
  def arguments(%__MODULE__{function: %{"arguments" => args}}), do: args
  def arguments(%__MODULE__{function: %{arguments: args}}), do: args
  def arguments(_), do: %{}
end
