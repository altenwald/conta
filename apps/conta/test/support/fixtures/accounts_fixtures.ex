defmodule Conta.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Conta.Accounts` context.
  """
  use ExMachina.Ecto, repo: Conta.Repo
  alias Conta.Accounts.User
  alias Conta.Repo

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def hashed_password(password), do: Bcrypt.hash_pwd_salt(password)

  def user_factory do
    %User{
      email: unique_user_email(),
      hashed_password: hashed_password(valid_user_password())
    }
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def confirm_user(user) do
    Repo.update!(User.confirm_changeset(user))
  end
end
