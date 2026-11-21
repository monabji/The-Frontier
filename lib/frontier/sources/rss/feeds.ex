defmodule Frontier.Sources.RSS.OpenAI do
  @moduledoc "OpenAI's news feed."
  use Frontier.Sources.RSS.Feed,
    key: "rss:openai",
    label: "OpenAI",
    url: "https://openai.com/news/rss.xml"
end

defmodule Frontier.Sources.RSS.HuggingFace do
  @moduledoc "The Hugging Face blog."
  use Frontier.Sources.RSS.Feed,
    key: "rss:huggingface",
    label: "Hugging Face",
    url: "https://huggingface.co/blog/feed.xml"
end

defmodule Frontier.Sources.RSS.DeepMind do
  @moduledoc "Google DeepMind's blog."
  use Frontier.Sources.RSS.Feed,
    key: "rss:deepmind",
    label: "DeepMind",
    url: "https://deepmind.google/blog/rss.xml"
end

defmodule Frontier.Sources.RSS.GoogleAI do
  @moduledoc "Google's AI blog."
  use Frontier.Sources.RSS.Feed,
    key: "rss:googleai",
    label: "Google AI",
    url: "https://blog.google/technology/ai/rss/"
end

defmodule Frontier.Sources.RSS.ArsTechnica do
  @moduledoc "Ars Technica, an independent technology publication."
  use Frontier.Sources.RSS.Feed,
    key: "rss:arstechnica",
    label: "Ars Technica",
    url: "https://arstechnica.com/feed/"
end

defmodule Frontier.Sources.RSS.SimonWillison do
  @moduledoc "Simon Willison's weblog, an Atom feed."
  use Frontier.Sources.RSS.Feed,
    key: "rss:simonwillison",
    label: "Simon Willison",
    url: "https://simonwillison.net/atom/everything/"
end
