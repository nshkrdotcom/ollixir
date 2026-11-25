defmodule Ollixir.TestAdapter do
  @moduledoc false

  def options(handler) do
    [plugins: [fn request -> attach(request, handler) end]]
  end

  defp attach(request, handler) do
    if Version.match?(to_string(Application.spec(:req, :vsn)), ">= 0.7.0") do
      case handler do
        module when is_atom(module) ->
          %{request | adapter: module}

        fun ->
          request = Req.Request.put_private(request, :ollixir_test_adapter, fun)
          %{request | adapter: __MODULE__}
      end
    else
      fun = if is_atom(handler), do: &handler.run/1, else: handler
      %{request | adapter: fun}
    end
  end

  def run(request), do: request.private.ollixir_test_adapter.(request)
end
