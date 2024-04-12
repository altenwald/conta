defmodule ContaWeb.Router do
  use ContaWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ContaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ContaWeb do
    pipe_through :browser

    get "/", PageController, :home

    scope "/books/invoices/" do
      live "/", InvoiceLive.Index, :index
      live "/new", InvoiceLive.Index, :new
      live "/:id/edit", InvoiceLive.Index, :edit

      live_session :default, root_layout: {ContaWeb.Layouts, :root_print} do
        live "/:id", InvoiceLive.Show, :show
      end
    end

    scope "/ledger/accounts/" do
      live "/", AccountLive.Index, :index
      live "/new", AccountLive.Index, :new
      live "/:id/edit", AccountLive.Index, :edit

      live "/:id", AccountLive.Show, :show
      live "/:id/show/edit", AccountLive.Show, :edit

      scope "/:account_id/entries/" do
        live "/", EntryLive.Index, :index
        live "/new", EntryLive.Index, :new
        live "/:id/edit", EntryLive.Index, :edit

        live "/:id", EntryLive.Show, :show
        live "/:id/show/edit", EntryLive.Show, :edit
      end
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", ContaWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:conta_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ContaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
