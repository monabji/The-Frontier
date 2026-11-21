defmodule FrontierWeb.PoolControllerTest do
  use FrontierWeb.ConnCase

  alias Frontier.ClusteringFixtures
  alias Frontier.Newsroom.{Dateline, Pool}

  describe "GET /pool with a clustered pool" do
    setup do
      day = Dateline.edition_date()
      items = ClusteringFixtures.seed!(day)
      Pool.rebuild(day, items: items)
      :ok
    end

    test "shows each story with the items it was made from", %{conn: conn} do
      html = get(conn, ~p"/pool") |> html_response(200)

      assert html =~ "The pool"
      assert html =~ "Welcome Inkling 2 Mini"
      assert html =~ "3 items"
      assert html =~ "3 sources"
    end

    test "names each item's source and role", %{conn: conn} do
      html = get(conn, ~p"/pool") |> html_response(200)

      assert html =~ "primary"
      assert html =~ "discussion"
      assert html =~ "rss:huggingface"
      assert html =~ "hn"
      assert html =~ "bsky"
    end

    test "lists the primary item first", %{conn: conn} do
      html = get(conn, ~p"/pool") |> html_response(200)

      [_head | items] = String.split(html, ~s(class="pool-item">))

      assert hd(items) =~ "primary"
      assert Enum.join(tl(items), " ") =~ "discussion"
    end

    test "shows the cluster key, so a bad merge is traceable", %{conn: conn} do
      html = get(conn, ~p"/pool") |> html_response(200)

      assert html =~ "url:https://huggingface.co/blog/inkling2mini"
    end
  end

  test "GET /pool before clustering says what to run", %{conn: conn} do
    html = get(conn, ~p"/pool") |> html_response(200)

    assert html =~ "Nothing clustered yet"
    assert html =~ "mix frontier.cluster"
  end

  test "the pool page is not linked from the paper", %{conn: conn} do
    html = get(conn, ~p"/") |> html_response(200)

    refute html =~ ~s(href="/pool")
  end
end
