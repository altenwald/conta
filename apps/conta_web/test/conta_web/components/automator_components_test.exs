defmodule ContaWeb.AutomatorComponentsTest do
  use ContaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Conta.Command.SetFilter
  alias ContaWeb.AutomatorComponents

  describe "test_param_input/1 for a :table param" do
    test "prefills the textarea with the given value" do
      param = %SetFilter.Param{name: "expenses", type: :table}

      raw_value = ~s([{"a":1}])

      html =
        render_component(&AutomatorComponents.test_param_input/1,
          param: param,
          value: raw_value
        )

      # The value is HTML-escaped (as Phoenix does for every interpolated
      # assign) so it round-trips safely even if it contains `<`, `>` or
      # `"` — a browser decodes the entities back to the original text
      # when displaying the <textarea>, so this is functionally a prefill.
      expected = raw_value |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      textarea_content =
        html
        |> Floki.parse_fragment!()
        |> Floki.find("textarea")
        |> Floki.text()

      assert textarea_content == expected
    end

    test "renders a Load real data button wired to load_table_sample" do
      param = %SetFilter.Param{name: "expenses", type: :table}

      html = render_component(&AutomatorComponents.test_param_input/1, param: param, value: nil)

      assert html =~ "Load real data"
      assert html =~ ~s(phx-click="load_table_sample")
      assert html =~ ~s(phx-value-param="expenses")
    end
  end
end
