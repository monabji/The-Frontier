defmodule FrontierWeb.ReaderFlowTest do
  use FrontierWeb.ConnCase

  alias Frontier.Profiles
  alias Frontier.Profiles.{Event, Profile}
  alias Frontier.Readers
  alias Frontier.Repo

  defp csrf(html) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, html)
    token
  end

  defp recovery_path(html) do
    [_, link] = Regex.run(~r{value="([^"]*/recover/[^"]+)"}, html)
    URI.parse(link).path
  end

  describe "onboarding" do
    test "a visit stores nothing; a save stores chips, accounts and one version", %{conn: conn} do
      html = get(conn, ~p"/start") |> html_response(200)

      assert html =~ "Models &amp; releases"
      assert html =~ "No email, no password, no account"
      assert html =~ ~s(href="/privacy")
      assert Repo.aggregate(Readers.Reader, :count) == 0

      get(build_conn(), ~p"/your-paper") |> html_response(200)
      assert Repo.aggregate(Readers.Reader, :count) == 0

      conn =
        post(conn, ~p"/start", %{
          "_csrf_token" => csrf(html),
          "chips" => ["models", "research"],
          "trusted_accounts" => "simonwillison.net"
        })

      assert redirected_to(conn) == "/your-paper"
      assert Repo.aggregate(Readers.Reader, :count) == 1
      assert Repo.aggregate(Profile, :count) == 1
      assert Repo.aggregate(Event, :count) == 3

      html = get(recycle(conn), ~p"/your-paper") |> html_response(200)
      assert html =~ "Models &amp; releases"
      assert html =~ "Research"
      assert html =~ "simonwillison.net"
      assert html =~ "/recover/"
    end
  end

  describe "thumbs" do
    test "a thumb appends an event and bumps the version", %{conn: conn} do
      html = get(conn, ~p"/start") |> html_response(200)

      conn =
        post(conn, ~p"/start", %{
          "_csrf_token" => csrf(html),
          "chips" => ["models"],
          "trusted_accounts" => ""
        })

      conn = recycle(conn)
      reader = Repo.one!(Readers.Reader)
      assert Profiles.current(reader).version == 1

      conn =
        post(conn, ~p"/thumbs", %{
          "_csrf_token" => csrf(get(conn, ~p"/your-paper") |> html_response(200)),
          "thumb" => %{
            "story" => "https://example.com/story",
            "value" => "up",
            "return" => "/",
            "edition_day" => "2026-11-22"
          }
        })

      assert redirected_to(conn) == "/?noted=thumb"

      profile = Profiles.current(reader)
      assert profile.version == 2
      assert profile.document["thumbs"] == %{"https://example.com/story" => "up"}

      [event] = Profiles.events(reader) |> Enum.take(-1)
      assert event.kind == "thumb_up"
      assert event.edition_day == ~D[2026-11-22]

      reader = Repo.one!(Readers.Reader)
      assert Profiles.current(reader).document["thumb_counts"] == %{"up" => 1, "down" => 0}
    end

    test "thumbing a malformed story is refused", %{conn: conn} do
      html = get(conn, ~p"/start") |> html_response(200)

      conn =
        post(conn, ~p"/thumbs", %{
          "_csrf_token" => csrf(html),
          "thumb" => %{"story" => "", "value" => "up"}
        })

      assert response(conn, 422) =~ "could not be saved"
    end
  end

  describe "the recovery link" do
    test "restores the profile in a browser with no cookie", %{conn: conn} do
      html = get(conn, ~p"/start") |> html_response(200)

      conn =
        post(conn, ~p"/start", %{
          "_csrf_token" => csrf(html),
          "chips" => ["models", "tooling"],
          "trusted_accounts" => "example.com"
        })

      html = get(recycle(conn), ~p"/your-paper") |> html_response(200)
      path = recovery_path(html)
      original = Repo.one!(Readers.Reader)

      # A different browser: no cookies at all. The GET is only a confirmation.
      confirmation_conn = get(build_conn(), path)
      confirmation = html_response(confirmation_conn, 200)
      assert confirmation =~ "Restore this paper"
      assert confirmation =~ "Anyone who has the link can restore it"

      {:ok, minted} = Readers.verify(confirmation_conn.resp_cookies["frontier_reader"].value)
      refute minted == original.public_id

      restored =
        post(recycle(confirmation_conn), path, %{"_csrf_token" => csrf(confirmation)})

      assert redirected_to(restored) == "/your-paper"

      html = get(recycle(restored), ~p"/your-paper") |> html_response(200)
      assert html =~ "Models &amp; releases"
      assert html =~ "Tools &amp; code"
      assert html =~ "example.com"
    end

    test "refuses to replace a different paper in the same browser", %{conn: conn} do
      html = get(conn, ~p"/start") |> html_response(200)

      conn =
        post(conn, ~p"/start", %{
          "_csrf_token" => csrf(html),
          "chips" => ["models"],
          "trusted_accounts" => ""
        })

      other = Readers.ensure(Readers.new_id())
      {:ok, _} = Profiles.onboard(other, ["research"], "")
      path = "/recover/" <> Readers.recovery_token(other.public_id)

      confirmation_conn = get(recycle(conn), path)
      confirmation = html_response(confirmation_conn, 200)
      assert confirmation =~ "different paper"

      paper = get(recycle(conn), ~p"/your-paper") |> html_response(200)

      refused =
        post(recycle(confirmation_conn), path, %{"_csrf_token" => csrf(paper)})

      assert response(refused, 409) =~ "different paper"

      html = get(recycle(refused), ~p"/your-paper") |> html_response(200)
      assert html =~ "Models &amp; releases"
      refute html =~ "Research"
    end

    test "a tampered recovery link is refused" do
      assert get(build_conn(), "/recover/not-a-real-token") |> response(404) =~ "not valid"
    end
  end

  describe "a tampered cookie" do
    test "is rejected and a fresh identity minted", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_req_header("cookie", "frontier_reader=not-a-real-token")
        |> get(~p"/start")

      assert html_response(conn, 200) =~ "Tell the paper"

      {:ok, minted} = Readers.verify(conn.resp_cookies["frontier_reader"].value)
      assert String.length(minted) == 22
      refute minted == "not-a-real-token"
      assert Repo.aggregate(Readers.Reader, :count) == 0
    end
  end

  describe "privacy" do
    test "says exactly what is stored", %{conn: conn} do
      html = get(conn, ~p"/privacy") |> html_response(200)

      assert html =~ "frontier_reader"
      assert html =~ "readers"
      assert html =~ "profiles"
      assert html =~ "profile_events"
      assert html =~ "two years"
      assert html =~ "No name, email address, phone number or password"
      assert html =~ "No IP address"
      assert html =~ "Forget this reader"
      assert html =~ "HttpOnly"
      assert html =~ "SameSite"
      assert html =~ "read and change it"
      assert html =~ "two years"
    end

    test "no table has an email, password or account column" do
      for table <- ["readers", "profiles", "profile_events"] do
        %{rows: rows} = Repo.query!("PRAGMA table_info(#{table})")
        columns = rows |> Enum.map(&Enum.at(&1, 1)) |> Enum.map(&String.downcase/1)

        refute Enum.any?(columns, &String.contains?(&1, "email"))
        refute Enum.any?(columns, &String.contains?(&1, "password"))
        refute Enum.any?(columns, &String.contains?(&1, "account"))
      end
    end
  end

  describe "forgetting" do
    test "erases the rows and clears the cookie", %{conn: conn} do
      html = get(conn, ~p"/start") |> html_response(200)

      conn =
        post(conn, ~p"/start", %{
          "_csrf_token" => csrf(html),
          "chips" => ["models"],
          "trusted_accounts" => "example.com"
        })

      conn = recycle(conn)
      html = get(conn, ~p"/your-paper") |> html_response(200)

      conn =
        post(conn, ~p"/forget", %{"_csrf_token" => csrf(html)})

      assert redirected_to(conn) == "/"
      assert Repo.aggregate(Readers.Reader, :count) == 0
      assert Repo.aggregate(Profile, :count) == 0
      assert Repo.aggregate(Event, :count) == 0
      assert conn.resp_cookies["frontier_reader"].max_age == 0
    end
  end
end
