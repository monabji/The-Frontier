defmodule FrontierWeb.Router do
  use FrontierWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug FrontierWeb.ReaderPlug
    plug :fetch_live_flash
    plug :put_root_layout, html: {FrontierWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FrontierWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/archive", PageController, :archive
    get "/pool", PoolController, :index
    get "/start", ReaderController, :new
    post "/start", ReaderController, :create
    get "/your-paper", ReaderController, :paper
    get "/privacy", ReaderController, :privacy
    post "/forget", ReaderController, :forget
    post "/thumbs", ReaderController, :thumb
    get "/recover/:token", ReaderController, :recover
    get "/:year/:month/:day", PageController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", FrontierWeb do
  #   pipe_through :api
  # end
end
