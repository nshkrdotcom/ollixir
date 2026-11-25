defmodule Ollixir.Types.UserResponse do
  @moduledoc "Account information for the user signed into the Ollama server."
  use Ollixir.Types.Base

  @type t :: %__MODULE__{
          id: String.t() | nil,
          email: String.t() | nil,
          name: String.t() | nil,
          bio: String.t() | nil,
          avatarurl: String.t() | nil,
          firstname: String.t() | nil,
          lastname: String.t() | nil,
          plan: String.t() | nil
        }
  defstruct [:id, :email, :name, :bio, :avatarurl, :firstname, :lastname, :plan]

  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      id: map["id"],
      email: map["email"],
      name: map["name"],
      bio: map["bio"],
      avatarurl: map["avatarurl"],
      firstname: map["firstname"],
      lastname: map["lastname"],
      plan: map["plan"]
    }
  end
end
