defmodule FrontierWeb.ReaderController do
  @moduledoc """
  Onboarding, the reader's own page, recovery, thumbs and the privacy page.

  Everything here is anonymous: the controller resolves the signed reader id,
  saves an append-only event, and renders. It never asks for a name, email or
  password, and it never shows another reader's profile.
  """

  use FrontierWeb, :controller

  alias Frontier.{Profiles, Readers}
  alias Frontier.Newsroom.Dateline
  alias Frontier.Profiles.Chips

  @noted_query "noted=thumb"

  plug :default_page

  defp default_page(conn, _opts) do
    conn
    |> assign(:page_title, "The Frontier")
    |> assign(
      :page_description,
      "The day in AI and technology, edited to be read in ten minutes."
    )
  end

  def new(conn, _params) do
    summary = summary_for(conn.assigns.reader_id)

    conn
    |> assign(:page_title, "Start — The Frontier")
    |> render(:start,
      chips: chip_views(),
      selected: Enum.map(summary.chips, &elem(&1, 0)),
      trusted_accounts: Enum.join(summary.trusted_accounts, ", "),
      csrf_token: get_csrf_token(),
      error: nil
    )
  end

  def create(conn, params) do
    reader = Readers.ensure(conn.assigns.reader_id)
    chips = List.wrap(params["chips"])

    case Profiles.onboard(reader, chips, params["trusted_accounts"] || "") do
      {:ok, _profile} ->
        redirect(conn, to: ~p"/your-paper")

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:start,
          chips: chip_views(),
          selected: chips,
          trusted_accounts: params["trusted_accounts"] || "",
          csrf_token: get_csrf_token(),
          error: "That could not be saved. Try again."
        )
    end
  end

  def paper(conn, _params) do
    summary = summary_for(conn.assigns.reader_id)
    token = Readers.recovery_token(conn.assigns.reader_id)

    conn
    |> assign(:page_title, "Your paper — The Frontier")
    |> render(:paper,
      summary: summary,
      recovery_url: url(conn, ~p"/recover/#{token}"),
      csrf_token: get_csrf_token()
    )
  end

  def recover(conn, %{"token" => token}) do
    case Readers.verify_recovery(token) do
      {:ok, public_id} ->
        conn
        |> Readers.put_cookie(public_id)
        |> redirect(to: ~p"/your-paper")

      {:error, _reason} ->
        conn
        |> put_status(:not_found)
        |> text("That recovery link is not valid.")
    end
  end

  def privacy(conn, _params) do
    conn
    |> assign(:page_title, "Privacy — The Frontier")
    |> assign(:page_description, "Exactly what The Frontier stores about an anonymous reader.")
    |> render(:privacy)
  end

  def forget(conn, _params) do
    case Readers.get(conn.assigns.reader_id) do
      nil -> :ok
      reader -> :ok = Profiles.forget(reader)
    end

    conn
    |> Readers.clear_cookie()
    |> redirect(to: "/")
  end

  def thumb(conn, %{"thumb" => %{"story" => story, "value" => value} = params}) do
    reader = Readers.ensure(conn.assigns.reader_id)
    day = parse_day(params["edition_day"]) || Dateline.edition_date()

    case Profiles.thumb(reader, story, day, value) do
      {:ok, _profile} ->
        redirect(conn, to: noted_path(params["return"]))

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> text("That thumb could not be saved.")
    end
  end

  def thumb(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> text("That thumb could not be saved.")
  end

  defp summary_for(public_id) do
    case Readers.get(public_id) do
      nil -> Profiles.empty_summary()
      reader -> Profiles.summary(reader)
    end
  end

  defp chip_views do
    Enum.map(Chips.all(), fn {key, label} -> %{key: key, label: label} end)
  end

  defp parse_day(nil), do: nil

  defp parse_day(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, day} -> day
      {:error, _reason} -> nil
    end
  end

  defp parse_day(_value), do: nil

  # Only a page of this paper may receive the reader back; anything else is
  # the front page. The thumb is a quiet acknowledgment, not a flash message.
  defp noted_path(nil), do: "/?" <> @noted_query

  defp noted_path(path) when is_binary(path) do
    if Regex.match?(~r"\A/(\d{4}/\d{2}/\d{2})?\z", path) do
      path <> "?" <> @noted_query
    else
      "/?" <> @noted_query
    end
  end

  defp noted_path(_path), do: "/?" <> @noted_query
end
