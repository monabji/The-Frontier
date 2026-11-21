defmodule Frontier.Newsroom.DemoEdition do
  @moduledoc """
  The one story the paper prints while the press is being installed (phase 0).

  Hardcoded on purpose: nothing is fetched, clustered or stored yet. The story
  and its quote are taken from a single primary source, so the page rehearses
  the paper's real rule — one verbatim quote, one resolving link — rather than
  inventing copy. It is shaped like the edition a stored story will arrive in,
  so the page components survive the swap when the editor lands.

  Word counts are held to the paper's own editorial budget by
  `Frontier.Newsroom.DemoEditionTest`.
  """

  @spec current() :: map()
  def current do
    %{
      number: 1,
      label: "Pilot edition",
      published: "Morning edition, 06:00 IST",
      section: "Front Page",
      kicker: "The Lead",
      story: %{
        headline: "Thinking Machines releases a 26B model that runs on a laptop",
        dek:
          "Inkling 2 Mini is a looped transformer: three passes through its middle layers for every token, in about 20GB of weights.",
        source: %{
          name: "thinkingmachines.ai",
          url: "https://thinkingmachines.ai/news/inkling-2-mini/"
        },
        body: [
          "Thinking Machines Lab released Inkling 2 Mini this week: a mixture-of-experts " <>
            "model with 26.4B total parameters, 3.4B active, and about 20GB of weights. Most " <>
            "of it was trained in 4-bit precision and is deployed at the same precision, so " <>
            "nothing is converted afterwards. It runs on a MacBook with 32GB of memory, and " <>
            "on NVIDIA’s DGX Spark.",
          "The architecture is the argument. Inkling 2 Mini is a looped transformer: its two " <>
            "middle blocks run three times per token, 48 layer applications from 24 stored " <>
            "layers, buying reasoning without writing the reasoning down. That makes the " <>
            "chain of thought shorter and, the company says, no less legible. Looping does " <>
            "not add facts. It leads open-weights models under 100B parameters on agentic " <>
            "coding, while trailing Qwen3.8-27B on chat and constraint-heavy instructions. " <>
            "The weights are open."
        ],
        quote: %{
          text:
            "Today we are releasing Inkling 2 Mini, a fast, powerful model that’s small " <>
              "enough to run on your laptop.",
          attribution: "Quoted verbatim"
        }
      }
    }
  end
end
