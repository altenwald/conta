defmodule Conta.Domain.Expense do
  @categories ~w[
    computers
    bank_fees
    gasoline
    shipping_costs
    representation_expenses
    accounting_fees
    printing_and_stationery
    motor_vehicle_tax
    professional_literature
    motor_vehicle_maintenance
    office_supplies
    other_vehicle_costs
    other_general_costs
    advertising
    vehicle_insurances
    general_insurances
    software
    subscriptions
    phone_and_internet
    transport
    travel_and_accommodation
    web_hosting_or_platforms
  ]a

  def categories, do: @categories
end
