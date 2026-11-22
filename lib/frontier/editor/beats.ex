defmodule Frontier.Editor.Beats do
  @moduledoc """
  Which beat a candidate probably belongs to, and how the beats are grouped
  into calls when the editor has to write the paper in parts.

  This is routing, not editing. A source is a strong prior — a Kubernetes post
  is DevOps, a Godot post is game development — and for mixed desks (Ars
  Technica, Hacker News) a headline is read against a small keyword table. The
  model still chooses the story, writes it and can place it in any section its
  part allows; the route only decides which candidates are worth showing it.
  """

  @source_sections %{
    "rss:openai" => "Models & Harnesses",
    "rss:huggingface" => "Models & Harnesses",
    "rss:deepmind" => "Models & Harnesses",
    "rss:googleai" => "Models & Harnesses",
    "rss:simonwillison" => "Models & Harnesses",
    "rss:thehackernews" => "Security",
    "rss:bleepingcomputer" => "Security",
    "rss:krebs" => "Security",
    "rss:gamedeveloper" => "Game Development",
    "rss:godot" => "Game Development",
    "rss:androiddev" => "App Development",
    "rss:reactnative" => "App Development",
    "rss:phoronix" => "FOSS",
    "rss:lwn" => "FOSS",
    "rss:kubernetes" => "DevOps",
    "rss:cncf" => "DevOps",
    "rss:quanta" => "Frontier Science",
    "rss:ieeespectrum" => "Frontier Science",
    "rss:quantumcomputingreport" => "Frontier Science",
    "rss:coindesk" => "Frontier Science",
    "rss:80lv" => "Design",
    "rss:smashing" => "Design",
    "rss:blender" => "Design",
    "bsky" => "Trending"
  }

  @keywords [
    {~r/(vulnerab|exploit|malware|ransom|breach|hacked|hacker|cve|zero[- ]day|phishing|botnet|security|backdoor)/i,
     "Security"},
    {~r/(game|gaming|engine|studio|playstation|xbox|nintendo|steam|godot|unity|unreal)/i,
     "Game Development"},
    {~r/(design|ui\/ux|\bux\b|\bui\b|3d|vfx|motion|render|blender|typograph)/i, "Design"},
    {~r/(kubernetes|docker|cloud|ci\/cd|infra|observab|\bsre\b|terraform|argo|devops)/i,
     "DevOps"},
    {~r/(open[- ]source|linux|kernel|github|licen[cs]e|fork|debian|fedora|rust|postgres|foss)/i,
     "FOSS"},
    {~r/(android|ios\b|app store|sdk|compose|react native|flutter|mobile|web app)/i,
     "App Development"},
    {~r/(quantum|protein|bioinform|genome|physics|cosmos|astronom|bitcoin|blockchain|\biot\b|sensor)/i,
     "Frontier Science"},
    {~r/(paper|research|study|benchmark|training|inference|dataset|proof|fine[- ]tun)/i,
     "Research"},
    {~r/(model|gemini|gpt|llama|agent|harness|\bapi\b)/i, "Models & Harnesses"}
  ]

  # One section per call. A small model asked for two sections will file a
  # security story under Research because both were allowed; asked for one, it
  # has nowhere else to put it. The whole paper is eleven short calls.
  @groups [
    ["Front Page"],
    ["Models & Harnesses"],
    ["Research"],
    ["Security"],
    ["Game Development"],
    ["App Development"],
    ["FOSS"],
    ["DevOps"],
    ["Frontier Science"],
    ["Design"],
    ["Trending"]
  ]

  @front_page_pool 14
  @group_pool 10

  @doc "The order the paper is written in, one section at a time."
  @spec groups() :: [[String.t()]]
  def groups, do: @groups

  @doc "The section a candidate is routed to."
  @spec section(map()) :: String.t()
  def section(candidate) do
    case Map.get(@source_sections, candidate.primary_source) do
      nil -> by_headline(candidate.headline)
      section when is_binary(section) -> section
    end
  end

  @doc """
  The candidates to show a part, in paper order, excluding stories already
  printed by an earlier part.
  """
  @spec group_candidates([String.t()], [map()], MapSet.t()) :: [map()]
  def group_candidates(group, candidates, used) do
    fresh = Enum.reject(candidates, &MapSet.member?(used, &1.id))

    cond do
      "Front Page" in group ->
        Enum.take(fresh, @front_page_pool)

      true ->
        fresh
        |> Enum.filter(&(section(&1) in group))
        |> Enum.take(@group_pool)
    end
  end

  defp by_headline(headline) when is_binary(headline) do
    Enum.find_value(@keywords, "Trending", fn {pattern, section} ->
      if Regex.match?(pattern, headline), do: section
    end)
  end

  defp by_headline(_headline), do: "Trending"
end
