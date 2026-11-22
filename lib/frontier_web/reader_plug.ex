defmodule FrontierWeb.ReaderPlug do
  @moduledoc """
  Reads the signed reader cookie, or mints one.

  This plug deliberately does not touch the database. A first visit gets a
  signed random id and nothing is stored until the reader saves a chip or a
  thumb, which keeps the shared artifact page readable with the database
  unqueried.
  """

  import Plug.Conn

  alias Frontier.Readers

  @spec init(term()) :: term()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case Readers.read_cookie(conn) do
      {:ok, public_id} ->
        assign(conn, :reader_id, public_id)

      :none ->
        public_id = Readers.new_id()
        conn |> Readers.put_cookie(public_id) |> assign(:reader_id, public_id)
    end
  end
end
