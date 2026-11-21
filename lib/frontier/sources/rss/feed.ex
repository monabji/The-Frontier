defmodule Frontier.Sources.RSS.Feed do
  @moduledoc """
  Turns one feed's address into one source adapter.

      defmodule Frontier.Sources.RSS.OpenAI do
        use Frontier.Sources.RSS.Feed,
          key: "rss:openai",
          label: "OpenAI",
          url: "https://openai.com/news/rss.xml"
      end

  Five lines of configuration instead of five copies of the same module, and
  each feed still gets its own key, its own run report and its own failure.
  """

  defmacro __using__(opts) do
    key = Keyword.fetch!(opts, :key)
    label = Keyword.fetch!(opts, :label)
    url = Keyword.fetch!(opts, :url)

    quote do
      @behaviour Frontier.Sources.Adapter

      @impl true
      def key, do: unquote(key)

      @impl true
      def label, do: unquote(label)

      @doc "The feed's address."
      def url, do: unquote(url)

      @impl true
      def fetch(opts \\ []), do: Frontier.Sources.RSS.fetch(unquote(url), opts)

      @impl true
      def normalize(payload), do: Frontier.Sources.RSS.normalize(payload)
    end
  end
end
