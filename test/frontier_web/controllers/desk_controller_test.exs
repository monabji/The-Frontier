defmodule FrontierWeb.DeskControllerTest do
  use FrontierWeb.ConnCase, async: false

  alias Frontier.{EditionStorage, Editions}
  alias Frontier.EditorFixtures

  @day ~D[2026-11-22]
  @token "desk-test-token"

  setup do
    EditionStorage.tmp!(%{})

    previous_token = Application.get_env(:frontier, :desk_token)
    previous_checker = Application.get_env(:frontier, :desk_link_checker)

    Application.put_env(:frontier, :desk_token, @token)

    Application.put_env(:frontier, :desk_link_checker, fn _url ->
      {:ok, "https://example.com/final"}
    end)

    on_exit(fn ->
      restore(:desk_token, previous_token)
      restore(:desk_link_checker, previous_checker)
    end)

    stories = EditorFixtures.seed_stories(32)
    %{payload: EditorFixtures.payload(EditorFixtures.candidates(stories))}
  end

  defp restore(key, nil), do: Application.delete_env(:frontier, key)
  defp restore(key, value), do: Application.put_env(:frontier, key, value)

  defp csrf(html) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, html)
    token
  end

  describe "the desk is closed without its token" do
    test "GET /desk is not found", %{conn: conn} do
      assert conn |> get(~p"/desk") |> response(404) == "Not found"
    end

    test "a wrong token is not found", %{conn: conn} do
      assert conn |> get(~p"/desk?token=nope") |> response(404)
    end

    test "POST /desk needs the token before it reads the reply", %{conn: conn} do
      assert conn |> post(~p"/desk", %{"reply" => "{}"}) |> response(404)
    end
  end

  describe "GET /desk" do
    test "prints the brief and the reply form", %{conn: conn} do
      html = conn |> get(~p"/desk?token=#{@token}") |> html_response(200)

      assert html =~ "The brief"
      assert html =~ "Front Page: 3"
      assert html =~ "Copy the brief"
      assert html =~ "Ground and assemble"
    end
  end

  describe "POST /desk" do
    test "refuses a reply that is not JSON", %{conn: conn} do
      html = conn |> get(~p"/desk?token=#{@token}") |> html_response(200)

      response =
        conn
        |> post(~p"/desk", %{
          "_csrf_token" => csrf(html),
          "token" => @token,
          "day" => Date.to_iso8601(@day),
          "assistant" => "gemini",
          "reply" => "Here is a summary in prose."
        })
        |> html_response(422)

      assert response =~ "not JSON"
    end

    test "grounds a pasted edition and offers to publish it", %{conn: conn, payload: payload} do
      html = conn |> get(~p"/desk?token=#{@token}") |> html_response(200)

      response =
        conn
        |> post(~p"/desk", %{
          "_csrf_token" => csrf(html),
          "token" => @token,
          "day" => Date.to_iso8601(@day),
          "assistant" => "chatgpt",
          "reply" => Jason.encode!(payload)
        })
        |> html_response(200)

      assert response =~ "Assembled"
      assert response =~ "Publish this edition"
      assert response =~ "desk:chatgpt"

      edition = Editions.get(@day)
      assert edition.status == "draft"
      assert length(edition.entries) == 26
    end
  end

  describe "POST /desk/publish" do
    test "publishes the assembled draft and sends the reader to the paper", %{
      conn: conn,
      payload: payload
    } do
      html = conn |> get(~p"/desk?token=#{@token}") |> html_response(200)

      assembled =
        conn
        |> post(~p"/desk", %{
          "_csrf_token" => csrf(html),
          "token" => @token,
          "day" => Date.to_iso8601(@day),
          "assistant" => "chatgpt",
          "reply" => Jason.encode!(payload)
        })
        |> html_response(200)

      conn =
        post(conn, ~p"/desk/publish", %{
          "_csrf_token" => csrf(assembled),
          "token" => @token,
          "day" => Date.to_iso8601(@day)
        })

      assert redirected_to(conn) == "/"
      assert Editions.get(@day).status == "published"
    end
  end
end
