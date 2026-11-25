defmodule Ollixir.StreamWorker do
  @moduledoc false

  alias Ollixir.{ConnectionError, RequestError, ResponseError}

  def run(fun) do
    fun.()
  rescue
    error in [ConnectionError, RequestError, ResponseError] ->
      {:error, error}

    error ->
      {:error,
       RequestError.exception(
         message: "Stream request failed",
         reason: {:exception, error.__struct__}
       )}
  end
end
