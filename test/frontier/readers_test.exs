defmodule Frontier.ReadersTest do
  use Frontier.DataCase, async: false

  alias Frontier.Readers
  alias Frontier.Readers.Reader

  describe "the anonymous id" do
    test "is random and unguessable" do
      first = Readers.new_id()
      second = Readers.new_id()

      assert first != second
      assert String.length(first) == 22
      assert first =~ ~r/\A[A-Za-z0-9_-]+\z/
    end

    test "a signed cookie round-trips and a changed one does not" do
      id = Readers.new_id()
      token = Readers.sign(id)

      assert {:ok, ^id} = Readers.verify(token)
      assert {:error, _reason} = Readers.verify(token <> "x")
    end

    test "a recovery token is a different key from the cookie" do
      id = Readers.new_id()
      recovery = Readers.recovery_token(id)

      assert {:ok, ^id} = Readers.verify_recovery(recovery)
      assert {:error, _reason} = Readers.verify(recovery)
    end

    test "the cookie holds the signed id, and reading it needs no database" do
      id = Readers.new_id()
      token = Readers.sign(id)

      conn =
        Plug.Test.conn(:get, "/")
        |> Plug.Conn.put_req_header("cookie", "#{Readers.cookie_name()}=#{token}")
        |> Plug.Conn.fetch_cookies()

      assert {:ok, ^id} = Readers.read_cookie(conn)
      assert Readers.cookie_name() == "frontier_reader"
      assert Readers.cookie_max_age() == 63_072_000
    end
  end

  describe "the cookie flags" do
    test "honours the secure flag used in production" do
      previous = Application.get_env(:frontier, :secure_cookies)
      Application.put_env(:frontier, :secure_cookies, true)

      on_exit(fn ->
        if previous do
          Application.put_env(:frontier, :secure_cookies, previous)
        else
          Application.delete_env(:frontier, :secure_cookies)
        end
      end)

      conn = Readers.put_cookie(Plug.Test.conn(:get, "/"), Readers.new_id())

      assert conn.resp_cookies[Readers.cookie_name()].secure
      assert conn.resp_cookies[Readers.cookie_name()].http_only
      assert conn.resp_cookies[Readers.cookie_name()].same_site == "Lax"
    end
  end

  describe "the reader row" do
    test "is created on first save and kept on the next" do
      id = Readers.new_id()
      first = Readers.ensure(id)

      assert first.public_id == id
      assert first.first_seen_at
      assert first.last_seen_at

      second = Readers.ensure(id)
      assert second.id == first.id
      assert second.first_seen_at == first.first_seen_at
    end

    test "a public id cannot be changed by an update" do
      reader = Readers.ensure(Readers.new_id())

      changeset = Reader.changeset(reader, %{public_id: "changed-to-someone-else"})

      refute Ecto.Changeset.get_change(changeset, :public_id)
    end

    test "touching records a later last-seen without touching the profile" do
      reader = Readers.ensure(Readers.new_id())
      touched = Readers.touch(reader)

      assert touched.id == reader.id
      assert DateTime.compare(touched.last_seen_at, reader.last_seen_at) != :lt
    end
  end
end
