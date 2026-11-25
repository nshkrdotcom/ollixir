defmodule Ollixir.Types.ShowResponse do
  @moduledoc """
  Response from show_model.
  """

  use Ollixir.Types.Base

  alias Ollixir.Types.ModelDetails

  @type t :: %__MODULE__{
          messages: [Ollixir.Types.Message.t()] | nil,
          manifests: [map()] | nil,
          voices: [String.t()] | nil,
          tensors: [map()] | nil,
          projector_info: map() | nil,
          thinking: map() | nil,
          requires: String.t() | nil,
          remote_host: String.t() | nil,
          remote_model: String.t() | nil,
          template_source: String.t() | nil,
          parser: String.t() | nil,
          renderer: String.t() | nil,
          system: String.t() | nil,
          runner: String.t() | nil,
          modified_at: String.t() | nil,
          template: String.t() | nil,
          modelfile: String.t() | nil,
          license: String.t() | nil,
          parameters: String.t() | nil,
          capabilities: [String.t()] | nil,
          details: ModelDetails.t() | nil,
          model_info: map() | nil
        }

  defstruct [
    :messages,
    :manifests,
    :voices,
    :tensors,
    :projector_info,
    :thinking,
    :requires,
    :remote_host,
    :remote_model,
    :template_source,
    :parser,
    :renderer,
    :system,
    :runner,
    :modified_at,
    :template,
    :modelfile,
    :license,
    :parameters,
    :capabilities,
    :details,
    :model_info
  ]

  def from_map(map) do
    %__MODULE__{
      messages: parse_messages(map["messages"]),
      manifests: map["manifests"],
      voices: map["voices"],
      tensors: map["tensors"],
      projector_info: map["projector_info"],
      thinking: map["thinking"],
      requires: map["requires"],
      remote_host: map["remote_host"],
      remote_model: map["remote_model"],
      template_source: map["template_source"],
      parser: map["parser"],
      renderer: map["renderer"],
      system: map["system"],
      runner: map["runner"],
      modified_at: map["modified_at"],
      template: map["template"],
      modelfile: map["modelfile"],
      license: map["license"],
      parameters: map["parameters"],
      capabilities: map["capabilities"],
      details: ModelDetails.from_map(map["details"]),
      model_info: map["model_info"] || map["modelinfo"]
    }
  end

  defp parse_messages(nil), do: nil
  defp parse_messages(messages), do: Enum.map(messages, &Ollixir.Types.Message.from_map/1)

  @doc """
  Check if model has a capability.
  """
  def has_capability?(%__MODULE__{capabilities: caps}, cap) when is_list(caps) do
    cap in caps
  end

  def has_capability?(_, _), do: false
end
