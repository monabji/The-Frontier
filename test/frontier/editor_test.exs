defmodule Frontier.EditorTest do
  use Frontier.DataCase, async: false

  import Ecto.Query

  alias Frontier.Editions
  alias Frontier.Editor
  alias Frontier.EditorFixtures
  alias Frontier.Sources.Run

  @day ~D[2026-11-22]

  setup do
    stories = EditorFixtures.seed_stories(32)
    %{candidates: EditorFixtures.candidates(stories)}
  end

  defp reply(payload, opts \\ []) do
    {:ok,
     %{
       content: Jason.encode!(payload),
       usage: Keyword.get(opts, :usage, %{input_tokens: 1_200, output_tokens: 400}),
       model: Keyword.get(opts, :model, "test-model")
     }}
  end

  defp links_ok, do: fn _url -> {:ok, "https://example.com/final"} end

  defp edit(candidates, client, opts \\ []) do
    Editor.edit(
      @day,
      [candidates: candidates, client: client, link_checker: links_ok()] ++ opts
    )
  end

  defp candidate(candidates, id), do: Enum.find(candidates, &(&1.id == id))

  describe "a full day" do
    test "writes the edition, grounds it, and records tokens and cost", %{candidates: candidates} do
      payload = EditorFixtures.payload(candidates)

      assert {:ok, %{edition: edition, plan: plan, report: report}} =
               edit(candidates, fn _messages, _opts -> reply(payload) end)

      assert edition.status == "draft"
      assert plan.story_count == 22
      assert length(plan.tickers) == 10
      assert edition.desk_note =~ "busy morning"
      assert report.read_minutes in 8..10
      assert report.printed == 22
      assert report.rejected == 0
      assert report.input_tokens == 1_200
      assert report.output_tokens == 400
      assert report.cost_micros == 420
      assert Editions.rejections(@day) == []

      run =
        Repo.one!(
          from run in Run,
            where: run.stage == "edit" and run.edition_day == ^@day
        )

      assert run.status == "ok"
      assert run.model == "test-model"
      assert run.input_tokens == 1_200
      assert run.output_tokens == 400
      assert run.cost_micros == 420
      assert run.inserted == 32
      assert run.rejected == 0
    end

    test "the lead is the first Front Page entry and the story is printed once", %{
      candidates: candidates
    } do
      payload = EditorFixtures.payload(candidates)

      assert {:ok, %{edition: edition}} = edit(candidates, fn _m, _o -> reply(payload) end)

      sections = Editions.sections(edition)
      assert [{"Front Page", [lead | _]} | _] = sections
      assert lead.kind == "lead"

      urls = Enum.map(edition.entries, & &1.canonical_url)
      assert length(urls) == length(Enum.uniq(urls))
    end
  end

  describe "the day's pool" do
    test "the editor builds its candidates from the stored pool", %{candidates: candidates} do
      payload = EditorFixtures.payload(candidates)

      assert {:ok, %{plan: plan}} =
               Editor.edit(@day,
                 client: fn _m, _o -> reply(payload) end,
                 link_checker: links_ok()
               )

      assert plan.story_count == 22
    end
  end

  describe "grounding" do
    test "a hallucinated quote is rejected, repaired once, then dropped", %{
      candidates: candidates
    } do
      payload = EditorFixtures.payload(candidates)
      [first | rest] = payload["entries"]

      bad =
        Map.put(first, "quote", "The bakery was opened by a robot that nobody had seen before.")

      payload = %{payload | "entries" => [bad | rest]}

      assert {:ok, %{edition: edition, plan: plan}} =
               edit(candidates, fn _m, _o -> reply(payload) end)

      assert plan.story_count == 21
      refute Enum.any?(edition.entries, &(&1.story_id == bad["story_id"]))

      assert [rejection] = Editions.rejections(@day)
      assert rejection.story_id == bad["story_id"]
      assert rejection.reason == "quote_not_in_source"

      run = Repo.one!(from run in Run, where: run.stage == "edit")
      assert run.rejected == 1
    end

    test "a valid alternate quote prints without a repair call", %{candidates: candidates} do
      payload = EditorFixtures.payload(candidates)
      [first | rest] = payload["entries"]
      good_quote = EditorFixtures.verbatim_quote(candidate(candidates, first["story_id"]))

      bad =
        first
        |> Map.put("quote", "The bakery was opened by a robot that nobody had seen before.")
        |> Map.put("quote_candidates", [good_quote])

      payload = %{payload | "entries" => [bad | rest]}
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      client = fn _messages, _opts ->
        Agent.update(counter, &(&1 + 1))
        reply(payload)
      end

      assert {:ok, %{plan: plan, edition: edition}} = edit(candidates, client)

      assert plan.story_count == 22
      assert Editions.rejections(@day) == []
      assert Enum.find(edition.entries, &(&1.story_id == first["story_id"])).quote == good_quote
      assert Agent.get(counter, & &1) == 1
    end

    test "a repaired quote prints", %{candidates: candidates} do
      payload = EditorFixtures.payload(candidates)
      [first | rest] = payload["entries"]

      bad =
        Map.put(first, "quote", "The bakery was opened by a robot that nobody had seen before.")

      payload = %{payload | "entries" => [bad | rest]}
      good_quote = EditorFixtures.verbatim_quote(candidate(candidates, first["story_id"]))
      repair = %{"entries" => [Map.put(bad, "quote", good_quote)]}

      client = fn _messages, opts ->
        if opts[:repair], do: reply(repair), else: reply(payload)
      end

      assert {:ok, %{plan: plan, edition: edition}} = edit(candidates, client)

      assert plan.story_count == 22
      assert Editions.rejections(@day) == []
      assert Enum.find(edition.entries, &(&1.story_id == first["story_id"])).quote == good_quote
    end

    test "a dead link drops the story", %{candidates: candidates} do
      payload = EditorFixtures.payload(candidates)
      [first | _rest] = payload["entries"]
      dead_url = candidate(candidates, first["story_id"]).url

      checker = fn
        ^dead_url -> {:error, {:http_status, 404, "Not Found"}}
        _url -> {:ok, "https://example.com/final"}
      end

      {:ok, counter} = Agent.start_link(fn -> 0 end)

      assert {:ok, %{plan: plan}} =
               Editor.edit(@day,
                 candidates: candidates,
                 client: fn _m, _o ->
                   Agent.update(counter, &(&1 + 1))
                   reply(payload)
                 end,
                 link_checker: checker
               )

      assert plan.story_count == 21
      assert Enum.any?(Editions.rejections(@day), &(&1.reason == "unresolved_link"))

      # A dead link cannot be repaired by rewriting copy, so it costs one call.
      assert Agent.get(counter, & &1) == 1
    end
  end

  describe "the paper's shape" do
    test "a quiet day is shorter and never padded", %{candidates: candidates} do
      six = Enum.take(candidates, 6)
      payload = EditorFixtures.payload(six)
      payload = %{payload | "entries" => Enum.take(payload["entries"], 5)}

      assert {:ok, %{plan: plan, report: report}} =
               edit(six, fn _m, _o -> reply(payload) end)

      assert plan.story_count == 5
      assert plan.tickers == []
      assert report.read_minutes == 2
      assert plan.desk_note =~ "shorter than usual"
    end

    test "a full pool that produces a short paper is sent back for more", %{
      candidates: candidates
    } do
      payload = EditorFixtures.payload(candidates)
      first = %{payload | "entries" => Enum.take(payload["entries"], 10)}
      extra = %{"entries" => payload["entries"] |> Enum.drop(10) |> Enum.take(12)}

      {:ok, counter} = Agent.start_link(fn -> 0 end)

      client = fn _messages, opts ->
        Agent.update(counter, &(&1 + 1))
        if opts[:repair], do: reply(extra), else: reply(first)
      end

      assert {:ok, %{plan: plan}} = edit(candidates, client)
      assert plan.story_count == 22
      assert Agent.get(counter, & &1) == 2
    end

    test "a summary outside its word budget is sent back once", %{candidates: candidates} do
      payload = EditorFixtures.payload(candidates)
      [lead | rest] = payload["entries"]
      second = Enum.at(rest, 0)
      short = Map.put(second, "summary", String.duplicate("word ", 30) |> String.trim())
      payload = %{payload | "entries" => [lead, short | Enum.drop(rest, 1)]}

      repair = %{
        "entries" => [Map.put(short, "summary", EditorFixtures.summary(:standard))]
      }

      client = fn _messages, opts ->
        if opts[:repair], do: reply(repair), else: reply(payload)
      end

      assert {:ok, %{edition: edition}} = edit(candidates, client)

      entry = Enum.find(edition.entries, &(&1.story_id == second["story_id"]))
      assert entry.word_count == 70
      assert Editions.rejections(@day) == []
    end
  end

  describe "failures" do
    test "an API failure records a failed run and prints nothing", %{candidates: candidates} do
      assert {:error, {:editor_client, :timeout}} =
               edit(candidates, fn _m, _o -> {:error, :timeout} end)

      assert Editions.get(@day) == nil

      run = Repo.one!(from run in Run, where: run.stage == "edit")
      assert run.status == "error"
      assert run.error =~ "timeout"
    end

    test "an edition where nothing survives grounding is not written", %{candidates: candidates} do
      payload = EditorFixtures.payload(candidates)
      [first | _rest] = payload["entries"]
      bad = Map.put(first, "quote", "A fabricated sentence that no source ever contained.")
      payload = %{payload | "entries" => [bad], "also_today" => []}

      assert {:error, {:nothing_printed, _reasons}} =
               edit(candidates, fn _m, _o -> reply(payload) end)

      assert Editions.get(@day) == nil
      assert length(Editions.rejections(@day)) == 1
    end

    test "a published edition is never overwritten", %{candidates: candidates} do
      payload = EditorFixtures.payload(candidates)
      client = fn _m, _o -> reply(payload) end

      assert {:ok, _} = edit(candidates, client)
      assert {:ok, _} = Editions.publish(@day)
      assert {:error, {:edition_is_published, "published"}} = edit(candidates, client)
    end
  end
end
