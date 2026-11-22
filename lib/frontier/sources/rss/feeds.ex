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

# Security: a trade paper, a breaking-news desk, and the reporter who reads the
# advisories before anyone else.
defmodule Frontier.Sources.RSS.TheHackerNews do
  @moduledoc "The Hacker News, a security trade publication."
  use Frontier.Sources.RSS.Feed,
    key: "rss:thehackernews",
    label: "The Hacker News",
    url: "https://feeds.feedburner.com/TheHackersNews"
end

defmodule Frontier.Sources.RSS.BleepingComputer do
  @moduledoc "BleepingComputer, security news and malware reporting."
  use Frontier.Sources.RSS.Feed,
    key: "rss:bleepingcomputer",
    label: "BleepingComputer",
    url: "https://www.bleepingcomputer.com/feed/"
end

defmodule Frontier.Sources.RSS.Krebs do
  @moduledoc "Krebs on Security."
  use Frontier.Sources.RSS.Feed,
    key: "rss:krebs",
    label: "Krebs on Security",
    url: "https://krebsonsecurity.com/feed/"
end

# Game development: the trade paper and the engine that ships its own notes.
defmodule Frontier.Sources.RSS.GameDeveloper do
  @moduledoc "Game Developer, the game-industry trade publication."
  use Frontier.Sources.RSS.Feed,
    key: "rss:gamedeveloper",
    label: "Game Developer",
    url: "https://www.gamedeveloper.com/rss.xml"
end

defmodule Frontier.Sources.RSS.Godot do
  @moduledoc "The Godot engine's news feed."
  use Frontier.Sources.RSS.Feed,
    key: "rss:godot",
    label: "Godot",
    url: "https://godotengine.org/rss.xml"
end

# App development: the two platform blogs that ship the releases app teams
# actually build against.
defmodule Frontier.Sources.RSS.AndroidDevelopers do
  @moduledoc "Android Developers' blog."
  use Frontier.Sources.RSS.Feed,
    key: "rss:androiddev",
    label: "Android Developers",
    url: "https://android-developers.googleblog.com/feeds/posts/default"
end

defmodule Frontier.Sources.RSS.ReactNative do
  @moduledoc "The React Native blog."
  use Frontier.Sources.RSS.Feed,
    key: "rss:reactnative",
    label: "React Native",
    url: "https://reactnative.dev/blog/rss.xml"
end

# Open source: the two desks that follow the kernel and the projects around it.
defmodule Frontier.Sources.RSS.Phoronix do
  @moduledoc "Phoronix, Linux and open-source hardware news."
  use Frontier.Sources.RSS.Feed,
    key: "rss:phoronix",
    label: "Phoronix",
    url: "https://www.phoronix.com/rss.php"
end

defmodule Frontier.Sources.RSS.LWN do
  @moduledoc "LWN's headlines."
  use Frontier.Sources.RSS.Feed,
    key: "rss:lwn",
    label: "LWN",
    url: "https://lwn.net/headlines/rss"
end

# DevOps: the project that runs the cluster and the foundation around it.
defmodule Frontier.Sources.RSS.Kubernetes do
  @moduledoc "The Kubernetes blog."
  use Frontier.Sources.RSS.Feed,
    key: "rss:kubernetes",
    label: "Kubernetes",
    url: "https://kubernetes.io/feed.xml"
end

defmodule Frontier.Sources.RSS.CNCF do
  @moduledoc "The Cloud Native Computing Foundation's blog."
  use Frontier.Sources.RSS.Feed,
    key: "rss:cncf",
    label: "CNCF",
    url: "https://www.cncf.io/feed/"
end

# Frontier science: maths, physics and biology for technologists; quantum and
# blockchain get their own desks so those beats are not drowned by AI.
defmodule Frontier.Sources.RSS.Quanta do
  @moduledoc "Quanta Magazine, mathematics, physics and biology."
  use Frontier.Sources.RSS.Feed,
    key: "rss:quanta",
    label: "Quanta",
    url: "https://www.quantamagazine.org/feed/"
end

defmodule Frontier.Sources.RSS.IEEESpectrum do
  @moduledoc "IEEE Spectrum, engineering and applied science."
  use Frontier.Sources.RSS.Feed,
    key: "rss:ieeespectrum",
    label: "IEEE Spectrum",
    url: "https://spectrum.ieee.org/feeds/feed.rss"
end

defmodule Frontier.Sources.RSS.QuantumComputingReport do
  @moduledoc "The Quantum Computing Report."
  use Frontier.Sources.RSS.Feed,
    key: "rss:quantumcomputingreport",
    label: "Quantum Computing Report",
    url: "https://quantumcomputingreport.com/feed/"
end

defmodule Frontier.Sources.RSS.CoinDesk do
  @moduledoc "CoinDesk, blockchain and crypto news."
  use Frontier.Sources.RSS.Feed,
    key: "rss:coindesk",
    label: "CoinDesk",
    url: "https://www.coindesk.com/arc/outboundfeeds/rss/"
end

# Design: 3D and VFX, interface craft, and the open-source 3D suite.
defmodule Frontier.Sources.RSS.EightyLV do
  @moduledoc "80.lv, 3D, VFX and game art."
  use Frontier.Sources.RSS.Feed,
    key: "rss:80lv",
    label: "80.lv",
    url: "https://80.lv/feed/"
end

defmodule Frontier.Sources.RSS.SmashingMagazine do
  @moduledoc "Smashing Magazine, UI, UX and front-end craft."
  use Frontier.Sources.RSS.Feed,
    key: "rss:smashing",
    label: "Smashing Magazine",
    url: "https://www.smashingmagazine.com/feed/"
end

defmodule Frontier.Sources.RSS.Blender do
  @moduledoc "The Blender Foundation's news feed."
  use Frontier.Sources.RSS.Feed,
    key: "rss:blender",
    label: "Blender",
    url: "https://www.blender.org/feed/"
end
