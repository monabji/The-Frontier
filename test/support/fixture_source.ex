defmodule Frontier.FixtureSource do
  @moduledoc """
  A source adapter that fetches nothing: the morning pipeline's test peer.

  It produces one story with enough source text to quote, so a daily run can be
  exercised end to end without a network or a model.
  """

  @behaviour Frontier.Sources.Adapter

  alias Frontier.Sources.Item

  @impl true
  def key, do: "fixture"

  @impl true
  def label, do: "Fixture"

  @impl true
  def fetch(_opts), do: {:ok, :fixture}

  @impl true
  def normalize(:fixture) do
    {:ok,
     [
       %Item{
         external_id: "fixture-1",
         title: "Quokka One arrives with a new compiler",
         url: "https://example.com/quokka-one",
         kind: :post,
         text: text(),
         published_at: ~U[2026-11-22 04:00:00Z]
       }
     ]}
  end

  def normalize(_payload), do: {:error, :unexpected_payload}

  @doc "The sentence a fixture edition can quote verbatim."
  def quote, do: "Quokka One arrives with a new compiler."

  def text do
    quote() <>
      " The team said it cuts build times by half, and that existing projects can adopt it " <>
      "without changing their code. A second release is planned for the spring, with better " <>
      "diagnostics and a smaller runtime. The compiler is open source and the source is " <>
      "available today, the team said."
  end
end
