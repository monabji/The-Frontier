defmodule Frontier.Editor.Client.DeskTest do
  use ExUnit.Case, async: true

  alias Frontier.Editor.Client.Desk

  @reply ~s({"desk_note":"A day.","entries":[]})

  describe "a pasted reply" do
    test "is returned as the editor's JSON content" do
      assert {:ok, %{content: content, usage: usage, model: model}} =
               Desk.complete([], reply: @reply, desk_model: "chatgpt")

      assert Jason.decode!(content) == %{"desk_note" => "A day.", "entries" => []}
      assert usage == %{input_tokens: 0, output_tokens: 0}
      assert model == "desk:chatgpt"
    end

    test "reads a reply from a file when given a path" do
      path =
        Path.join(System.tmp_dir!(), "frontier-desk-#{System.unique_integer([:positive])}.json")

      File.write!(path, @reply)
      on_exit(fn -> File.rm(path) end)

      assert {:ok, %{content: content}} = Desk.complete([], reply: path)
      assert Jason.decode!(content)["desk_note"] == "A day."
    end

    test "strips a code fence" do
      fenced = "```json\n#{@reply}\n```"

      assert {:ok, %{content: content}} = Desk.complete([], reply: fenced)
      assert Jason.decode!(content)["desk_note"] == "A day."
    end

    test "finds the object after a sentence of preamble" do
      chatty =
        "Here is the edition you asked for:\n\n#{@reply}\n\nLet me know if you want changes."

      assert {:ok, %{content: content}} = Desk.complete([], reply: chatty)
      assert Jason.decode!(content)["desk_note"] == "A day."
    end

    test "refuses text that is not JSON" do
      assert {:error, {:reply_not_json, _reason}} =
               Desk.complete([], reply: "I cannot help with that.")
    end

    test "refuses an empty reply" do
      assert {:error, :missing_reply} = Desk.complete([], [])
    end
  end

  describe "the recorded model" do
    test "names the assistant, or says just desk" do
      assert Desk.model(desk_model: "claude") == "desk:claude"
      assert Desk.model([]) == "desk"
      assert Desk.model(desk_model: "  ") == "desk"
    end
  end
end
