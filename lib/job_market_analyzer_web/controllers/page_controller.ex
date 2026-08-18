defmodule JobMarketAnalyzerWeb.PageController do
  use JobMarketAnalyzerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
