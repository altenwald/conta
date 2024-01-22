defmodule ContaTest do
  use ExUnit.Case
  import Commanded.Assertions.EventAssertions

  test "ensure a create account event is published" do
    command =
      %Conta.Command.CreateAccount{
        name: ["Assets"],
        type: :assets,
        currency: :EUR,
        notes: nil,
        ledger: "default"
      }

    assert :ok = Conta.Commanded.Application.dispatch(command)

    assert_receive_event(Conta.Commanded.Application, Conta.Event.AccountCreated, fn event ->
      assert event.name == ["Assets"]
      assert event.type == "assets"
      assert event.currency == "EUR"
      assert is_nil(event.notes)
      assert event.ledger == "default"
    end)
  end

  test "fail if the parent doesn't exist" do
    command =
      %Conta.Command.CreateAccount{
        name: ["NonExist", "Child"],
        type: :assets,
        currency: :EUR,
        notes: nil,
        ledger: "default"
      }

    assert {:error, :invalid_parent_account} = Conta.Commanded.Application.dispatch(command)
  end
end
