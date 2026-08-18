defmodule JobMarketAnalyzer.Repo do
  use Ecto.Repo,
    otp_app: :job_market_analyzer,
    adapter: Ecto.Adapters.SQLite3
end
