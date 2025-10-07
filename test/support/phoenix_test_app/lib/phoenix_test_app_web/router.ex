defmodule PhoenixTestAppWeb.Router do
  use Phoenix.Router
  import Phoenix.Controller

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", PhoenixTestAppWeb do
    pipe_through :api
    get "/health", HealthController, :index
  end
end
