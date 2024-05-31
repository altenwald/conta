defmodule ContaWeb.Router do
  use ContaWeb, :router

  import ContaWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ContaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :printer do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {ContaWeb.Layouts, :root_print}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

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

  scope "/", ContaWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{ContaWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/register", UserLive.Registration, :new
      live "/signin", UserLive.Signin, :new
      live "/reset-password", UserLive.ForgotPassword, :new
      live "/reset-password/:token", UserLive.ResetPassword, :edit
    end

    post "/signin", UserSessionController, :create
  end

  scope "/", ContaWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{ContaWeb.UserAuth, :ensure_authenticated}] do
      scope "/users/", UserLive do
        live "/settings", Settings, :edit
        live "/settings/confirm-email/:token", Settings, :confirm_email
      end

      scope "/books/invoices/" do
        live "/", InvoiceLive.Index, :index
        live "/new", InvoiceLive.Index, :new
        live "/:id/edit", InvoiceLive.Index, :edit

        scope "/" do
          pipe_through :printer

          get "/:id", InvoiceController, :show
          get "/:id/download", InvoiceController, :download
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
          live "/:id/duplicate", EntryLive.Index, :duplicate

          live "/:id", EntryLive.Show, :show
          live "/:id/show/edit", EntryLive.Show, :edit
        end
      end
    end
  end

  scope "/", ContaWeb do
    pipe_through [:browser]

    get "/", PageController, :home
    get "/logout", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{ContaWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserLive.Confirmation, :edit
      live "/users/confirm", UserLive.ConfirmationInstructions, :new
    end
  end
end
